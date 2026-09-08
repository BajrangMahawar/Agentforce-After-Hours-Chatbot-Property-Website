public with sharing class AgentforceSiteVisitController {
    private static final Integer DEFAULT_DURATION_MINUTES = 60;
    private static final String LEAD_SOURCE = 'Website Chatbot';
    private static final String LEAD_COMPANY = 'Website Enquiry';

    private static final String LOG = 'CREATE_APPOINTMENT';

    private static void log(String step, String detail) {
        AgentforceLogger.log(LOG, step, detail);
    }

    private static String show(Object value) {
        return AgentforceLogger.show(value);
    }

    @InvocableMethod(
    label='Create Site Visit Appointment'
        description='Books a site visit for a property with a mediator at a given date and time, capturing the visitor as a Lead. Returns the Appointment Number.'
        category='Property'
        )
    public static List<SiteVisitResult> createSiteVisit(List<SiteVisitRequest> requests) {
        List<SiteVisitResult> results = new List<SiteVisitResult>();

        AgentforceLogger.logContext(LOG, requests == null ? 0 : requests.size());

        if (requests == null) {
            log('ENTRY', 'ABORT: the request list itself was null');
            return results;
        }

        Integer index = 0;
        for (SiteVisitRequest req : requests) {
            index++;
            SiteVisitResult res = new SiteVisitResult();
            res.isSuccess = false;
            try {
                logRequest(index, req);
                res.message = book(req, res);
                log('RESULT #' + index, 'isSuccess=' + res.isSuccess +
                    ' appointmentNumber=' + show(res.appointmentNumber) +
                    ' message=' + show(res.message));
            } catch (Exception e) {
                res.isSuccess = false;
                res.appointmentNumber = null;
                res.message = 'Could not book the site visit: ' + e.getMessage();
                // The type and line number are what actually identify a
                // validation rule, a required field or a sharing failure.
                AgentforceLogger.logException(LOG, 'EXCEPTION #' + index, e);
            }
            results.add(res);
        }

        log('EXIT', 'returning ' + results.size() + ' result(s)');
        return results;
    }

    /** Dumps every inbound field, so a wrong or missing input is visible. */
    private static void logRequest(Integer index, SiteVisitRequest req) {
        if (req == null) {
            log('REQUEST #' + index, 'the request object was null');
            return;
        }
        log('REQUEST #' + index, 'propertyId=' + show(req.propertyId) +
            ' propertyName=' + show(req.propertyName));
        log('REQUEST #' + index, 'mediatorId=' + show(req.mediatorId) +
            ' mediatorName=' + show(req.mediatorName));
        log('REQUEST #' + index, 'customerName=' + show(req.customerName) +
            ' customerEmail=' + show(req.customerEmail) +
            ' customerPhone=' + show(req.customerPhone));
        log('REQUEST #' + index, 'startTimeText=' + show(req.startTimeText) +
            ' endTimeText=' + show(req.endTimeText));
        log('REQUEST #' + index, 'startTime(raw)=' + show(req.startTime) +
            ' endTime(raw)=' + show(req.endTime) +
            ' durationMinutes=' + show(req.durationMinutes));
        log('REQUEST #' + index, 'parentRecordId=' + show(req.parentRecordId));
    }

    private static String book(SiteVisitRequest req, SiteVisitResult res) {
        log('BOOK', 'starting');

        Datetime slotStart = resolveStart(req);
        if (slotStart == null) {
            log('BOOK', 'STOP: no start time could be resolved from either input');
            return 'A date and time is required to book a site visit.';
        }
        log('BOOK', 'slotStart resolved: ' + AgentforceLogger.utc(slotStart) + ' = ' + AgentforceDataService.formatBusinessTime(slotStart));

        Property__c property = resolveProperty(req);
        if (property == null) {
            log('BOOK', 'STOP: no property matched propertyId=' + show(req.propertyId) +
                ' propertyName=' + show(req.propertyName));
            return 'No matching property found, so nothing was booked.';
        }
        log('BOOK', 'property resolved: ' + property.Id + ' "' + property.Name + '"');

        Contact mediator = resolveMediator(req);
        if (mediator == null) {
            log('BOOK', 'STOP: no mediator matched mediatorId=' + show(req.mediatorId) +
                ' mediatorName=' + show(req.mediatorName) +
                ' (a mediator must be linked through Mediator_Property__c)');
            return 'No matching mediator found, so nothing was booked.';
        }
        log('BOOK', 'mediator resolved: ' + mediator.Id + ' "' + mediator.Name + '"');

        Datetime slotEnd = resolveEnd(req);
        if (slotEnd == null) {
            Integer mins = (req.durationMinutes == null || req.durationMinutes <= 0)
                ? DEFAULT_DURATION_MINUTES
                : req.durationMinutes;
            slotEnd = slotStart.addMinutes(mins);
            log('BOOK', 'no end time given, applied ' + mins + ' minute duration');
        }
        log('BOOK', 'slotEnd resolved: ' + AgentforceLogger.utc(slotEnd) + ' = ' + AgentforceDataService.formatBusinessTime(slotEnd));

        if (slotEnd <= slotStart) {
            log('BOOK', 'STOP: slotEnd is not after slotStart');
            return 'The requested slot ends before it starts, so nothing was booked.';
        }

        ServiceAppointment clash = AgentforceDataService.clashFor(mediator.Id, slotStart, slotEnd);
        if (clash != null) {
            log('BOOK', 'STOP: clash with existing appointment ' + clash.AppointmentNumber +
                ' (' + clash.Id + ') for mediator ' + mediator.Id);
            return mediator.Name + ' already has site visit ' + clash.AppointmentNumber +
                ' in that slot, so nothing was booked. Ask for another mediator or another time.';
        }
        log('BOOK', 'no clash for mediator ' + mediator.Id + ' in that slot');

        Boolean handlesProperty = AgentforceDataService.handlesProperty(property.Id, mediator.Id);
        log('BOOK', 'mediator mapped to this property: ' + handlesProperty);

        Lead visitor = resolveLead(req, property, slotStart);
        log('BOOK', 'lead resolved: ' + visitor.Id);

        Id parentId = AgentforceController.blankToNull(req.parentRecordId) != null
            ? (Id) req.parentRecordId.trim()
            : visitor.Id;
        log('BOOK', 'parentRecordId=' + parentId +
            (parentId == visitor.Id ? ' (the lead)' : ' (supplied by the caller)'));

        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId = parentId,
        Lead__c = visitor.Id,
        Property__c = property.Id,
        Mediator__c = mediator.Id,
        ContactId = findExistingContact(req),
        Subject = 'Site visit - ' + property.Name,
        Status = 'Scheduled',
        SchedStartTime = slotStart,
        SchedEndTime = slotEnd,
        EarliestStartTime = slotStart,
        DueDate = slotEnd,
        Email = AgentforceController.blankToNull(req.customerEmail),
        Phone = AgentforceController.blankToNull(req.customerPhone),
        Description = 'Booked by the after-hours chatbot for ' + property.Name +
            ' with ' + mediator.Name + '.'
            );

        log('INSERT', 'about to insert ServiceAppointment in USER_MODE:' +
            ' ParentRecordId=' + sa.ParentRecordId +
            ' Lead__c=' + sa.Lead__c +
            ' Property__c=' + sa.Property__c +
            ' Mediator__c=' + sa.Mediator__c +
            ' ContactId=' + show(sa.ContactId));
        log('INSERT', '  Subject=' + sa.Subject + ' Status=' + sa.Status +
            ' Email=' + show(sa.Email) + ' Phone=' + show(sa.Phone));
        log('INSERT', '  SchedStartTime=' + AgentforceLogger.utc(sa.SchedStartTime) +
            ', SchedEndTime=' + AgentforceLogger.utc(sa.SchedEndTime));
        log('INSERT', '  createable=' + Schema.SObjectType.ServiceAppointment.isCreateable() +
            ' accessible=' + Schema.SObjectType.ServiceAppointment.isAccessible());

        Database.insert(sa, AccessLevel.USER_MODE);
        log('INSERT', 'SUCCESS, new ServiceAppointment Id=' + sa.Id);

        ServiceAppointment saved = [
            SELECT AppointmentNumber, SchedStartTime, SchedEndTime
            FROM ServiceAppointment WHERE Id = :sa.Id WITH USER_MODE LIMIT 1
        ];
        log('INSERT', 'read back AppointmentNumber=' + saved.AppointmentNumber +
            ' start=' + AgentforceDataService.formatBusinessTime(saved.SchedStartTime) +
            ' end=' + AgentforceDataService.formatBusinessTime(saved.SchedEndTime));

        res.isSuccess = true;
        res.appointmentNumber = saved.AppointmentNumber;
        res.serviceAppointmentId = sa.Id;
        res.propertyId = property.Id;
        res.propertyName = property.Name;
        res.mediatorId = mediator.Id;
        res.mediatorName = mediator.Name;
        res.leadId = visitor.Id;
        res.scheduledStart = saved.SchedStartTime;
        res.scheduledEnd = saved.SchedEndTime;

        String message = 'Site visit ' + saved.AppointmentNumber + ' booked at ' + property.Name +
            ' with ' + mediator.Name + ' on ' + AgentforceDataService.formatBusinessTime(saved.SchedStartTime) + '.';
        if (!handlesProperty) {
            message += ' Note: this mediator is not mapped to this property.';
        }
        return message;
    }

    /**
     * Start of the slot. The text field wins when present: it states an IST
     * wall clock outright, so it cannot be re-interpreted against whatever
     * timezone the Agentforce session user happens to carry. The Datetime
     * field stays supported as an absolute instant for existing callers.
     */
    private static Datetime resolveStart(SiteVisitRequest req) {
        Datetime fromText = AgentforceDataService.parseBusinessTime(req.startTimeText);
        if (fromText != null) {
            log('TIME', 'start came from IST text "' + req.startTimeText + '" -> ' +
                AgentforceLogger.utc(fromText));
            return fromText;
        }
        if (String.isNotBlank(req.startTimeText)) {
            log('TIME', 'WARNING: startTimeText "' + req.startTimeText +
                '" did not match yyyy-MM-dd HH:mm, falling back to the Datetime field');
        }
        log('TIME', 'start came from the Datetime field: ' + show(req.startTime) +
            ' (interpreted as an absolute instant)');
        return req.startTime;
    }

    private static Datetime resolveEnd(SiteVisitRequest req) {
        Datetime fromText = AgentforceDataService.parseBusinessTime(req.endTimeText);
        if (fromText != null) {
            log('TIME', 'end came from IST text "' + req.endTimeText + '" -> ' +
                AgentforceLogger.utc(fromText));
            return fromText;
        }
        if (String.isNotBlank(req.endTimeText)) {
            log('TIME', 'WARNING: endTimeText "' + req.endTimeText +
                '" did not match yyyy-MM-dd HH:mm, falling back to the Datetime field');
        }
        return req.endTime;
    }

    private static Property__c resolveProperty(SiteVisitRequest req) {
        String key = AgentforceController.blankToNull(req.propertyId);
        if (key != null) {
            try {
                Id parsed = Id.valueOf(key);
                if (parsed.getSObjectType() == Property__c.SObjectType) {
                    List<Property__c> byId = [SELECT Id, Name FROM Property__c WHERE Id = :parsed WITH USER_MODE LIMIT 1];
                    if (!byId.isEmpty()) {
                        log('PROPERTY', 'matched by Id ' + parsed);
                        return byId[0];
                    }
                    log('PROPERTY', 'Id ' + parsed + ' is a Property Id but returned no row (check sharing)');
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
        List<Property__c> exact = [SELECT Id, Name FROM Property__c WHERE Name = :name WITH USER_MODE LIMIT 1];
        if (!exact.isEmpty()) {
            log('PROPERTY', 'exact name match on "' + name + '"');
            return exact[0];
        }
        String search = '%' + AgentforceController.escapeLike(name) + '%';
        List<Property__c> partial = [
            SELECT Id, Name FROM Property__c WHERE Name LIKE :search WITH USER_MODE ORDER BY Name ASC LIMIT 1
        ];
        log('PROPERTY', 'LIKE search ' + search + ' returned ' + partial.size() + ' row(s)');
        return partial.isEmpty() ? null : partial[0];
    }

    private static Contact resolveMediator(SiteVisitRequest req) {
        String key = AgentforceController.blankToNull(req.mediatorId);
        if (key != null) {
            try {
                Id parsed = Id.valueOf(key);
                if (parsed.getSObjectType() == Contact.SObjectType) {
                    Contact byId = AgentforceDataService.mediatorById(parsed);
                    if (byId != null) {
                        log('MEDIATOR', 'matched by Id ' + parsed);
                        return byId;
                    }
                    log('MEDIATOR', 'Contact ' + parsed +
                        ' is not linked to any property through Mediator_Property__c');
                }
            } catch (Exception ignored) {
                log('MEDIATOR', '"' + key + '" is not a usable Id, will try it as a name');
            }
        }

        String name = AgentforceController.blankToNull(req.mediatorName) != null
            ? AgentforceController.blankToNull(req.mediatorName)
            : key;
        if (name == null) {
            log('MEDIATOR', 'no mediator id or name was supplied');
            return null;
        }
        Contact byName = AgentforceDataService.mediatorByName(name);
        log('MEDIATOR', 'name search "' + name + '" -> ' +
            (byName == null ? 'no match' : byName.Id + ' ' + byName.Name));
        return byName;
    }

    private static Id findExistingContact(SiteVisitRequest req) {
        String email = AgentforceController.blankToNull(req.customerEmail);
        String phone = AgentforceController.blankToNull(req.customerPhone);
        if (email == null && phone == null) {
            log('CONTACT', 'no email or phone given, ContactId stays null');
            return null;
        }
        List<Contact> matches = [
            SELECT Id FROM Contact
            WHERE (Email != NULL AND Email = :email)
               OR (Phone != NULL AND Phone = :phone)
               OR (MobilePhone != NULL AND MobilePhone = :phone)
            WITH USER_MODE
            LIMIT 1
        ];
        log('CONTACT', 'lookup by email=' + show(email) + ' phone=' + show(phone) +
            ' -> ' + (matches.isEmpty() ? 'no match' : String.valueOf(matches[0].Id)));
        return matches.isEmpty() ? null : matches[0].Id;
    }

    private static Lead resolveLead(SiteVisitRequest req, Property__c property, Datetime slotStart) {
        String email = AgentforceController.blankToNull(req.customerEmail);
        String phone = AgentforceController.blankToNull(req.customerPhone);

        if (email != null || phone != null) {
            List<Lead> existing = [
                SELECT Id, Name FROM Lead
                WHERE IsConverted = false
                  AND ((Email != NULL AND Email = :email) OR (Phone != NULL AND Phone = :phone))
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                log('LEAD', 'reusing existing lead ' + existing[0].Id);
                return existing[0];
            }
            log('LEAD', 'no open lead matched email=' + show(email) + ' phone=' + show(phone));
        }

        Lead visitor = new Lead(
            LastName = leadLastName(req),
        Company = LEAD_COMPANY,
        Email = email,
        Phone = phone,
        LeadSource = LEAD_SOURCE,
        Property_of_Interest__c = property.Id,
        Enquiry_Notes__c = 'Site visit requested through the after-hours chatbot for ' +
            property.Name + ' on ' + AgentforceDataService.formatBusinessTime(slotStart) + '.'
            );
        log('LEAD', 'inserting new lead: LastName=' + visitor.LastName +
            ' Company=' + visitor.Company + ' Email=' + show(visitor.Email) +
            ' Phone=' + show(visitor.Phone) +
            ' Property_of_Interest__c=' + visitor.Property_of_Interest__c);

        // Without this the lead is owned by whoever the agent session runs as
        // (the Einstein service user), which keeps it off every human's list
        // view. The assignment rules decide the real owner instead.
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.assignmentRuleHeader.useDefaultRule = true;
        visitor.setOptions(opts);

        Database.insert(visitor, AccessLevel.USER_MODE);
        log('LEAD', 'lead inserted: ' + visitor.Id);
        return visitor;
    }

    private static String leadLastName(SiteVisitRequest req) {
        String name = AgentforceController.blankToNull(req.customerName);
        if (name != null) {
            return name.length() > 80 ? name.substring(0, 80) : name;
        }
        String email = AgentforceController.blankToNull(req.customerEmail);
        if (email != null && email.contains('@')) {
            return email.substringBefore('@');
        }
        String phone = AgentforceController.blankToNull(req.customerPhone);
        return phone != null ? 'Visitor ' + phone : 'Website Visitor';
    }

    public class SiteVisitRequest {
        @InvocableVariable(label='Property Id' description='Id of the property being visited. Preferred over the name.')
        public String propertyId;

        @InvocableVariable(label='Property Name' description='Project name, used when no Property Id is known.')
        public String propertyName;

        @InvocableVariable(label='Mediator Id' description='Contact Id of the mediator taking the visit. Preferred over the name.')
        public String mediatorId;

        @InvocableVariable(label='Mediator Name' description='Mediator name, used when no Mediator Id is known.')
        public String mediatorName;

        @InvocableVariable(label='Customer Name' description='Visitor name. Falls back to the email handle when blank.')
        public String customerName;

        @InvocableVariable(label='Customer Email')
        public String customerEmail;

        @InvocableVariable(label='Customer Phone')
        public String customerPhone;

        @InvocableVariable(label='Start Time (IST Text)' description='PREFERRED. The requested date and time as plain text in India Standard Time, formatted yyyy-MM-dd HH:mm (24 hour), e.g. 2026-09-09 15:00 for 3 PM. Use this rather than Start Time so the slot cannot shift with the session timezone.')
        public String startTimeText;

        @InvocableVariable(label='End Time (IST Text)' description='Optional slot end as plain text in India Standard Time, formatted yyyy-MM-dd HH:mm. Leave blank to use Duration (Minutes).')
        public String endTimeText;

        @InvocableVariable(label='Start Time' description='Fallback for Start Time (IST Text). An absolute instant; prefer the IST text field.')
        public Datetime startTime;

        @InvocableVariable(label='End Time' description='Site-visit end, always read as India Standard Time (IST). Leave blank to use Duration (Minutes) instead.')
        public Datetime endTime;

        @InvocableVariable(label='Duration (Minutes)' description='Slot length when no End Time is given. Defaults to 60.')
        public Integer durationMinutes;

        @InvocableVariable(label='Parent Record Id' description='Optional. Overrides the Lead the appointment is filed under.')
        public String parentRecordId;
    }

    public class SiteVisitResult {
        @InvocableVariable(label='Success' description='True only when the appointment was actually created.')
        public Boolean isSuccess;

        @InvocableVariable(label='Appointment Number' description='The booking reference to read back to the visitor.')
        public String appointmentNumber;

        @InvocableVariable(label='Message' description='Human readable outcome the agent can say out loud.')
        public String message;

        @InvocableVariable(label='Service Appointment Id')
        public String serviceAppointmentId;

        @InvocableVariable(label='Property Id')
        public String propertyId;

        @InvocableVariable(label='Property Name')
        public String propertyName;

        @InvocableVariable(label='Mediator Id')
        public String mediatorId;

        @InvocableVariable(label='Mediator Name')
        public String mediatorName;

        @InvocableVariable(label='Lead Id' description='The visitor captured for follow-up.')
        public String leadId;

        @InvocableVariable(label='Scheduled Start' description='Booked start instant. Read it back to the visitor in IST.')
        public Datetime scheduledStart;

        @InvocableVariable(label='Scheduled End')
        public Datetime scheduledEnd;
    }
}
