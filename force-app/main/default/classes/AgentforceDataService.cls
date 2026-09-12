public without sharing class AgentforceDataService {
    private static final Integer MAX_ROWS = 50;
    private static final String LOG = 'DATA';

    /**
     * Business timezone every site visit is booked in, regardless of the
     * timezone of the user or Agentforce session that submitted the request.
     */
    public static final String BUSINESS_TIMEZONE = 'Asia/Kolkata';

    // Character classes rather than backslash escapes, so the literal needs no
    // double escaping and reads the same as the format the agent is asked for.
    private static final Pattern LOCAL_TIME_PATTERN = Pattern.compile(
        '^[ ]*([0-9]{4})-([0-9]{2})-([0-9]{2})[T ]([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?[ ]*$'
    );

    /**
     * Parses a wall-clock string as IST and returns the matching instant.
     *
     * Accepts "yyyy-MM-dd HH:mm" or "yyyy-MM-ddTHH:mm" (optional seconds).
     * The text carries no offset by design: it is the time the visitor said
     * out loud, so it is read in BUSINESS_TIMEZONE and nothing else. This is
     * the unambiguous path, immune to the timezone of whichever user or agent
     * session happens to run the action.
     *
     * Returns null when the text is blank or not in that shape, so callers can
     * fall back to a Datetime input.
     */
    public static Datetime parseBusinessTime(String localText) {
        if (String.isBlank(localText)) {
            return null;
        }
        Matcher m = LOCAL_TIME_PATTERN.matcher(localText);
        if (!m.matches()) {
            AgentforceLogger.log(LOG, 'PARSE', '"' + localText +
                '" does not match yyyy-MM-dd HH:mm, returning null');
            return null;
        }

        Integer yr = Integer.valueOf(m.group(1));
        Integer mo = Integer.valueOf(m.group(2));
        Integer dy = Integer.valueOf(m.group(3));
        Integer hr = Integer.valueOf(m.group(4));
        Integer mi = Integer.valueOf(m.group(5));
        Integer se = m.group(7) == null ? 0 : Integer.valueOf(m.group(7));

        if (mo < 1 || mo > 12 || dy < 1 || dy > 31 || hr > 23 || mi > 59 || se > 59) {
            AgentforceLogger.log(LOG, 'PARSE', '"' + localText +
                '" parsed but is out of range, returning null');
            return null;
        }

        // Build the wall clock on the GMT calendar, then step back by the IST
        // offset so the reading lands in the business timezone.
        Datetime wallClock = Datetime.newInstanceGmt(yr, mo, dy, hr, mi, se);
        Integer offsetMillis = TimeZone.getTimeZone(BUSINESS_TIMEZONE).getOffset(wallClock);
        Datetime instant = wallClock.addSeconds(-offsetMillis / 1000);
        AgentforceLogger.log(LOG, 'PARSE', '"' + localText + '" -> ' +
            AgentforceLogger.utc(instant) + ' (offset ' +
            (offsetMillis / 3600000) + 'h applied for ' + BUSINESS_TIMEZONE + ')');
        return instant;
    }

    /** Renders an instant as an IST wall clock for anything a human reads. */
    public static String formatBusinessTime(Datetime value) {
        return value == null
            ? 'an unspecified time'
            : value.format('d MMM yyyy, h:mm a', BUSINESS_TIMEZONE) + ' IST';
    }

    /**
     * Renders an instant in the exact shape parseBusinessTime accepts, so a
     * value handed to the agent can be passed straight back into booking
     * without a lossy prose round trip. formatBusinessTime stays the
     * human-readable form; this one is the machine-readable twin.
     */
    public static String formatBusinessTimeForRoundTrip(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd HH:mm', BUSINESS_TIMEZONE);
    }

    public static Map<Id, Contact> mediatorsForProperty(Id propertyId) {
        Map<Id, Contact> mediators = new Map<Id, Contact>();
        for (Mediator_Property__c mp : [
            SELECT Mediator__c, Mediator__r.Name, Mediator__r.FirstName, Mediator__r.LastName,
                   Mediator__r.Phone, Mediator__r.MobilePhone, Mediator__r.Email, Mediator__r.Title
            FROM Mediator_Property__c
            WHERE Property__c = :propertyId
            ORDER BY Mediator__r.Name ASC
            LIMIT :MAX_ROWS
        ]) {
            mediators.put(mp.Mediator__c, mp.Mediator__r);
        }
        AgentforceLogger.log(LOG, 'MEDIATORS_FOR_PROPERTY', 'property=' + propertyId +
            ' -> ' + mediators.size() + ' mapped ' + mediators.keySet());
        return mediators;
    }

    public static Set<Id> busyMediators(Set<Id> mediatorIds, Datetime slotStart, Datetime slotEnd) {
        Set<Id> busy = new Set<Id>();
        if (mediatorIds == null || mediatorIds.isEmpty()) {
            AgentforceLogger.log(LOG, 'BUSY', 'no mediator ids given, nobody is busy');
            return busy;
        }
        for (ServiceAppointment sa : [
            SELECT Mediator__c
            FROM ServiceAppointment
            WHERE Mediator__c IN :mediatorIds
              AND SchedStartTime < :slotEnd
              AND SchedEndTime > :slotStart
              AND StatusCategory != 'Canceled'
        ]) {
            busy.add(sa.Mediator__c);
        }
        AgentforceLogger.log(LOG, 'BUSY', 'checked ' + mediatorIds.size() + ' mediator(s) between ' +
            AgentforceLogger.utc(slotStart) + ' and ' + AgentforceLogger.utc(slotEnd) +
            ' -> busy ' + busy.size() + ' ' + busy);
        return busy;
    }

    /**
     * Every non-cancelled appointment for these mediators that overlaps the
     * window, grouped by mediator. One query for a whole day of candidate
     * slots, so the slot search does not go back to the database per slot.
     * Uses the same status filter as busyMediators.
     */
    public static Map<Id, List<ServiceAppointment>> appointmentsForMediators(
        Set<Id> mediatorIds, Datetime windowStart, Datetime windowEnd
    ) {
        Map<Id, List<ServiceAppointment>> byMediator = new Map<Id, List<ServiceAppointment>>();
        if (mediatorIds == null || mediatorIds.isEmpty()) {
            AgentforceLogger.log(LOG, 'APPOINTMENTS', 'no mediator ids given, nothing to load');
            return byMediator;
        }
        Integer rows = 0;
        for (ServiceAppointment sa : [
            SELECT Mediator__c, SchedStartTime, SchedEndTime
            FROM ServiceAppointment
            WHERE Mediator__c IN :mediatorIds
              AND SchedStartTime < :windowEnd
              AND SchedEndTime > :windowStart
              AND StatusCategory != 'Canceled'
            WITH USER_MODE
        ]) {
            if (!byMediator.containsKey(sa.Mediator__c)) {
                byMediator.put(sa.Mediator__c, new List<ServiceAppointment>());
            }
            byMediator.get(sa.Mediator__c).add(sa);
            rows++;
        }
        AgentforceLogger.log(LOG, 'APPOINTMENTS', 'window ' + AgentforceLogger.utc(windowStart) +
            ' to ' + AgentforceLogger.utc(windowEnd) + ' over ' + mediatorIds.size() +
            ' mediator(s) -> ' + rows + ' appointment(s) across ' + byMediator.size() + ' mediator(s)');
        return byMediator;
    }

    public static ServiceAppointment clashFor(Id mediatorId, Datetime slotStart, Datetime slotEnd) {
        List<ServiceAppointment> clashes = [
            SELECT Id, AppointmentNumber
            FROM ServiceAppointment
            WHERE Mediator__c = :mediatorId
              AND SchedStartTime < :slotEnd
              AND SchedEndTime > :slotStart
              AND StatusCategory != 'Canceled'
            LIMIT 1
        ];
        AgentforceLogger.log(LOG, 'CLASH', 'mediator=' + mediatorId +
            ' window ' + AgentforceLogger.utc(slotStart) + ' to ' + AgentforceLogger.utc(slotEnd) +
            ' -> ' + (clashes.isEmpty() ? 'free' : 'busy with ' + clashes[0].AppointmentNumber));
        return clashes.isEmpty() ? null : clashes[0];
    }

    public static Boolean handlesProperty(Id propertyId, Id mediatorId) {
        Boolean handles = ![
            SELECT Id FROM Mediator_Property__c
            WHERE Property__c = :propertyId AND Mediator__c = :mediatorId
            LIMIT 1
        ].isEmpty();
        AgentforceLogger.log(LOG, 'HANDLES_PROPERTY', 'property=' + propertyId +
            ' mediator=' + mediatorId + ' -> ' + handles);
        return handles;
    }

    public static Contact mediatorById(Id mediatorId) {
        List<Contact> matches = [
            SELECT Id, Name FROM Contact
            WHERE Id = :mediatorId
              AND Id IN (SELECT Mediator__c FROM Mediator_Property__c)
            LIMIT 1
        ];
        AgentforceLogger.log(LOG, 'MEDIATOR_BY_ID', mediatorId + ' -> ' +
            (matches.isEmpty()
                ? 'no match (not linked through Mediator_Property__c)'
                : matches[0].Id + ' ' + matches[0].Name));
        return matches.isEmpty() ? null : matches[0];
    }

    public static Contact mediatorByName(String name) {
        String search = '%' + AgentforceController.escapeLike(name) + '%';
        List<Contact> matches = [
            SELECT Id, Name FROM Contact
            WHERE Name LIKE :search
              AND Id IN (SELECT Mediator__c FROM Mediator_Property__c)
            ORDER BY Name ASC
            LIMIT 1
        ];
        AgentforceLogger.log(LOG, 'MEDIATOR_BY_NAME', '"' + name + '" (search ' + search + ') -> ' +
            (matches.isEmpty() ? 'no match' : matches[0].Id + ' ' + matches[0].Name));
        return matches.isEmpty() ? null : matches[0];
    }
}