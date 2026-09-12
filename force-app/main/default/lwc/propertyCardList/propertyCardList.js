import { LightningElement, api } from 'lwc';
import getCardsByIds from '@salesforce/apex/PropertyChatController.getCardsByIds';

/**
 * Renders the agent's "Get Properties" answer as a rail of picture cards
 * inside the Embedded Messaging window.
 *
 * Agentforce hands this component the action's own output. That output was
 * shaped for the LLM to read out loud, so it carries no imagery - only Ids
 * and text. The Ids go back to Apex here and come back as the same card the
 * portal uses, hero image resolved through a public distribution link so a
 * logged-out visitor can load it.
 *
 * Tapping a card sends a message back into the conversation as if the visitor
 * had typed it, which keeps the agent in charge of what happens next.
 */

/**
 * Agentforce has changed the shape of the value it passes more than once, and
 * a deployment can be on either. Rather than bind to one, look for the first
 * list of property-shaped objects anywhere in the payload.
 */
const ID_KEYS = ['propertyId', 'PropertyId', 'recordId', 'id', 'Id'];

export default class PropertyCardList extends LightningElement {
    _value;
    cards = [];
    isLoading = false;
    loadFailed = false;

    /** The agent action's result. Agentforce sets this. */
    @api
    get value() {
        return this._value;
    }
    set value(incoming) {
        this._value = incoming;
        this.load(incoming);
    }

    async load(payload) {
        const ids = this.readPropertyIds(payload);
        if (!ids.length) {
            this.cards = [];
            return;
        }
        this.isLoading = true;
        this.loadFailed = false;
        try {
            const rows = await getCardsByIds({ propertyIds: ids });
            this.cards = (rows || []).map((card) => this.decorate(card));
        } catch (error) {
            // The window already shows the agent's own sentence, so a failure
            // here costs the pictures, not the answer. Say so quietly.
            this.loadFailed = true;
            this.cards = [];
            // eslint-disable-next-line no-console
            console.error('propertyCardList: could not load cards', error);
        } finally {
            this.isLoading = false;
        }
    }

    /** Walks the payload and collects the first property Ids it finds. */
    readPropertyIds(payload) {
        const found = [];
        const seen = new Set();
        const visit = (node, depth) => {
            if (!node || depth > 6 || found.length >= 24) {
                return;
            }
            if (Array.isArray(node)) {
                node.forEach((item) => visit(item, depth + 1));
                return;
            }
            if (typeof node === 'string') {
                if (this.looksLikeId(node) && !seen.has(node)) {
                    seen.add(node);
                    found.push(node);
                }
                return;
            }
            if (typeof node !== 'object') {
                return;
            }
            for (const key of ID_KEYS) {
                const candidate = node[key];
                if (typeof candidate === 'string' && this.looksLikeId(candidate) && !seen.has(candidate)) {
                    seen.add(candidate);
                    found.push(candidate);
                    return; // One Id per object - the rest of it is that record's fields.
                }
            }
            Object.values(node).forEach((child) => visit(child, depth + 1));
        };
        visit(payload, 0);
        return found;
    }

    /** A Salesforce Id: 15 or 18 alphanumerics. Apex rejects anything wrong. */
    looksLikeId(value) {
        return /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(value);
    }

    decorate(card) {
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

    // ------------------------------------------------------------ interaction

    handleCardClick(event) {
        this.askAbout(event.currentTarget.dataset.name);
    }

    handleCardKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.askAbout(event.currentTarget.dataset.name);
        }
    }

    /**
     * Puts a sentence into the conversation on the visitor's behalf. The agent
     * then routes it like any other message, so tapping a card and typing the
     * same words lead to exactly the same place.
     */
    askAbout(name) {
        if (!name) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('sendmessage', {
                detail: { message: `Tell me more about ${name}` },
                bubbles: true,
                composed: true
            })
        );
    }

    handleImageError(event) {
        // A distribution link can be revoked after the card rendered; drop the
        // frame rather than leave a torn-image icon in the window.
        event.target.closest('.frame')?.classList.add('frame--failed');
    }

    get hasCards() {
        return this.cards.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.hasCards;
    }
}
