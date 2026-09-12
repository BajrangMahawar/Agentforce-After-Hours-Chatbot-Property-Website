/**
 * Backs the propertyConsultantChat LWC on the Real Estate Property Portal site.
 *
 * The chat window renders picture cards, so everything here is shaped for a
 * card rather than for the agent's LLM: one row per property with its hero
 * image already resolved, and a detail payload carrying the whole gallery.
 *
 * Images come from files linked to the Property via ContentDocumentLink, gated
 * the same way the agent gates them - Shareable_With_Visitors__c - and served
 * through ContentDistribution because a site visitor has no Salesforce login.
 *
 * `without sharing` for the same reason PropertyPortalController is: the guest
 * user owns none of these records and the portfolio is public by design.
 */
public without sharing class PropertyChatController {
    private static final Integer MAX_RESULTS = 24;
    private static final Integer MAX_GALLERY = 12;
    private static final String LOG = 'PROPERTY_CHAT';

    /** File extensions a browser can put inside an img tag. Lowercase. */
    private static final Set<String> IMAGE_EXTENSIONS =
        new Set<String>{ 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg' };

    /** The Document Type that means "this file is photography of the project". */
    private static final String TYPE_GALLERY = 'Image / Gallery';

    // ---------------------------------------------------------------- search

    /**
     * The card list the chat shows for "3 BHK in Gurugram". Every filter is
     * optional; blank, 'All' or 'Any' means unfiltered on that axis.
     */
    @AuraEnabled(cacheable=true)
    public static List<PropertyCard> searchProperties(
        String city, String configuration, Decimal priceMin, Decimal priceMax, String nameLike
    ) {
        AgentforceLogger.log(LOG, 'SEARCH',
            'city=' + AgentforceLogger.show(city) +
            ' configuration=' + AgentforceLogger.show(configuration) +
            ' priceMin=' + AgentforceLogger.show(priceMin) +
            ' priceMax=' + AgentforceLogger.show(priceMax) +
            ' nameLike=' + AgentforceLogger.show(nameLike));

        List<String> filters = new List<String>{ 'Status__c != \'Sold Out\'' };
        Map<String, Object> binds = new Map<String, Object>();

        if (isReal(city)) {
            binds.put('city', '%' + city.trim() + '%');
            filters.add('City__c LIKE :city');
        }
        if (isReal(configuration)) {
            binds.put('config', configuration.trim());
            filters.add('Configurations__c INCLUDES (:config)');
        }
        if (priceMin != null && priceMin > 0) {
            binds.put('minBudget', priceMin);
            filters.add('(Price_Max__c >= :minBudget OR (Price_Max__c = NULL AND Price_Min__c >= :minBudget))');
        }
        if (priceMax != null && priceMax > 0) {
            binds.put('maxBudget', priceMax);
            filters.add('(Price_Min__c <= :maxBudget OR (Price_Min__c = NULL AND Price_Max__c <= :maxBudget))');
        }
        if (isReal(nameLike)) {
            binds.put('nameLike', '%' + AgentforceController.escapeLike(nameLike.trim()) + '%');
            filters.add('Name LIKE :nameLike');
        }

        String soql =
            'SELECT Id, Name, City__c, Address__c, Configurations__c, Property_Type__c, Status__c, ' +
            'Price_Min__c, Price_Max__c, Price_Range__c, Possession_Date__c, RERA_Number__c, Description__c ' +
            'FROM Property__c WHERE ' + String.join(filters, ' AND ') +
            ' ORDER BY Price_Min__c DESC NULLS LAST, Name ASC LIMIT ' + MAX_RESULTS;

        List<Property__c> rows =
            (List<Property__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);

        // One image query for the whole page rather than one per card.
        Map<Id, List<MediaItem>> gallery = imagesFor(idsOf(rows));

        List<PropertyCard> cards = new List<PropertyCard>();
        for (Property__c p : rows) {
            cards.add(new PropertyCard(p, gallery.get(p.Id)));
        }
        AgentforceLogger.log(LOG, 'SEARCH', 'returned ' + cards.size() + ' card(s)');
        return cards;
    }

    // ---------------------------------------------------------------- detail

    /**
     * Everything the detail card shows: the property, its whole image gallery,
     * unit specifications, amenities, mediators and shareable documents.
     * Accepts an Id or a name, so the chat can act on either. Returns null
     * when nothing answers to that key.
     */
    @AuraEnabled(cacheable=true)
    public static PropertyDetail getPropertyDetail(String propertyIdOrName) {
        AgentforceLogger.log(LOG, 'DETAIL', 'key=' + AgentforceLogger.show(propertyIdOrName));

        Property__c p = resolveProperty(propertyIdOrName);
        if (p == null) {
            AgentforceLogger.log(LOG, 'DETAIL', 'STOP: nothing matched');
            return null;
        }

        PropertyDetail detail = new PropertyDetail(p, imagesFor(new Set<Id>{ p.Id }).get(p.Id));
        populateSpecifications(detail, p.Id);
        populateMediators(detail, p.Id);
        populateDocuments(detail, p.Id);

        AgentforceLogger.log(LOG, 'DETAIL', 'resolved ' + p.Id + ' "' + p.Name +
            '" images=' + detail.images.size() + ' specs=' + detail.specifications.size() +
            ' mediators=' + detail.mediators.size() + ' documents=' + detail.documents.size());
        return detail;
    }

    private static Property__c resolveProperty(String key) {
        String trimmed = AgentforceController.blankToNull(key);
        if (trimmed == null) {
            return null;
        }

        try {
            Id parsed = Id.valueOf(trimmed);
            if (parsed.getSObjectType() == Property__c.SObjectType) {
                List<Property__c> byId = queryProperties('Id = :key', (Object) parsed);
                return byId.isEmpty() ? null : byId[0];
            }
        } catch (Exception ignored) {
            // Not an Id at all - fall through and treat it as a name.
        }

        List<Property__c> exact = queryProperties('Name = :key', (Object) trimmed);
        if (!exact.isEmpty()) {
            return exact[0];
        }
        List<Property__c> partial = queryProperties(
            'Name LIKE :key', (Object) ('%' + AgentforceController.escapeLike(trimmed) + '%')
        );
        return partial.isEmpty() ? null : partial[0];
    }

    private static List<Property__c> queryProperties(String whereClause, Object key) {
        String soql =
            'SELECT Id, Name, City__c, Address__c, Configurations__c, Property_Type__c, Status__c, ' +
            'Price_Min__c, Price_Max__c, Price_Range__c, Possession_Date__c, RERA_Number__c, Description__c, ' +
            'Location__Latitude__s, Location__Longitude__s ' +
            'FROM Property__c WHERE ' + whereClause + ' ORDER BY Name ASC LIMIT 1';
        return (List<Property__c>) Database.queryWithBinds(
            soql, new Map<String, Object>{ 'key' => key }, AccessLevel.SYSTEM_MODE
        );
    }

    private static void populateSpecifications(PropertyDetail detail, Id propertyId) {
        Set<String> allAmenities = new Set<String>();
        for (Property_Specification__c spec : [
            SELECT Name, Unit_Type__c, Carpet_Area__c, Built_up_Area__c, Floor_Plan_URL__c, Amenities__c
            FROM Property_Specification__c
            WHERE Property__c = :propertyId
            ORDER BY Carpet_Area__c ASC NULLS LAST
            LIMIT 50
        ]) {
            detail.specifications.add(new SpecCard(spec));
            if (String.isNotBlank(spec.Amenities__c)) {
                allAmenities.addAll(spec.Amenities__c.split(';'));
            }
        }
        List<String> merged = new List<String>();
        for (String amenity : allAmenities) {
            if (String.isNotBlank(amenity)) {
                merged.add(amenity.trim());
            }
        }
        merged.sort();
        detail.amenities = merged;
    }

    private static void populateMediators(PropertyDetail detail, Id propertyId) {
        for (Contact mediator : AgentforceDataService.mediatorsForProperty(propertyId).values()) {
            detail.mediators.add(new MediatorCard(mediator));
        }
    }

    private static void populateDocuments(PropertyDetail detail, Id propertyId) {
        for (MediaItem item : shareableFiles(new Set<Id>{ propertyId }).get(propertyId)) {
            // Project photography already rides in `images`; everything else is
            // collateral - a brochure, a price list, a floor plan - which the
            // card renders as a download row even when it happens to be a jpg.
            if (!item.isGallery) {
                detail.documents.add(item);
            }
        }
    }

    // ---------------------------------------------------------------- images

    /** Gallery images per property, capped, in Document Type then Title order. */
    private static Map<Id, List<MediaItem>> imagesFor(Set<Id> propertyIds) {
        Map<Id, List<MediaItem>> images = new Map<Id, List<MediaItem>>();
        Map<Id, List<MediaItem>> files = shareableFiles(propertyIds);
        for (Id propertyId : propertyIds) {
            List<MediaItem> picked = new List<MediaItem>();
            for (MediaItem item : files.get(propertyId)) {
                if (item.isGallery && picked.size() < MAX_GALLERY) {
                    picked.add(item);
                }
            }
            images.put(propertyId, picked);
        }
        return images;
    }

    /**
     * Cached per transaction: the detail path asks for the same property's
     * files twice - once for the gallery, once for the documents - and the
     * ContentDistribution insert inside must not run a second time.
     */
    private static Map<Id, List<MediaItem>> fileCache;

    private static Map<Id, List<MediaItem>> shareableFiles(Set<Id> propertyIds) {
        if (fileCache == null) {
            fileCache = new Map<Id, List<MediaItem>>();
        }
        Set<Id> missing = new Set<Id>();
        for (Id propertyId : propertyIds) {
            if (!fileCache.containsKey(propertyId)) {
                missing.add(propertyId);
            }
        }
        if (!missing.isEmpty()) {
            fileCache.putAll(loadShareableFiles(missing));
        }

        Map<Id, List<MediaItem>> slice = new Map<Id, List<MediaItem>>();
        for (Id propertyId : propertyIds) {
            slice.put(propertyId, fileCache.get(propertyId));
        }
        return slice;
    }

    private static Map<Id, List<MediaItem>> loadShareableFiles(Set<Id> propertyIds) {
        Map<Id, List<MediaItem>> byProperty = new Map<Id, List<MediaItem>>();
        for (Id propertyId : propertyIds) {
            byProperty.put(propertyId, new List<MediaItem>());
        }
        if (propertyIds.isEmpty()) {
            return byProperty;
        }

        // ContentDocumentLink cannot be filtered by fields on the version, so
        // the shareable gate is applied on ContentVersion below.
        Map<Id, Set<Id>> documentToProperties = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :propertyIds
            LIMIT 2000
        ]) {
            if (!documentToProperties.containsKey(link.ContentDocumentId)) {
                documentToProperties.put(link.ContentDocumentId, new Set<Id>());
            }
            documentToProperties.get(link.ContentDocumentId).add(link.LinkedEntityId);
        }
        AgentforceLogger.log(LOG, 'FILES', 'properties=' + propertyIds.size() +
            ' linked documents=' + documentToProperties.size());
        if (documentToProperties.isEmpty()) {
            return byProperty;
        }

        List<ContentVersion> shareable = [
            SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize, Document_Type__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentToProperties.keySet()
              AND IsLatest = true
              AND Shareable_With_Visitors__c = true
            ORDER BY Document_Type__c ASC NULLS LAST, Title ASC
            LIMIT 500
        ];
        AgentforceLogger.log(LOG, 'FILES', 'shareable versions=' + shareable.size());
        if (shareable.isEmpty()) {
            return byProperty;
        }

        // Two URLs per file, because they are not interchangeable: an image has
        // to be the bytes for <img src> to draw it, while a brochure should open
        // the viewer page a visitor can read and download from.
        Map<Id, String> pageUrls = AgentforcePropertyDetailController.publicLinks(shareable);
        Map<Id, String> byteUrls = AgentforcePropertyDetailController.imageLinks(shareable);
        Integer skipped = 0;
        for (ContentVersion cv : shareable) {
            // Only project photography is drawn inline and needs the raw bytes.
            // A brochure uploaded as a jpg is still a document, and should open
            // its viewer page rather than dump a file at the visitor.
            MediaItem probe = new MediaItem(cv, null);
            String url = probe.isGallery ? byteUrls.get(cv.Id) : pageUrls.get(cv.Id);
            if (String.isBlank(url)) {
                // No public link means no way for a logged-out visitor to load
                // it, so it must not reach a card as a broken image.
                skipped++;
                continue;
            }
            for (Id propertyId : documentToProperties.get(cv.ContentDocumentId)) {
                if (byProperty.containsKey(propertyId)) {
                    byProperty.get(propertyId).add(new MediaItem(cv, url));
                }
            }
        }
        AgentforceLogger.log(LOG, 'FILES', 'usable=' + (shareable.size() - skipped) +
            ' skipped for a missing public link=' + skipped);
        return byProperty;
    }

    private static Set<Id> idsOf(List<Property__c> rows) {
        Set<Id> ids = new Set<Id>();
        for (Property__c p : rows) {
            ids.add(p.Id);
        }
        return ids;
    }

    private static Boolean isReal(String value) {
        return String.isNotBlank(value) && value.trim() != 'All' && value.trim() != 'Any';
    }

    // ----------------------------------------------------------- wire shapes

    /** One file the chat can render - an image inline, anything else as a row. */
    public class MediaItem {
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String documentType;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public Integer sizeBytes;
        @AuraEnabled public String url;
        @AuraEnabled public Boolean isImage;
        /** True only for project photography - see the constructor. */
        @AuraEnabled public Boolean isGallery;

        public MediaItem(ContentVersion cv, String url) {
            this.contentVersionId = cv.Id;
            this.title = cv.Title;
            this.documentType = cv.Document_Type__c;
            this.fileExtension = cv.FileExtension;
            this.sizeBytes = cv.ContentSize;
            this.url = url;
            this.isImage = String.isNotBlank(cv.FileExtension) &&
                IMAGE_EXTENSIONS.contains(cv.FileExtension.toLowerCase());
            // A brochure is often uploaded as a jpg of its cover page. The
            // extension alone would make it the hero photograph, which is not
            // what a visitor wants to see first, so the Document Type decides:
            // only "Image / Gallery" is photography of the project itself.
            this.isGallery = this.isImage && TYPE_GALLERY.equals(cv.Document_Type__c);
        }
    }

    public virtual class PropertyCard {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String city;
        @AuraEnabled public String address;
        @AuraEnabled public String configurations;
        @AuraEnabled public String propertyType;
        @AuraEnabled public String status;
        @AuraEnabled public String priceRange;
        @AuraEnabled public Decimal priceMin;
        @AuraEnabled public Decimal priceMax;
        @AuraEnabled public String possession;
        @AuraEnabled public String reraNumber;
        @AuraEnabled public String description;
        @AuraEnabled public String initials;
        /** Null when the property has no shareable image; the card draws a monogram instead. */
        @AuraEnabled public String heroImageUrl;
        @AuraEnabled public Integer imageCount;

        public PropertyCard(Property__c p, List<MediaItem> images) {
            this.recordId = p.Id;
            this.name = p.Name;
            this.city = p.City__c;
            this.address = p.Address__c;
            this.configurations = p.Configurations__c == null ? '' : p.Configurations__c.replace(';', ' · ');
            this.propertyType = p.Property_Type__c;
            this.status = p.Status__c;
            this.priceRange = String.isBlank(p.Price_Range__c) ? 'Price on request' : p.Price_Range__c;
            this.priceMin = p.Price_Min__c;
            this.priceMax = p.Price_Max__c;
            this.possession = possessionText(p.Possession_Date__c);
            this.reraNumber = p.RERA_Number__c;
            this.description = p.Description__c;
            this.initials = initialsOf(p.Name);
            List<MediaItem> safe = images == null ? new List<MediaItem>() : images;
            this.heroImageUrl = safe.isEmpty() ? null : safe[0].url;
            this.imageCount = safe.size();
        }

        protected String possessionText(Date possessionDate) {
            if (possessionDate == null) {
                return 'Possession on request';
            }
            if (possessionDate <= Date.today()) {
                return 'Ready to move';
            }
            List<String> months = new List<String>{
                'January', 'February', 'March', 'April', 'May', 'June',
                'July', 'August', 'September', 'October', 'November', 'December'
            };
            return months[possessionDate.month() - 1] + ' ' + possessionDate.year();
        }

        protected String initialsOf(String value) {
            if (String.isBlank(value)) {
                return '--';
            }
            List<String> words = value.trim().split('\\s+');
            String first = words[0].substring(0, 1);
            String second = words.size() > 1 ? words[1].substring(0, 1) : '';
            return (first + second).toUpperCase();
        }
    }

    public class PropertyDetail extends PropertyCard {
        @AuraEnabled public List<MediaItem> images = new List<MediaItem>();
        @AuraEnabled public List<MediaItem> documents = new List<MediaItem>();
        @AuraEnabled public List<SpecCard> specifications = new List<SpecCard>();
        @AuraEnabled public List<MediatorCard> mediators = new List<MediatorCard>();
        @AuraEnabled public List<String> amenities = new List<String>();
        @AuraEnabled public Double latitude;
        @AuraEnabled public Double longitude;

        public PropertyDetail(Property__c p, List<MediaItem> images) {
            super(p, images);
            this.images = images == null ? new List<MediaItem>() : images;
            this.latitude = p.Location__Latitude__s;
            this.longitude = p.Location__Longitude__s;
        }
    }

    public class SpecCard {
        @AuraEnabled public String name;
        @AuraEnabled public String unitType;
        @AuraEnabled public Decimal carpetArea;
        @AuraEnabled public Decimal builtUpArea;
        @AuraEnabled public String floorPlanUrl;
        @AuraEnabled public List<String> amenities = new List<String>();

        public SpecCard(Property_Specification__c spec) {
            this.name = spec.Name;
            this.unitType = spec.Unit_Type__c;
            this.carpetArea = spec.Carpet_Area__c;
            this.builtUpArea = spec.Built_up_Area__c;
            this.floorPlanUrl = spec.Floor_Plan_URL__c;
            if (String.isNotBlank(spec.Amenities__c)) {
                for (String amenity : spec.Amenities__c.split(';')) {
                    if (String.isNotBlank(amenity)) {
                        this.amenities.add(amenity.trim());
                    }
                }
            }
        }
    }

    public class MediatorCard {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String phone;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String email;
        @AuraEnabled public String initials;

        public MediatorCard(Contact c) {
            this.recordId = c.Id;
            this.name = c.Name;
            this.title = c.Title;
            this.phone = c.Phone;
            this.mobilePhone = c.MobilePhone;
            this.email = c.Email;
            this.initials = String.isBlank(c.Name) ? '--' : c.Name.substring(0, 1).toUpperCase();
        }
    }

    // ------------------------------------------------- Agentforce card feeds

    /**
     * Cards for a list of Ids the agent has already chosen.
     *
     * The Agentforce output component receives the agent action's own result,
     * which carries no imagery - the action was written for the LLM to read
     * out loud, not for a card to render. So the component hands the Ids back
     * here and gets the same PropertyCard the chat window builds, hero image
     * resolved and all.
     *
     * Order follows `propertyIds`, because that is the order the agent decided
     * to present them in. Ids that no longer resolve are dropped silently -
     * a stale Id must not blank the whole rail.
     */
    @AuraEnabled(cacheable=true)
    public static List<PropertyCard> getCardsByIds(List<String> propertyIds) {
        AgentforceLogger.log(LOG, 'CARDS',
            'requested ' + (propertyIds == null ? 0 : propertyIds.size()) + ' id(s)');

        Set<Id> wanted = new Set<Id>();
        List<Id> ordered = new List<Id>();
        if (propertyIds != null) {
            for (String raw : propertyIds) {
                Id parsed = toPropertyId(raw);
                // A duplicate Id would render the same card twice.
                if (parsed != null && !wanted.contains(parsed)) {
                    wanted.add(parsed);
                    ordered.add(parsed);
                    if (ordered.size() >= MAX_RESULTS) {
                        break;
                    }
                }
            }
        }
        if (ordered.isEmpty()) {
            AgentforceLogger.log(LOG, 'CARDS', 'STOP: no usable id in the request');
            return new List<PropertyCard>();
        }

        Map<Id, Property__c> found = new Map<Id, Property__c>([
            SELECT Id, Name, City__c, Address__c, Configurations__c, Property_Type__c, Status__c,
                   Price_Min__c, Price_Max__c, Price_Range__c, Possession_Date__c,
                   RERA_Number__c, Description__c
            FROM Property__c
            WHERE Id IN :wanted
        ]);

        Map<Id, List<MediaItem>> gallery = imagesFor(found.keySet());

        List<PropertyCard> cards = new List<PropertyCard>();
        for (Id propertyId : ordered) {
            Property__c p = found.get(propertyId);
            if (p != null) {
                cards.add(new PropertyCard(p, gallery.get(propertyId)));
            }
        }
        AgentforceLogger.log(LOG, 'CARDS', 'returned ' + cards.size() +
            ' card(s) of ' + ordered.size() + ' requested');
        return cards;
    }

    /** An Id only if it really is one, and really is a Property. Else null. */
    private static Id toPropertyId(String raw) {
        String trimmed = AgentforceController.blankToNull(raw);
        if (trimmed == null) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(trimmed);
            return parsed.getSObjectType() == Property__c.SObjectType ? parsed : null;
        } catch (Exception ignored) {
            return null;
        }
    }
}
