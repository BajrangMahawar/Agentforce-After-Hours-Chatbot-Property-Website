public with sharing class AgentforceMediatorController {
    private static final Integer MAX_RESULTS = 50;
    private static final String LOG = 'GET_MEDIATOR';

    @InvocableMethod(
        label='Get Available Mediators'
        description='Returns the mediators mapped to a property who have no overlapping site visit at the requested time. Returns an empty list when none are free.'
        category='Property'
    )
    public static List<MediatorSearchResult> getMediator(List<MediatorSearchRequest> requests) {
        List<MediatorSearchResult> results = new List<MediatorSearchResult>();

        AgentforceLogger.logContext(LOG, requests == null ? 0 : requests.size());
        if (requests == null) {
            AgentforceLogger.log(LOG, 'ENTRY', 'ABORT: the request list itself was null');
            return results;
        }

        Integer index = 0;
        for (MediatorSearchRequest req : requests) {
            index++;
            MediatorSearchResult res = new MediatorSearchResult();
            res.mediators = new List<MediatorInfo>();
            res.mediatorCount = 0;
            try {
                logRequest(index, req);
                res.isSuccess = true;
                res.message = findAvailable(req, res);
                AgentforceLogger.log(LOG, 'RESULT #' + index,
                    'isSuccess=true mediatorCount=' + res.mediatorCount);
                for (MediatorInfo info : res.mediators) {
                    // The agent must pass one of these ids straight back into
                    // Create Service Appointment, so log exactly what it got.
                    AgentforceLogger.log(LOG, 'RESULT #' + index,
                        '  available: mediatorId=' + info.mediatorId + ' name=' + info.name);
                }
                AgentforceLogger.log(LOG, 'RESULT #' + index, 'message=' + AgentforceLogger.show(res.message));
            } catch (Exception e) {
                res.mediators = new List<MediatorInfo>();
                res.mediatorCount = 0;
                res.isSuccess = false;
                res.message = 'Could not check mediator availability: ' + e.getMessage();
                AgentforceLogger.logException(LOG, 'EXCEPTION #' + index, e);
            }
            results.add(res);
        }
        AgentforceLogger.log(LOG, 'EXIT', 'returning ' + results.size() + ' result(s)');
        return results;
    }

    /** Dumps every inbound field, so a wrong or missing input is visible. */
    private static void logRequest(Integer index, MediatorSearchRequest req) {
        if (req == null) {
            AgentforceLogger.log(LOG, 'REQUEST #' + index, 'the request object was null');
            return;
        }
        AgentforceLogger.log(LOG, 'REQUEST #' + index,
            'propertyId=' + AgentforceLogger.show(req.propertyId) +
            ' propertyName=' + AgentforceLogger.show(req.propertyName));
        AgentforceLogger.log(LOG, 'REQUEST #' + index,
            'startTimeText=' + AgentforceLogger.show(req.startTimeText) +
            ' endTimeText=' + AgentforceLogger.show(req.endTimeText));
        AgentforceLogger.log(LOG, 'REQUEST #' + index,
            'startTime(raw)=' + AgentforceLogger.show(req.startTime) +
            ' endTime(raw)=' + AgentforceLogger.show(req.endTime) +
            ' durationMinutes=' + AgentforceLogger.show(req.durationMinutes));
    }

    private static String findAvailable(MediatorSearchRequest req, MediatorSearchResult res) {
        AgentforceLogger.log(LOG, 'FIND', 'starting');

        Datetime slotStart = resolveStart(req);
        if (slotStart == null) {
            AgentforceLogger.log(LOG, 'FIND', 'STOP: no start time could be resolved from either input');
            return 'A start time is required to check mediator availability.';
        }
        AgentforceLogger.log(LOG, 'FIND', 'slotStart=' + AgentforceLogger.utc(slotStart) +
            ' = ' + AgentforceDataService.formatBusinessTime(slotStart));

        Id propertyId = resolveProperty(req);
        if (propertyId == null) {
            AgentforceLogger.log(LOG, 'FIND', 'STOP: no property matched propertyId=' +
                AgentforceLogger.show(req.propertyId) +
                ' propertyName=' + AgentforceLogger.show(req.propertyName));
            return 'No matching property found, so no mediator could be looked up.';
        }
        AgentforceLogger.log(LOG, 'FIND', 'property resolved: ' + propertyId);

        Datetime slotEnd = resolveEnd(req);
        if (slotEnd == null) {
            Integer mins = (req.durationMinutes == null || req.durationMinutes <= 0) ? 60 : req.durationMinutes;
            slotEnd = slotStart.addMinutes(mins);
            AgentforceLogger.log(LOG, 'FIND', 'no end time given, applied ' + mins + ' minute duration');
        }
        AgentforceLogger.log(LOG, 'FIND', 'slotEnd=' + AgentforceLogger.utc(slotEnd) +
            ' = ' + AgentforceDataService.formatBusinessTime(slotEnd));

        if (slotEnd <= slotStart) {
            AgentforceLogger.log(LOG, 'FIND', 'STOP: slotEnd is not after slotStart');
            return 'The requested slot ends before it starts.';
        }

        Map<Id, Contact> mediators = AgentforceDataService.mediatorsForProperty(propertyId);
        AgentforceLogger.log(LOG, 'FIND', 'mediators mapped to this property: ' + mediators.size() +
            ' ' + mediators.keySet());
        if (mediators.isEmpty()) {
            AgentforceLogger.log(LOG, 'FIND',
                'STOP: nothing in Mediator_Property__c links a mediator to ' + propertyId);
            return 'No mediator is mapped to this property yet.';
        }

        Set<Id> busy = AgentforceDataService.busyMediators(mediators.keySet(), slotStart, slotEnd);
        AgentforceLogger.log(LOG, 'FIND', 'busy in that window: ' + busy.size() + ' ' + busy);

        for (Id mediatorId : mediators.keySet()) {
            if (!busy.contains(mediatorId)) {
                res.mediators.add(new MediatorInfo(mediators.get(mediatorId)));
            }
        }
        res.mediatorCount = res.mediators.size();
        AgentforceLogger.log(LOG, 'FIND', 'free: ' + res.mediatorCount +
            ' of ' + mediators.size() + ' mapped');

        return res.mediatorCount == 0
            ? 'All ' + mediators.size() + ' mediator(s) for this property are already booked for that slot.'
            : res.mediatorCount + ' mediator(s) available for the requested slot.';
    }

    /** Mirrors the site-visit resolution so both actions agree on the slot. */
    private static Datetime resolveStart(MediatorSearchRequest req) {
        Datetime fromText = AgentforceDataService.parseBusinessTime(req.startTimeText);
        if (fromText != null) {
            AgentforceLogger.log(LOG, 'TIME', 'start came from IST text "' + req.startTimeText +
                '" -> ' + AgentforceLogger.utc(fromText));
            return fromText;
        }
        if (String.isNotBlank(req.startTimeText)) {
            AgentforceLogger.log(LOG, 'TIME', 'WARNING: startTimeText "' + req.startTimeText +
                '" did not match yyyy-MM-dd HH:mm, falling back to the Datetime field');
        }
        AgentforceLogger.log(LOG, 'TIME', 'start came from the Datetime field: ' +
            AgentforceLogger.show(req.startTime) + ' (interpreted as an absolute instant)');
        return req.startTime;
    }

    private static Datetime resolveEnd(MediatorSearchRequest req) {
        Datetime fromText = AgentforceDataService.parseBusinessTime(req.endTimeText);
        if (fromText != null) {
            AgentforceLogger.log(LOG, 'TIME', 'end came from IST text "' + req.endTimeText +
                '" -> ' + AgentforceLogger.utc(fromText));
            return fromText;
        }
        if (String.isNotBlank(req.endTimeText)) {
            AgentforceLogger.log(LOG, 'TIME', 'WARNING: endTimeText "' + req.endTimeText +
                '" did not match yyyy-MM-dd HH:mm, falling back to the Datetime field');
        }
        return req.endTime;
    }

    private static Id resolveProperty(MediatorSearchRequest req) {
        String propertyId = AgentforceController.blankToNull(req.propertyId);
        if (propertyId != null) {
            try {
                Id parsed = Id.valueOf(propertyId);
                if (parsed.getSObjectType() == Property__c.SObjectType) {
                    AgentforceLogger.log(LOG, 'PROPERTY', 'using supplied Id ' + parsed);
                    return parsed;
                }
                AgentforceLogger.log(LOG, 'PROPERTY', propertyId + ' is an Id but not a Property Id');
            } catch (Exception ignored) {
                AgentforceLogger.log(LOG, 'PROPERTY', '"' + propertyId +
                    '" is not a usable Id, will try it as a name');
            }
        }

        String name = AgentforceController.blankToNull(req.propertyName) != null ? AgentforceController.blankToNull(req.propertyName) : propertyId;
        if (name == null) {
            AgentforceLogger.log(LOG, 'PROPERTY', 'no property id or name was supplied');
            return null;
        }
        String search = '%' + AgentforceController.escapeLike(name) + '%';
        List<Property__c> matches = [
            SELECT Id FROM Property__c WHERE Name LIKE :search WITH USER_MODE ORDER BY Name ASC LIMIT 1
        ];
        AgentforceLogger.log(LOG, 'PROPERTY', 'LIKE search ' + search +
            ' returned ' + matches.size() + ' row(s)');
        return matches.isEmpty() ? null : matches[0].Id;
    }

    public class MediatorSearchRequest {
        @InvocableVariable(label='Property Id' description='Id of the property the visitor asked about. Preferred over the name.')
        public String propertyId;

        @InvocableVariable(label='Property Name' description='Project name, used only when no Property Id is known. Partial names are matched.')
        public String propertyName;

        @InvocableVariable(label='Start Time (IST Text)' description='PREFERRED. The requested start as plain text in India Standard Time, formatted yyyy-MM-dd HH:mm (24 hour), e.g. 2026-09-09 15:00 for 3 PM.')
        public String startTimeText;

        @InvocableVariable(label='End Time (IST Text)' description='Optional slot end as plain text in India Standard Time, formatted yyyy-MM-dd HH:mm.')
        public String endTimeText;

        @InvocableVariable(label='Start Time' description='Fallback for Start Time (IST Text). An absolute instant; prefer the IST text field.')
        public Datetime startTime;

        @InvocableVariable(label='End Time' description='Requested site-visit end, always read as India Standard Time (IST). Leave blank to use Duration (Minutes) instead.')
        public Datetime endTime;

        @InvocableVariable(label='Duration (Minutes)' description='Slot length when no End Time is given. Defaults to 60.')
        public Integer durationMinutes;
    }

    public class MediatorSearchResult {
        @InvocableVariable(label='Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Message' description='Human readable outcome the agent can say out loud.')
        public String message;

        @InvocableVariable(label='Mediator Count')
        public Integer mediatorCount;

        @InvocableVariable(label='Mediators' description='Mediators free for the requested slot. Empty when nobody is available.')
        public List<MediatorInfo> mediators;
    }

    public class MediatorInfo {
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

        public MediatorInfo() {
        }

        public MediatorInfo(Contact c) {
            this.mediatorId = c.Id;
            this.name = c.Name;
            this.title = c.Title;
            this.phone = c.Phone;
            this.mobilePhone = c.MobilePhone;
            this.email = c.Email;
        }
    }
}
