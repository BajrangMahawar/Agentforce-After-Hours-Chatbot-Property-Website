public with sharing class AgentforcePropertyDetailController {
    private static final Integer MAX_CHILD_ROWS = 50;
    private static final String LOG = 'PROPERTY_DETAIL';

    @InvocableMethod(
        label='Get Property Detail'
        description='Returns the complete profile of one property by name - pricing, status, possession, specifications, amenities, mediators and visitor-shareable documents.'
        category='Property'
    )
    public static List<PropertyDetailResult> getPropertyDetail(List<PropertyDetailRequest> requests) {
        List<PropertyDetailResult> results = new List<PropertyDetailResult>();

        AgentforceLogger.logContext(LOG, requests == null ? 0 : requests.size());
        if (requests == null) {
            AgentforceLogger.log(LOG, 'ENTRY', 'ABORT: the request list itself was null');
            return results;
        }

        Integer index = 0;
        for (PropertyDetailRequest req : requests) {
            index++;
            PropertyDetailResult res = new PropertyDetailResult();
            res.specifications = new List<SpecificationInfo>();
            res.mediators = new List<MediatorContactInfo>();
            res.documents = new List<DocumentInfo>();
            try {
                if (req == null) {
                    AgentforceLogger.log(LOG, 'REQUEST #' + index, 'the request object was null');
                } else {
                    AgentforceLogger.log(LOG, 'REQUEST #' + index,
                        'propertyId=' + AgentforceLogger.show(req.propertyId) +
                        ' propertyName=' + AgentforceLogger.show(req.propertyName));
                }
                res.isSuccess = true;
                res.message = load(req, res);
                AgentforceLogger.log(LOG, 'RESULT #' + index,
                    'isFound=' + res.isFound + ' name=' + AgentforceLogger.show(res.name) +
                    ' specs=' + res.specificationCount + ' mediators=' + res.mediatorCount +
                    ' documents=' + res.documentCount);
                AgentforceLogger.log(LOG, 'RESULT #' + index, 'message=' + AgentforceLogger.show(res.message));
            } catch (Exception e) {
                res.isFound = false;
                res.isSuccess = false;
                res.message = 'Could not load the property detail: ' + e.getMessage();
                AgentforceLogger.logException(LOG, 'EXCEPTION #' + index, e);
            }
            results.add(res);
        }
        AgentforceLogger.log(LOG, 'EXIT', 'returning ' + results.size() + ' result(s)');
        return results;
    }

    private static String load(PropertyDetailRequest req, PropertyDetailResult res) {
        res.isFound = false;

        List<Property__c> matches = findProperties(req);
        if (matches.isEmpty()) {
            AgentforceLogger.log(LOG, 'LOAD', 'STOP: no property matched');
            return 'No property found by that name.';
        }

        Property__c p = matches[0];
        res.isFound = true;
        AgentforceLogger.log(LOG, 'LOAD', 'using ' + p.Id + ' "' + p.Name +
            '" out of ' + matches.size() + ' match(es)');
        populateProperty(res, p);
        populateSpecifications(res, p.Id);
        populateMediators(res, p.Id);
        populateDocuments(res, p.Id);

        if (matches.size() == 1) {
            return 'Details for ' + p.Name + '.';
        }
        List<String> others = new List<String>();
        for (Integer i = 1; i < matches.size(); i++) {
            others.add(matches[i].Name);
        }
        return matches.size() + ' properties matched that name. Showing ' + p.Name +
            '. Others: ' + String.join(others, ', ') + '.';
    }

    private static List<Property__c> findProperties(PropertyDetailRequest req) {
        String propertyId = AgentforceController.blankToNull(req.propertyId);
        if (propertyId != null) {
            try {
                Id parsed = Id.valueOf(propertyId);
                if (parsed.getSObjectType() == Property__c.SObjectType) {
                    List<Property__c> byId = queryProperties('Id = :key', (Object) parsed);
                    AgentforceLogger.log(LOG, 'FIND', 'by Id ' + parsed +
                        ' returned ' + byId.size() + ' row(s)');
                    return byId;
                }
                AgentforceLogger.log(LOG, 'FIND', propertyId + ' is an Id but not a Property Id');
            } catch (Exception ignored) {
                AgentforceLogger.log(LOG, 'FIND', '"' + propertyId +
                    '" is not a usable Id, will try it as a name');
            }
        }

        String name = AgentforceController.blankToNull(req.propertyName);
        if (name == null) {
            name = propertyId;
        }
        if (name == null) {
            AgentforceLogger.log(LOG, 'FIND', 'no property id or name was supplied');
            return new List<Property__c>();
        }

        List<Property__c> exact = queryProperties('Name = :key', (Object) name);
        if (!exact.isEmpty()) {
            AgentforceLogger.log(LOG, 'FIND', 'exact name match on "' + name + '"');
            return exact;
        }
        List<Property__c> partial =
            queryProperties('Name LIKE :key', (Object) ('%' + AgentforceController.escapeLike(name) + '%'));
        AgentforceLogger.log(LOG, 'FIND', 'LIKE search on "' + name +
            '" returned ' + partial.size() + ' row(s)');
        return partial;
    }

    private static List<Property__c> queryProperties(String whereClause, Object key) {
        String soql =
            'SELECT Id, Name, City__c, Address__c, Configurations__c, Property_Type__c, Status__c, ' +
            'Price_Min__c, Price_Max__c, Price_Range__c, Possession_Date__c, RERA_Number__c, Description__c, ' +
            'Location__Latitude__s, Location__Longitude__s, CreatedDate, LastModifiedDate ' +
            'FROM Property__c WHERE ' + whereClause +
            ' ORDER BY Name ASC LIMIT ' + MAX_CHILD_ROWS;
        return (List<Property__c>) Database.queryWithBinds(
            soql, new Map<String, Object>{ 'key' => key }, AccessLevel.USER_MODE
        );
    }

    private static void populateProperty(PropertyDetailResult res, Property__c p) {
        res.propertyId = p.Id;
        res.name = p.Name;
        res.city = p.City__c;
        res.address = p.Address__c;
        res.configurations = p.Configurations__c;
        res.propertyType = p.Property_Type__c;
        res.status = p.Status__c;
        res.isAvailable = p.Status__c != 'Sold Out';
        res.priceMin = p.Price_Min__c;
        res.priceMax = p.Price_Max__c;
        res.priceRange = p.Price_Range__c;
        res.possessionDate = p.Possession_Date__c;
        res.reraNumber = p.RERA_Number__c;
        res.description = p.Description__c;
        res.latitude = p.Location__Latitude__s;
        res.longitude = p.Location__Longitude__s;
    }

    private static void populateSpecifications(PropertyDetailResult res, Id propertyId) {
        Set<String> allAmenities = new Set<String>();
        for (Property_Specification__c spec : [
            SELECT Name, Unit_Type__c, Carpet_Area__c, Built_up_Area__c, Floor_Plan_URL__c, Amenities__c
            FROM Property_Specification__c
            WHERE Property__c = :propertyId
            WITH USER_MODE
            ORDER BY Carpet_Area__c ASC NULLS LAST
            LIMIT :MAX_CHILD_ROWS
        ]) {
            res.specifications.add(new SpecificationInfo(spec));
            if (String.isNotBlank(spec.Amenities__c)) {
                allAmenities.addAll(spec.Amenities__c.split(';'));
            }
        }
        res.specificationCount = res.specifications.size();
        AgentforceLogger.log(LOG, 'SPECS', 'property=' + propertyId +
            ' specifications=' + res.specificationCount +
            ' distinctAmenities=' + allAmenities.size());
        List<String> merged = new List<String>(allAmenities);
        merged.sort();
        res.amenities = String.join(merged, '; ');
    }

    private static void populateMediators(PropertyDetailResult res, Id propertyId) {
        for (Contact mediator : AgentforceDataService.mediatorsForProperty(propertyId).values()) {
            res.mediators.add(new MediatorContactInfo(mediator));
        }
        res.mediatorCount = res.mediators.size();
        AgentforceLogger.log(LOG, 'MEDIATORS', 'property=' + propertyId +
            ' mediators mapped=' + res.mediatorCount);
    }

    private static void populateDocuments(PropertyDetailResult res, Id propertyId) {
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :propertyId
            LIMIT :MAX_CHILD_ROWS
        ]) {
            documentIds.add(link.ContentDocumentId);
        }
        AgentforceLogger.log(LOG, 'DOCS', 'property=' + propertyId +
            ' linked documents=' + documentIds.size());
        if (documentIds.isEmpty()) {
            res.documentCount = 0;
            res.documentLinks = flattenDocuments(res.documents);
            return;
        }

        List<ContentVersion> shareable = [
            SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize, Document_Type__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
              AND IsLatest = true
              AND Shareable_With_Visitors__c = true
            WITH USER_MODE
            ORDER BY Document_Type__c ASC NULLS LAST, Title ASC
            LIMIT :MAX_CHILD_ROWS
        ];
        Map<Id, String> links = publicLinks(shareable);
        for (ContentVersion cv : shareable) {
            DocumentInfo info = new DocumentInfo(cv);
            info.downloadUrl = links.get(cv.Id);
            res.documents.add(info);
        }
        res.documentCount = res.documents.size();
        res.documentLinks = flattenDocuments(res.documents);
        AgentforceLogger.log(LOG, 'DOCS', 'shareable with visitors=' + res.documentCount +
            ' of ' + documentIds.size() + ' linked');
        AgentforceLogger.log(LOG, 'DOCS', 'flattened link text length=' + res.documentLinks.length());
    }

    /**
     * The agent's LLM reads plain fields, not nested Apex objects, so the same
     * documents are handed over a second time as one ready-to-quote block of text.
     */
    private static String flattenDocuments(List<DocumentInfo> docs) {
        if (docs.isEmpty()) {
            return 'No shareable documents are available for this property.';
        }
        List<String> lines = new List<String>();
        for (DocumentInfo doc : docs) {
            String label = String.isBlank(doc.documentType)
                ? doc.title
                : doc.documentType + ': ' + doc.title;
            if (String.isBlank(doc.downloadUrl)) {
                lines.add('- ' + label + ' (link unavailable)');
            } else {
                lines.add('- ' + label + ' - ' + doc.downloadUrl);
            }
        }
        return String.join(lines, '\n');
    }

    /**
     * A visitor on the marketing site has no Salesforce login, so a record link
     * would be useless to them. ContentDistribution issues a password-free
     * public URL per file; one is reused when it already exists.
     */
    public static Map<Id, String> publicLinks(List<ContentVersion> versions) {
        return new LinkIssuer().issue(versions);
    }

    /** Runs unrestricted for the same reason the document read does: the files
     *  belong to whoever uploaded them, not to the agent user. */
    private without sharing class LinkIssuer {
        private Map<Id, String> issue(List<ContentVersion> versions) {
            return issueLinks(versions);
        }
    }

    private static Map<Id, String> issueLinks(List<ContentVersion> versions) {
        Map<Id, String> urls = new Map<Id, String>();
        if (versions.isEmpty()) {
            return urls;
        }

        Set<Id> versionIds = new Set<Id>();
        for (ContentVersion cv : versions) {
            versionIds.add(cv.Id);
        }

        for (ContentDistribution cd : [
            SELECT ContentVersionId, DistributionPublicUrl
            FROM ContentDistribution
            WHERE ContentVersionId IN :versionIds
        ]) {
            if (String.isNotBlank(cd.DistributionPublicUrl)) {
                urls.put(cd.ContentVersionId, cd.DistributionPublicUrl);
            }
        }
        AgentforceLogger.log(LOG, 'DOCS', 'existing public links=' + urls.size() +
            ' of ' + versionIds.size());

        List<ContentDistribution> toCreate = new List<ContentDistribution>();
        for (ContentVersion cv : versions) {
            if (!urls.containsKey(cv.Id)) {
                toCreate.add(new ContentDistribution(
                    Name = cv.Title,
                    ContentVersionId = cv.Id,
                    PreferencesAllowViewInBrowser = true,
                    PreferencesLinkLatestVersion = true,
                    PreferencesNotifyOnVisit = false,
                    PreferencesPasswordRequired = false
                ));
            }
        }
        if (toCreate.isEmpty()) {
            return urls;
        }

        // A distribution that cannot be created must not sink the whole reply;
        // the file simply comes back without a link.
        Database.SaveResult[] created = Database.insert(toCreate, false);
        Set<Id> newIds = new Set<Id>();
        for (Integer i = 0; i < created.size(); i++) {
            if (created[i].isSuccess()) {
                newIds.add(created[i].getId());
            } else {
                AgentforceLogger.log(LOG, 'DOCS', 'no public link for "' +
                    toCreate[i].Name + '": ' + created[i].getErrors());
            }
        }
        if (newIds.isEmpty()) {
            return urls;
        }

        // DistributionPublicUrl is populated by the platform on insert, so the
        // value is only readable once the rows are queried back.
        for (ContentDistribution cd : [
            SELECT ContentVersionId, DistributionPublicUrl
            FROM ContentDistribution WHERE Id IN :newIds
        ]) {
            if (String.isNotBlank(cd.DistributionPublicUrl)) {
                urls.put(cd.ContentVersionId, cd.DistributionPublicUrl);
            }
        }
        AgentforceLogger.log(LOG, 'DOCS', 'created ' + newIds.size() +
            ' public link(s), total=' + urls.size());
        return urls;
    }

    public class PropertyDetailRequest {
        @InvocableVariable(label='Property Name' description='Project name the visitor asked about. An exact name wins; otherwise partial names are matched.')
        public String propertyName;

        @InvocableVariable(label='Property Id' description='Optional. Use when the Id is already known - skips name matching entirely.')
        public String propertyId;
    }

    public class PropertyDetailResult {
        @InvocableVariable(label='Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Found' description='False when no property answers to that name.')
        public Boolean isFound;

        @InvocableVariable(label='Message' description='Human readable outcome, including the other names when a search was ambiguous.')
        public String message;

        @InvocableVariable(label='Property Id')
        public String propertyId;

        @InvocableVariable(label='Property Name')
        public String name;

        @InvocableVariable(label='City')
        public String city;

        @InvocableVariable(label='Address')
        public String address;

        @InvocableVariable(label='Configurations (BHK)')
        public String configurations;

        @InvocableVariable(label='Property Type')
        public String propertyType;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Available' description='False once the project is Sold Out.')
        public Boolean isAvailable;

        @InvocableVariable(label='Price (Min)')
        public Decimal priceMin;

        @InvocableVariable(label='Price (Max)')
        public Decimal priceMax;

        @InvocableVariable(label='Price Range' description='Formatted range the chatbot should quote, e.g. INR 1.2 Cr - 1.8 Cr.')
        public String priceRange;

        @InvocableVariable(label='Possession Date')
        public Date possessionDate;

        @InvocableVariable(label='RERA Number')
        public String reraNumber;

        @InvocableVariable(label='Description')
        public String description;

        @InvocableVariable(label='Latitude')
        public Double latitude;

        @InvocableVariable(label='Longitude')
        public Double longitude;

        @InvocableVariable(label='Amenities' description='Every amenity across all unit types, de-duplicated.')
        public String amenities;

        @InvocableVariable(label='Specification Count')
        public Integer specificationCount;

        @InvocableVariable(label='Specifications' description='One entry per unit type on offer.')
        public List<SpecificationInfo> specifications;

        @InvocableVariable(label='Mediator Count')
        public Integer mediatorCount;

        @InvocableVariable(label='Mediators' description='Everyone who handles this project. Availability is a separate action.')
        public List<MediatorContactInfo> mediators;

        @InvocableVariable(label='Document Count')
        public Integer documentCount;

        @InvocableVariable(label='Documents' description='Only files flagged Shareable With Visitors.')
        public List<DocumentInfo> documents;

        @InvocableVariable(label='Document Links' description='Each shareable document as "Type: Title - public URL", one per line. Show these to the visitor as clickable links.')
        public String documentLinks;
    }

    public class SpecificationInfo {
        @InvocableVariable(label='Specification Name')
        public String name;

        @InvocableVariable(label='Unit Type')
        public String unitType;

        @InvocableVariable(label='Carpet Area')
        public Decimal carpetArea;

        @InvocableVariable(label='Built-up Area')
        public Decimal builtUpArea;

        @InvocableVariable(label='Floor Plan URL')
        public String floorPlanUrl;

        @InvocableVariable(label='Amenities')
        public String amenities;

        public SpecificationInfo() {
        }

        public SpecificationInfo(Property_Specification__c spec) {
            this.name = spec.Name;
            this.unitType = spec.Unit_Type__c;
            this.carpetArea = spec.Carpet_Area__c;
            this.builtUpArea = spec.Built_up_Area__c;
            this.floorPlanUrl = spec.Floor_Plan_URL__c;
            this.amenities = spec.Amenities__c;
        }
    }

    public class MediatorContactInfo {
        @InvocableVariable(label='Mediator Id')
        public String mediatorId;

        @InvocableVariable(label='Name')
        public String name;

        @InvocableVariable(label='Title')
        public String title;

        @InvocableVariable(label='Phone')
        public String phone;

        @InvocableVariable(label='Mobile')
        public String mobilePhone;

        @InvocableVariable(label='Email')
        public String email;

        public MediatorContactInfo() {
        }

        public MediatorContactInfo(Contact c) {
            this.mediatorId = c.Id;
            this.name = c.Name;
            this.title = c.Title;
            this.phone = c.Phone;
            this.mobilePhone = c.MobilePhone;
            this.email = c.Email;
        }
    }

    public class DocumentInfo {
        @InvocableVariable(label='Content Document Id')
        public String contentDocumentId;

        @InvocableVariable(label='Title')
        public String title;

        @InvocableVariable(label='Document Type')
        public String documentType;

        @InvocableVariable(label='File Extension')
        public String fileExtension;

        @InvocableVariable(label='Size (Bytes)')
        public Integer contentSize;

        @InvocableVariable(label='Download Url' description='Public link the visitor can open without logging in. Blank when no link could be issued.')
        public String downloadUrl;

        public DocumentInfo() {
        }

        public DocumentInfo(ContentVersion cv) {
            this.contentDocumentId = cv.ContentDocumentId;
            this.title = cv.Title;
            this.documentType = cv.Document_Type__c;
            this.fileExtension = cv.FileExtension;
            this.contentSize = cv.ContentSize;
        }
    }
}
