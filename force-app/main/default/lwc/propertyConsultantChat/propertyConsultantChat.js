import { LightningElement, api, track } from 'lwc';
import searchProperties from '@salesforce/apex/PropertyChatController.searchProperties';
import getPropertyDetail from '@salesforce/apex/PropertyChatController.getPropertyDetail';

/**
 * The Property Consultant chat window for the Real Estate Property Portal.
 *
 * The point of this component is the part a standard chat window cannot do:
 * a reply is not only text. A shortlist comes back as a horizontal rail of
 * picture cards, and one property comes back as a detail card with its whole
 * gallery - the images being files linked to the Property record and marked
 * shareable with visitors.
 *
 * Every message in `messages` carries a `kind`, and the template renders a
 * different block per kind. Adding a new reply shape means adding a kind here
 * and a branch in the template, nothing more.
 */

const BUDGET_BANDS = [
    { test: /under\s*(?:1|one)\s*cr|below\s*(?:1|one)\s*cr|less than\s*(?:1|one)\s*cr/i, min: null, max: 10000000 },
    { test: /\b1\s*-\s*3\s*cr|between\s*1\s*and\s*3/i, min: 10000000, max: 30000000 },
    { test: /\b3\s*-\s*6\s*cr/i, min: 30000000, max: 60000000 },
    { test: /\b6\s*-\s*12\s*cr/i, min: 60000000, max: 120000000 },
    { test: /above\s*12\s*cr|over\s*12\s*cr|12\s*cr\s*(?:and|\+)/i, min: 120000000, max: null }
];

const CONFIG_PATTERN = /\b([1-6])\s*(?:\.5\s*)?bhk\b/i;

/** Cities the portfolio runs in. Matched case-insensitively, longest first. */
const CITIES = ['Gurugram', 'Gurgaon', 'Faridabad', 'Noida', 'Delhi', 'Ghaziabad', 'Mumbai', 'Pune', 'Bengaluru'];

const GREETING = /^\s*(hi|hey|hello|namaste|good\s*(morning|afternoon|evening))\b/i;
const THANKS = /\b(thanks|thank you|shukriya|dhanyavad)\b/i;

let messageSeq = 0;
const nextId = () => `m${++messageSeq}`;

export default class PropertyConsultantChat extends LightningElement {
    // ------------------------------------------------------- design settings
    @api agentName = 'Property Consultant';
    @api agentTagline = 'Online · replies instantly';
    @api brandName = 'DLF';
    @api welcomeMessage =
        'Hello! I am your Property Consultant. Tell me a city, a configuration or a budget and I will pull up the residences with photographs.';
    @api launcherLabel = 'Chat with a consultant';
    /** Opens the window on page load. Off by default so the page is not hijacked. */
    @api openOnLoad = false;

    // -------------------------------------------------------- runtime state
    @track messages = [];
    draft = '';
    isOpen = false;
    isMinimised = false;
    isThinking = false;

    /** Set while a detail card is open, so "book a visit" knows what about. */
    activeProperty = null;

    connectedCallback() {
        this.isOpen = this.openOnLoad === true;
        this.pushAgentText(this.welcomeMessage);
        this.pushChips([
            '3 BHK in Gurugram',
            'Show me everything',
            'Under 1 Cr',
            'Ready to move'
        ]);
    }

    // ------------------------------------------------------------ open/close

    handleLauncher() {
        this.isOpen = true;
        this.isMinimised = false;
        this.focusInput();
    }

    handleMinimise() {
        this.isMinimised = !this.isMinimised;
    }

    handleClose() {
        this.isOpen = false;
        this.isMinimised = false;
    }

    // --------------------------------------------------------------- sending

    handleDraft(event) {
        this.draft = event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.send();
        }
    }

    handleSend() {
        this.send();
    }

    handleChip(event) {
        this.ask(event.currentTarget.dataset.chip);
    }

    send() {
        const text = (this.draft || '').trim();
        if (!text) {
            return;
        }
        this.draft = '';
        this.ask(text);
    }

    async ask(text) {
        this.pushVisitorText(text);
        this.isThinking = true;
        try {
            await this.respondTo(text);
        } catch (error) {
            this.pushAgentText(this.readError(error));
        } finally {
            this.isThinking = false;
            this.scrollToLatest();
        }
    }

    // ------------------------------------------------------------- responses

    /**
     * Reads the intent off the visitor's line and answers with the right card
     * shape. Order matters: a named property beats a filter search, because
     * "tell me about DLF Camellias" mentions no city but means one property.
     */
    async respondTo(text) {
        if (GREETING.test(text) && text.trim().split(/\s+/).length <= 3) {
            this.pushAgentText(
                `Good to see you. I look after the ${this.brandName} portfolio - tell me where you are looking and what size, and I will show you what is available.`
            );
            this.pushChips(['3 BHK in Gurugram', 'Show me everything', 'Under 1 Cr']);
            return;
        }

        if (THANKS.test(text) && text.trim().split(/\s+/).length <= 4) {
            this.pushAgentText('Happy to help. Ask me any time - I am here after hours too.');
            return;
        }

        const filters = this.readFilters(text);

        // A specific project name: answer with the full detail card.
        const named = this.readPropertyName(text);
        if (named) {
            const detail = await getPropertyDetail({ propertyIdOrName: named });
            if (detail) {
                this.showDetail(detail);
                return;
            }
            this.pushAgentText(
                `I could not find a project called "${named}". Here is what is available instead.`
            );
        }

        const results = await searchProperties({
            city: filters.city,
            configuration: filters.configuration,
            priceMin: filters.priceMin,
            priceMax: filters.priceMax,
            nameLike: null
        });

        if (!results.length) {
            this.pushAgentText(
                'Nothing in the portfolio matches that combination right now. Try a wider budget, or a different city - our advisors can also source off-market inventory.'
            );
            this.pushChips(['Show me everything', 'Gurugram', 'Noida']);
            return;
        }

        this.pushAgentText(this.searchHeadline(results.length, filters));
        this.pushMessage({
            kind: 'properties',
            isProperties: true,
            cards: results.map((card) => this.decorateCard(card))
        });
    }

    /** Loads and shows one property, with its gallery. */
    async openProperty(key) {
        this.isThinking = true;
        try {
            const detail = await getPropertyDetail({ propertyIdOrName: key });
            if (!detail) {
                this.pushAgentText('That project is no longer listed. Ask me for the current collection.');
                return;
            }
            this.showDetail(detail);
        } catch (error) {
            this.pushAgentText(this.readError(error));
        } finally {
            this.isThinking = false;
            this.scrollToLatest();
        }
    }

    handleCardClick(event) {
        this.openProperty(event.currentTarget.dataset.id);
    }

    handleCardKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.openProperty(event.currentTarget.dataset.id);
        }
    }

    showDetail(detail) {
        this.activeProperty = detail;
        this.pushAgentText(`Here is ${detail.name}.`);
        this.pushMessage({
            kind: 'detail',
            isDetail: true,
            detail: this.decorateDetail(detail)
        });
        const chips = ['Book a site visit'];
        if (detail.documents && detail.documents.length) {
            chips.push('Send me the brochure');
        }
        chips.push('Show me something else');
        this.pushChips(chips);
    }

    // --------------------------------------------------------- intent reading

    readFilters(text) {
        const filters = { city: null, configuration: null, priceMin: null, priceMax: null };

        const city = CITIES.find((c) => new RegExp(`\\b${c}\\b`, 'i').test(text));
        if (city) {
            // Gurgaon and Gurugram are the same market; the data uses one name.
            filters.city = city.toLowerCase() === 'gurgaon' ? 'Gurugram' : city;
        }

        const config = CONFIG_PATTERN.exec(text);
        if (config) {
            filters.configuration = `${config[1]} BHK`;
        }

        const band = BUDGET_BANDS.find((b) => b.test.test(text));
        if (band) {
            filters.priceMin = band.min;
            filters.priceMax = band.max;
        } else {
            // "around 4 cr" / "budget 2.5 crore" - read it as a ceiling.
            const loose = /(\d+(?:\.\d+)?)\s*(?:cr|crore)/i.exec(text);
            if (loose) {
                filters.priceMax = Math.round(parseFloat(loose[1]) * 10000000);
            }
        }

        return filters;
    }

    /**
     * Pulls a project name out of "tell me about X" / "show me X" / "details of X".
     * Deliberately narrow: a bare city or a bare configuration must not be
     * mistaken for a project, or every search would become a detail lookup.
     */
    readPropertyName(text) {
        const patterns = [
            /(?:tell me about|details? (?:of|for|about)|more about|show me details of|info(?:rmation)? (?:on|about))\s+(.+?)\s*[?.!]*$/i,
            /^\s*(?:show|open)\s+(?!me\b|all\b|everything\b)(.+?)\s*[?.!]*$/i
        ];
        for (const pattern of patterns) {
            const found = pattern.exec(text);
            if (!found) {
                continue;
            }
            const candidate = found[1].trim();
            const isBareFilter =
                CONFIG_PATTERN.test(candidate) ||
                CITIES.some((c) => new RegExp(`^${c}$`, 'i').test(candidate)) ||
                /^(properties|projects|options|everything|all)$/i.test(candidate);
            if (!isBareFilter && candidate.length >= 3) {
                return candidate;
            }
        }
        return null;
    }

    searchHeadline(count, filters) {
        const parts = [];
        if (filters.configuration) {
            parts.push(filters.configuration);
        }
        if (filters.city) {
            parts.push(`in ${filters.city}`);
        }
        const what = parts.length ? parts.join(' ') : 'residences';
        const noun = count === 1 ? 'option' : 'options';
        return `I found ${count} ${noun} — ${what}. Tap a card to see the photographs and full details.`;
    }

    // ----------------------------------------------------------- card shaping

    /** Adds the presentation-only flags the template needs. */
    decorateCard(card) {
        return {
            ...card,
            hasImage: Boolean(card.heroImageUrl),
            // No photograph means no picture frame at all - a placeholder tile
            // reads as a failed image rather than as a project without photos.
            hasNoImage: !card.heroImageUrl,
            hasExtraImages: card.imageCount > 1,
            extraImagesLabel: `+${card.imageCount - 1} photos`,
            statusClass: this.statusClass(card.status),
            // The badge normally sits over the photograph; without one it moves
            // into the body, where it needs static rather than absolute placing.
            statusClassInline: `${this.statusClass(card.status)} chip--inline`,
            altText: `${card.name}, ${card.city || ''}`.trim()
        };
    }

    decorateDetail(detail) {
        const images = (detail.images || []).map((image, index) => ({
            ...image,
            key: image.contentVersionId,
            isHero: index === 0,
            altText: `${detail.name} — ${image.title}`
        }));
        return {
            ...detail,
            hero: images.length ? images[0] : null,
            hasHero: images.length > 0,
            thumbnails: images.slice(1),
            hasThumbnails: images.length > 1,
            hasImages: images.length > 0,
            hasDocuments: Boolean(detail.documents && detail.documents.length),
            hasAmenities: Boolean(detail.amenities && detail.amenities.length),
            hasSpecifications: Boolean(detail.specifications && detail.specifications.length),
            hasMediators: Boolean(detail.mediators && detail.mediators.length),
            specifications: (detail.specifications || []).map((spec, index) => ({
                ...spec,
                key: `${detail.recordId}-spec-${index}`,
                carpetText: spec.carpetArea ? `${spec.carpetArea} sq ft carpet` : null,
                builtUpText: spec.builtUpArea ? `${spec.builtUpArea} sq ft built-up` : null
            })),
            documents: (detail.documents || []).map((doc) => ({
                ...doc,
                key: doc.contentVersionId,
                label: doc.documentType || doc.title,
                sizeText: this.sizeText(doc.sizeBytes)
            })),
            amenities: (detail.amenities || []).map((amenity) => ({ key: amenity, label: amenity })),
            mediators: (detail.mediators || []).map((mediator) => ({
                ...mediator,
                key: mediator.recordId,
                callHref: mediator.mobilePhone || mediator.phone ? `tel:${mediator.mobilePhone || mediator.phone}` : null,
                mailHref: mediator.email ? `mailto:${mediator.email}` : null,
                hasCall: Boolean(mediator.mobilePhone || mediator.phone),
                hasMail: Boolean(mediator.email)
            })),
            statusClass: this.statusClass(detail.status)
        };
    }

    statusClass(status) {
        const base = 'chip chip--status';
        if (!status) {
            return base;
        }
        if (/ready/i.test(status)) {
            return `${base} chip--ready`;
        }
        if (/sold/i.test(status)) {
            return `${base} chip--sold`;
        }
        return `${base} chip--building`;
    }

    sizeText(bytes) {
        if (!bytes) {
            return '';
        }
        if (bytes < 1024 * 1024) {
            return `${Math.max(1, Math.round(bytes / 1024))} KB`;
        }
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }

    handleImageError(event) {
        // A distribution link can expire or be revoked after the card rendered.
        // Drop the broken frame rather than leaving a torn-image icon.
        event.target.closest('.frame')?.classList.add('frame--failed');
    }

    // ------------------------------------------------------- message plumbing

    pushMessage(message) {
        this.messages = [...this.messages, { id: nextId(), ...message }];
        this.scrollToLatest();
    }

    pushAgentText(text) {
        this.pushMessage({ kind: 'text', isText: true, fromAgent: true, text });
    }

    pushVisitorText(text) {
        this.pushMessage({ kind: 'text', isText: true, fromAgent: false, text });
    }

    pushChips(labels) {
        this.pushMessage({
            kind: 'chips',
            isChips: true,
            chips: labels.map((label) => ({ key: label, label }))
        });
    }

    scrollToLatest() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.requestAnimationFrame(() => {
            const stream = this.template.querySelector('.stream');
            if (stream) {
                stream.scrollTop = stream.scrollHeight;
            }
        });
    }

    focusInput() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.requestAnimationFrame(() => {
            this.template.querySelector('.composer__input')?.focus();
        });
    }

    readError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Something went wrong at our end. Please try again in a moment.'
        );
    }

    // ------------------------------------------------------------- template

    get panelClass() {
        return `panel${this.isMinimised ? ' panel--minimised' : ''}`;
    }

    get minimiseLabel() {
        return this.isMinimised ? 'Expand chat' : 'Minimise chat';
    }

    get showPanel() {
        return this.isOpen;
    }

    get showLauncher() {
        return !this.isOpen;
    }

    get isSendDisabled() {
        return this.isThinking || !(this.draft || '').trim();
    }
}
