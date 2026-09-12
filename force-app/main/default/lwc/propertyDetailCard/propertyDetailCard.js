import { LightningElement, api } from 'lwc';
import getPropertyDetail from '@salesforce/apex/PropertyChatController.getPropertyDetail';

/**
 * Renders one property, opened out, inside the Embedded Messaging window:
 * hero photograph, the rest of the gallery, unit plans, amenities, the
 * shareable documents and the advisor to call.
 *
 * Like propertyCardList, this takes the agent action's own output and reads a
 * key out of it - an Id if the action returned one, otherwise the project
 * name, since Apex resolves either. Everything shown is fetched here rather
 * than trusted from the payload, so the card can never show a figure the
 * record does not carry.
 */

const KEY_FIELDS = ['propertyId', 'PropertyId', 'recordId', 'id', 'Id'];
const NAME_FIELDS = ['propertyName', 'PropertyName', 'name', 'Name'];

export default class PropertyDetailCard extends LightningElement {
    _value;
    detail;
    isLoading = false;
    loadFailed = false;

    @api
    get value() {
        return this._value;
    }
    set value(incoming) {
        this._value = incoming;
        this.load(incoming);
    }

    async load(payload) {
        const key = this.readKey(payload);
        if (!key) {
            this.detail = undefined;
            return;
        }
        this.isLoading = true;
        this.loadFailed = false;
        try {
            const found = await getPropertyDetail({ propertyIdOrName: key });
            this.detail = found ? this.decorate(found) : undefined;
        } catch (error) {
            this.loadFailed = true;
            this.detail = undefined;
            // eslint-disable-next-line no-console
            console.error('propertyDetailCard: could not load the property', error);
        } finally {
            this.isLoading = false;
        }
    }

    /** An Id if the payload carries one, else a project name. */
    readKey(payload) {
        let name = null;
        const visit = (node, depth) => {
            if (!node || depth > 6 || typeof node !== 'object') {
                return null;
            }
            if (Array.isArray(node)) {
                for (const item of node) {
                    const found = visit(item, depth + 1);
                    if (found) {
                        return found;
                    }
                }
                return null;
            }
            for (const field of KEY_FIELDS) {
                const candidate = node[field];
                if (typeof candidate === 'string' && this.looksLikeId(candidate)) {
                    return candidate;
                }
            }
            // Keep the first name seen as the fallback, but go on looking for
            // an Id, which resolves without ambiguity.
            if (!name) {
                for (const field of NAME_FIELDS) {
                    const candidate = node[field];
                    if (typeof candidate === 'string' && candidate.trim().length >= 3) {
                        name = candidate.trim();
                        break;
                    }
                }
            }
            for (const child of Object.values(node)) {
                const found = visit(child, depth + 1);
                if (found) {
                    return found;
                }
            }
            return null;
        };

        if (typeof payload === 'string') {
            const text = payload.trim();
            return text.length >= 3 ? text : null;
        }
        return visit(payload, 0) || name;
    }

    looksLikeId(value) {
        return /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(value);
    }

    // ------------------------------------------------------------- shaping

    decorate(detail) {
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
            // Without a photograph the frame is dropped entirely, so the status
            // badge that normally sits on it moves into the body instead.
            hasNoHero: images.length === 0,
            thumbnails: images.slice(1),
            hasThumbnails: images.length > 1,
            hasDocuments: Boolean(detail.documents && detail.documents.length),
            hasAmenities: Boolean(detail.amenities && detail.amenities.length),
            hasSpecifications: Boolean(detail.specifications && detail.specifications.length),
            hasMediators: Boolean(detail.mediators && detail.mediators.length),
            statusClass: this.statusClass(detail.status),
            statusClassInline: `${this.statusClass(detail.status)} chip--inline`,
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
                hasCall: Boolean(mediator.mobilePhone || mediator.phone),
                hasMail: Boolean(mediator.email),
                callHref: mediator.mobilePhone || mediator.phone
                    ? `tel:${mediator.mobilePhone || mediator.phone}`
                    : null,
                mailHref: mediator.email ? `mailto:${mediator.email}` : null
            }))
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

    // --------------------------------------------------------- interaction

    /** Hands the conversation back to the agent, which owns booking. */
    handleBookVisit() {
        if (!this.detail) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('sendmessage', {
                detail: { message: `I want to book a site visit for ${this.detail.name}` },
                bubbles: true,
                composed: true
            })
        );
    }

    handleImageError(event) {
        event.target.closest('.frame')?.classList.add('frame--failed');
    }

    get hasDetail() {
        return Boolean(this.detail);
    }
}
