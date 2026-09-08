/**
 * Emails a property's visitor-shareable documents.
 *
 * A Service Agent redacts URLs out of anything it says in the chat, so a
 * brochure link can only reach the visitor out of band. Email is that channel.
 */
public with sharing class AgentforceDocumentEmailController {
    /**
     * Files are owned by whoever uploaded them, and the agent user is not that
     * person, so a user-mode read of a brochure returns nothing. The document
     * lookup therefore runs without sharing. Only rows already flagged
     * Shareable_With_Visitors__c are ever selected, so nothing private is
     * reachable through this path.
     */
    private without sharing class DocumentReader {
        private List<ContentVersion> fetch(Id propertyId, String documentType) {
            Set<Id> documentIds = new Set<Id>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId FROM ContentDocumentLink
                WHERE LinkedEntityId = :propertyId
                LIMIT :MAX_ROWS
            ]) {
                documentIds.add(link.ContentDocumentId);
            }
            AgentforceLogger.log(LOG, 'DOCS', 'property=' + propertyId +
                ' linked documents=' + documentIds.size());
            if (documentIds.isEmpty()) {
                return new List<ContentVersion>();
            }

            String wanted = AgentforceController.blankToNull(documentType);
            if (wanted == null) {
                return [
                    SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize, Document_Type__c
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :documentIds
                      AND IsLatest = true
                      AND Shareable_With_Visitors__c = true
                    ORDER BY Document_Type__c ASC NULLS LAST, Title ASC
                    LIMIT :MAX_ROWS
                ];
            }
            AgentforceLogger.log(LOG, 'DOCS', 'filtered to documentType "' + wanted + '"');
            return [
                SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize, Document_Type__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :documentIds
                  AND IsLatest = true
                  AND Shareable_With_Visitors__c = true
                  AND Document_Type__c = :wanted
                ORDER BY Title ASC
                LIMIT :MAX_ROWS
            ];
        }
    }

    private static final Integer MAX_ROWS = 50;
    private static final String LOG = 'EMAIL_DOCUMENTS';

    private static void log(String step, String detail) {
        AgentforceLogger.log(LOG, step, detail);
    }

    private static String show(Object value) {
        return AgentforceLogger.show(value);
    }

    @InvocableMethod(
        label='Email Property Documents'
        description='Emails the visitor the brochure, floor plans and other shareable documents for one property, along with its key details. Returns whether the email was actually sent.'
        category='Property'
    )
    public static List<DocumentEmailResult> emailDocuments(List<DocumentEmailRequest> requests) {
        List<DocumentEmailResult> results = new List<DocumentEmailResult>();

        // Loudest possible marker: if this line is absent from the debug log the
        // action was never invoked at all, whatever the agent claimed in chat.
        System.debug(LoggingLevel.ERROR, '### EMAIL_DOCUMENTS INVOKED ### user=' +
            UserInfo.getUserName() + ' at=' + Datetime.now().formatGMT('yyyy-MM-dd HH:mm:ss') +
            ' UTC requests=' + (requests == null ? 'null' : String.valueOf(requests.size())));

        AgentforceLogger.logContext(LOG, requests == null ? 0 : requests.size());
        if (requests == null) {
            log('ENTRY', 'ABORT: the request list itself was null');
            return results;
        }

        Integer index = 0;
        for (DocumentEmailRequest req : requests) {
            index++;
            DocumentEmailResult res = new DocumentEmailResult();
            res.isSuccess = false;
            res.documentCount = 0;
            try {
                logRequest(index, req);
                System.debug(LoggingLevel.ERROR, '### INPUT #' + index + ' ### email=' +
                    (req == null ? 'null' : show(req.customerEmail)) +
                    ' property=' + (req == null ? 'null' : show(req.propertyName)) +
                    ' propertyId=' + (req == null ? 'null' : show(req.propertyId)) +
                    ' documentType=' + (req == null ? 'null' : show(req.documentType)));
                res.message = send(req, res);
                log('RESULT #' + index, 'isSuccess=' + res.isSuccess +
                    ' documentCount=' + res.documentCount +
                    ' message=' + show(res.message));
                System.debug(LoggingLevel.ERROR, '### RESULT #' + index + ' ### isSuccess=' +
                    res.isSuccess + ' documentCount=' + res.documentCount +
                    ' message=' + res.message);
            } catch (Exception e) {
                res.isSuccess = false;
                res.message = 'Could not email the documents: ' + e.getMessage();
                AgentforceLogger.logException(LOG, 'EXCEPTION #' + index, e);
                System.debug(LoggingLevel.ERROR, '### EXCEPTION #' + index + ' ### ' +
                    e.getTypeName() + ' line ' + e.getLineNumber() + ': ' + e.getMessage());
            }
            results.add(res);
        }

        log('EXIT', 'returning ' + results.size() + ' result(s)');
        return results;
    }

    private static void logRequest(Integer index, DocumentEmailRequest req) {
        if (req == null) {
            log('REQUEST #' + index, 'the request object was null');
            return;
        }
        log('REQUEST #' + index, 'propertyId=' + show(req.propertyId) +
            ' propertyName=' + show(req.propertyName));
        log('REQUEST #' + index, 'customerEmail=' + show(req.customerEmail) +
            ' customerName=' + show(req.customerName) +
            ' documentType=' + show(req.documentType));
    }

    private static String send(DocumentEmailRequest req, DocumentEmailResult res) {
        String email = AgentforceController.blankToNull(req.customerEmail);
        if (email == null) {
            log('SEND', 'STOP: no email address was supplied');
            return 'An email address is required before anything can be sent.';
        }
        if (!isEmailShaped(email)) {
            log('SEND', 'STOP: "' + email + '" is not a usable email address');
            return 'That email address does not look complete, so nothing was sent. Ask the visitor to repeat it.';
        }

        Property__c property = resolveProperty(req);
        if (property == null) {
            log('SEND', 'STOP: no property matched propertyId=' + show(req.propertyId) +
                ' propertyName=' + show(req.propertyName));
            return 'No matching property found, so nothing was sent.';
        }
        log('SEND', 'property resolved: ' + property.Id + ' "' + property.Name + '"');
        res.propertyId = property.Id;
        res.propertyName = property.Name;

        List<ContentVersion> files = shareableFiles(property.Id, req.documentType);
        if (files.isEmpty()) {
            log('SEND', 'STOP: no shareable document for ' + property.Name +
                ' (documentType filter=' + show(req.documentType) + ')');
            return 'No shareable document is on file for ' + property.Name +
                ' right now, so nothing was sent.';
        }

        Map<Id, String> links = AgentforcePropertyDetailController.publicLinks(files);
        List<String> titles = new List<String>();
        for (ContentVersion cv : files) {
            // A file with no public link would arrive as a dead entry, so it is
            // left out of both the email and the count.
            if (String.isNotBlank(links.get(cv.Id))) {
                titles.add(cv.Title);
            } else {
                log('SEND', 'skipping "' + cv.Title + '": no public link could be issued');
            }
        }
        if (titles.isEmpty()) {
            log('SEND', 'STOP: not one file could be given a public link');
            return 'The documents for ' + property.Name +
                ' could not be prepared for sending right now, so nothing was sent.';
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ email });
        mail.setSubject(property.Name + ' - documents you asked for');
        mail.setHtmlBody(buildBody(req, property, files, links));
        mail.setSaveAsActivity(false);

        // The agent runs as an integration user whose address is
        // noreply@salesforce.com; mail sent from there fails SPF and is dropped
        // before it reaches the visitor. A verified org-wide address gives the
        // message a From that recipients will actually accept.
        Id fromAddressId = orgWideAddressId();
        if (fromAddressId != null) {
            mail.setOrgWideEmailAddressId(fromAddressId);
            log('SEND', 'using org-wide from address ' + fromAddressId);
        } else {
            log('SEND', 'WARNING: no verified org-wide address, sending as the running user');
        }
        System.debug(LoggingLevel.ERROR, '### FROM ### orgWideAddressId=' +
            (fromAddressId == null ? 'NONE (falls back to running user)' : String.valueOf(fromAddressId)));

        log('SEND', 'sending to ' + email + ' with ' + titles.size() + ' document link(s)');
        System.debug(LoggingLevel.ERROR, '### SENDING ### to=' + email +
            ' docs=' + titles.size() + ' emailInvocationsUsed=' + Limits.getEmailInvocations() +
            '/' + Limits.getLimitEmailInvocations());
        Messaging.SendEmailResult[] sent = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ mail }, false
        );
        if (!sent.isEmpty() && !sent[0].isSuccess()) {
            log('SEND', 'FAILED: ' + sent[0].getErrors());
            System.debug(LoggingLevel.ERROR, '### SEND FAILED ### ' + sent[0].getErrors());
            return 'The email could not be sent just now. Offer to have the sales team send it instead.';
        }
        System.debug(LoggingLevel.ERROR, '### SEND ACCEPTED BY SALESFORCE ### to=' + email +
            ' (delivery still depends on org Email Deliverability being set to All Email)');

        res.isSuccess = true;
        res.documentCount = titles.size();
        res.sentTo = email;
        log('SEND', 'SUCCESS');
        return 'Sent ' + titles.size() + ' document(s) for ' + property.Name +
            ' to ' + email + ': ' + String.join(titles, ', ') + '.';
    }

    /**
     * Id of the verified org-wide address brochures are sent from.
     *
     * The agent runs as an integration user whose own address is
     * noreply@salesforce.com, which fails SPF and gets dropped by most
     * mailboxes, so a real From address is what makes the mail arrive.
     *
     * It is a constant rather than a query because OrgWideEmailAddress is
     * invisible to the agent user — the query throws for it even without
     * sharing. Replace this when the org-wide address changes; a wrong value
     * only costs the From line, since the send falls back to the running user.
     */
    private static final String ORG_WIDE_ADDRESS_ID = '0D2ak0000007bUHCAY';

    private static Id orgWideAddressId() {
        if (String.isBlank(ORG_WIDE_ADDRESS_ID)) {
            return null;
        }
        try {
            return Id.valueOf(ORG_WIDE_ADDRESS_ID);
        } catch (Exception e) {
            log('SEND', 'ORG_WIDE_ADDRESS_ID is not a valid Id: ' + ORG_WIDE_ADDRESS_ID);
            return null;
        }
    }

    /**
     * Deliberately loose: the goal is to catch a truncated or mistyped address
     * before an email silently disappears, not to enforce the RFC.
     */
    private static Boolean isEmailShaped(String value) {
        return Pattern.matches('^[^@\\s]+@[^@\\s.]+\\.[^@\\s]{2,}$', value);
    }

    private static Property__c resolveProperty(DocumentEmailRequest req) {
        String key = AgentforceController.blankToNull(req.propertyId);
        if (key != null) {
            try {
                Id parsed = Id.valueOf(key);
                if (parsed.getSObjectType() == Property__c.SObjectType) {
                    List<Property__c> byId = [
                        SELECT Id, Name, City__c, Address__c, Configurations__c, Status__c,
                               Price_Range__c, Possession_Date__c, RERA_Number__c
                        FROM Property__c WHERE Id = :parsed WITH USER_MODE LIMIT 1
                    ];
                    if (!byId.isEmpty()) {
                        log('PROPERTY', 'matched by Id ' + parsed);
                        return byId[0];
                    }
                    log('PROPERTY', 'Id ' + parsed + ' returned no row (check sharing)');
                }
            } catch (Exception ignored) {
                log('PROPERTY', '"' + key + '" is not a usable Id, will try it as a name');
            }
        }

        String name = AgentforceController.blankToNull(req.propertyName) != null
            ? AgentforceController.blankToNull(req.propertyName)
            : key;
        if (name == null) {
            log('PROPERTY', 'no property id or name was supplied');
            return null;
        }

        List<Property__c> exact = [
            SELECT Id, Name, City__c, Address__c, Configurations__c, Status__c,
                   Price_Range__c, Possession_Date__c, RERA_Number__c
            FROM Property__c WHERE Name = :name WITH USER_MODE LIMIT 1
        ];
        if (!exact.isEmpty()) {
            log('PROPERTY', 'exact name match on "' + name + '"');
            return exact[0];
        }

        String search = '%' + AgentforceController.escapeLike(name) + '%';
        List<Property__c> partial = [
            SELECT Id, Name, City__c, Address__c, Configurations__c, Status__c,
                   Price_Range__c, Possession_Date__c, RERA_Number__c
            FROM Property__c WHERE Name LIKE :search WITH USER_MODE ORDER BY Name ASC LIMIT 1
        ];
        log('PROPERTY', 'LIKE search ' + search + ' returned ' + partial.size() + ' row(s)');
        return partial.isEmpty() ? null : partial[0];
    }

    private static List<ContentVersion> shareableFiles(Id propertyId, String documentType) {
        List<ContentVersion> files = new DocumentReader().fetch(propertyId, documentType);
        log('DOCS', 'shareable with visitors=' + files.size());
        System.debug(LoggingLevel.ERROR, '### DOCS ### property=' + propertyId +
            ' documentType=' + show(documentType) + ' shareableFound=' + files.size());
        for (ContentVersion cv : files) {
            System.debug(LoggingLevel.ERROR, '###   file: ' + cv.Title +
                ' type=' + cv.Document_Type__c);
        }
        return files;
    }

    private static String buildBody(
        DocumentEmailRequest req,
        Property__c p,
        List<ContentVersion> files,
        Map<Id, String> links
    ) {
        String who = AgentforceController.blankToNull(req.customerName);
        List<String> html = new List<String>();
        html.add('<p>' + (who == null ? 'Hello' : 'Hello ' + esc(who)) + ',</p>');
        html.add('<p>Here are the documents you asked for on <strong>' + esc(p.Name) + '</strong>.</p>');

        List<String> facts = new List<String>();
        addFact(facts, 'Location', String.isBlank(p.Address__c) ? p.City__c : p.Address__c);
        addFact(facts, 'Configurations', p.Configurations__c);
        addFact(facts, 'Price range', p.Price_Range__c);
        addFact(facts, 'Status', p.Status__c);
        addFact(facts, 'Possession', p.Possession_Date__c == null ? null : String.valueOf(p.Possession_Date__c));
        addFact(facts, 'RERA number', p.RERA_Number__c);
        if (!facts.isEmpty()) {
            html.add('<ul>' + String.join(facts, '') + '</ul>');
        }

        List<String> items = new List<String>();
        for (ContentVersion cv : files) {
            String url = links.get(cv.Id);
            if (String.isBlank(url)) {
                continue;
            }
            String label = String.isBlank(cv.Document_Type__c)
                ? esc(cv.Title)
                : esc(cv.Document_Type__c) + ' - ' + esc(cv.Title);
            items.add('<li><a href="' + esc(url) + '">' + label + '</a></li>');
        }
        html.add('<p><strong>Documents</strong></p>');
        html.add('<ul>' + String.join(items, '') + '</ul>');
        html.add('<p>Reply to this email if you would like a site visit or anything else on this project.</p>');
        return String.join(html, '\n');
    }

    private static void addFact(List<String> facts, String label, String value) {
        if (String.isNotBlank(value)) {
            facts.add('<li><strong>' + label + ':</strong> ' + esc(value) + '</li>');
        }
    }

    /** Property and file names are user-entered, so they are escaped, not trusted. */
    private static String esc(String value) {
        return value == null ? '' : value.escapeHtml4();
    }

    public class DocumentEmailRequest {
        @InvocableVariable(label='Customer Email' description='REQUIRED. The address the visitor gave and confirmed. Never invent or assume one.' required=true)
        public String customerEmail;

        @InvocableVariable(label='Property Name' description='Project name whose documents are wanted. An exact name wins; otherwise partial names are matched.')
        public String propertyName;

        @InvocableVariable(label='Property Id' description='Id of the property, taken from an earlier result. Preferred over the name when known.')
        public String propertyId;

        @InvocableVariable(label='Customer Name' description='Optional. Used to greet the visitor in the email.')
        public String customerName;

        @InvocableVariable(label='Document Type' description='Optional filter, e.g. Brochure, Floor Plan, Price List, Specification Sheet, Site Layout, RERA Certificate. Leave blank to send every shareable document for the property.')
        public String documentType;
    }

    public class DocumentEmailResult {
        @InvocableVariable(label='Success' description='True only when the email was actually sent.')
        public Boolean isSuccess;

        @InvocableVariable(label='Message' description='Human readable outcome the agent can say out loud.')
        public String message;

        @InvocableVariable(label='Document Count' description='How many documents the email carried.')
        public Integer documentCount;

        @InvocableVariable(label='Sent To' description='The address the email went to.')
        public String sentTo;

        @InvocableVariable(label='Property Id')
        public String propertyId;

        @InvocableVariable(label='Property Name')
        public String propertyName;
    }
}
