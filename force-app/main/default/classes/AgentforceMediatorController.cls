public with sharing class AgentforceMediatorController {
    private static final String LOG = 'GET_MEDIATOR';

    // Visiting calendar. Changing these needs a deploy — that is deliberate.
    private static final String  BUSINESS_TZ      = 'Asia/Kolkata';
    private static final Integer OPEN_MINUTES     = 11 * 60;  // 11:00
    private static final Integer CLOSE_MINUTES    = 18 * 60;  // 18:00
    private static final Integer DEFAULT_DURATION = 60;
    private static final Integer SLOT_INTERVAL    = 60;
    private static final Integer MIN_LEAD_MINUTES = 120;
    private static final Integer MAX_SLOTS        = 3;
    private static final Set<String> CLOSED_DAYS  =
        new Set<String>{ 'saturday', 'sunday' };

    /** Guard on the candidate grid, so a bad interval cannot spin. */
    private static final Integer MAX_CANDIDATES = 200;
    /** How far nextOpenTextFrom will look before giving up. */
    private static final Integer LOOKAHEAD_DAYS = 21;

    // Visitor-facing strings. None of these may carry an Id, a raw Datetime or
    // a count, because the agent reads them out loud.
    private static final String MSG_SLOTS_INSIDE  = 'Slots are available close to the requested time.';
    private static final String MSG_SLOTS_OUTSIDE =
        'The requested time is outside site visit hours. Slots are available inside the visiting window that day.';
    private static final String MSG_CLOSED_DAY    = 'Site visits do not run on that day.';
    private static final String MSG_NONE_FREE     = 'No mediator has a free slot on that day.';
    private static final String MSG_NO_MEDIATOR   = 'No mediator is mapped to this property yet.';
    private static final String MSG_FAILED        = 'Could not check availability.';

    @InvocableMethod(
        label='Get Available Mediators'
        description='Returns bookable site visit slots inside visiting hours on the requested date, one slot per mediator, nearest to the requested time first.'
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
            res.slots = new List<SlotInfo>();
            res.mediatorCount = 0;
            res.slotCount = 0;
            res.isWithinBusinessHours = true;
            try {
                logRequest(index, req);
                res.isSuccess = true;
                res.message = findAvailable(req, res);
                AgentforceLogger.log(LOG, 'RESULT #' + index,
                    'isSuccess=true withinHours=' + res.isWithinBusinessHours +
                    ' slotCount=' + res.slotCount + ' mediatorCount=' + res.mediatorCount +
                    ' nextOpenText=' + AgentforceLogger.show(res.nextOpenText));
                for (SlotInfo slot : res.slots) {
                    // The agent passes startTimeText and the mediator id straight
                    // back into Create Service Appointment, so log exactly what
                    // it received.
                    AgentforceLogger.log(LOG, 'RESULT #' + index,
                        '  slot: mediatorId=' + slot.mediatorId + ' name=' + slot.mediatorName +
                        ' start=' + slot.startTimeText + ' end=' + slot.endTimeText);
                }
                AgentforceLogger.log(LOG, 'RESULT #' + index, 'message=' + AgentforceLogger.show(res.message));
            } catch (Exception e) {
                // The raw exception text can name records or fields, and the
                // agent may repeat `message` to a visitor. Log it in full, say
                // something plain out loud.
                res.mediators = new List<MediatorInfo>();
                res.slots = new List<SlotInfo>();
                res.mediatorCount = 0;
                res.slotCount = 0;
                res.isWithinBusinessHours = true;
                res.isSuccess = false;
                res.message = MSG_FAILED;
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
        AgentforceLogger.log(LOG, 'REQUEST #' + index,
            'slotIntervalMinutes=' + AgentforceLogger.show(req.slotIntervalMinutes) +
            ' minLeadMinutes=' + AgentforceLogger.show(req.minLeadMinutes));
    }

    /**
     * True when site visits run on this date.
     *
     * The weekday is read off a Datetime built at NOON in BUSINESS_TZ rather
     * than off Date methods, which resolve against the running user's timezone.
     * A guest user in another timezone has to get the same answer as a user in
     * India, and noon is far enough from either midnight that no offset can
     * push the reading onto the neighbouring day.
     */
    private static Boolean isWorkingDay(Date d) {
        Datetime noon = businessDatetime(d, 12 * 60);
        String dayName = noon.format('EEEE', BUSINESS_TZ).toLowerCase();
        return !CLOSED_DAYS.contains(dayName);
    }

    /** Builds the instant for a wall-clock minute-of-day on a date in BUSINESS_TZ. */
    private static Datetime businessDatetime(Date d, Integer minuteOfDay) {
        Datetime wallClock = Datetime.newInstanceGmt(
            d.year(), d.month(), d.day(), minuteOfDay / 60, Math.mod(minuteOfDay, 60), 0
        );
        Integer offsetMillis = TimeZone.getTimeZone(BUSINESS_TZ).getOffset(wallClock);
        return wallClock.addSeconds(-offsetMillis / 1000);
    }

    /** The calendar date an instant falls on in BUSINESS_TZ. */
    private static Date businessDate(Datetime value) {
        return Date.valueOf(value.format('yyyy-MM-dd', BUSINESS_TZ));
    }

    /** Minutes past midnight an instant reads as in BUSINESS_TZ. */
    private static Integer businessMinuteOfDay(Datetime value) {
        return Integer.valueOf(value.format('H', BUSINESS_TZ)) * 60 +
               Integer.valueOf(value.format('m', BUSINESS_TZ));
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

        // Duration: an explicit end wins, then a duration, then the default.
        Integer dur;
        Datetime slotEnd = resolveEnd(req);
        if (slotEnd != null && slotEnd > slotStart) {
            dur = Integer.valueOf((slotEnd.getTime() - slotStart.getTime()) / 60000);
        } else if (req.durationMinutes != null && req.durationMinutes > 0) {
            dur = req.durationMinutes;
        } else {
            dur = DEFAULT_DURATION;
        }
        AgentforceLogger.log(LOG, 'FIND', 'duration=' + dur + ' minute(s)');

        Map<Id, Contact> mediators = AgentforceDataService.mediatorsForProperty(propertyId);
        AgentforceLogger.log(LOG, 'FIND', 'mediators mapped to this property: ' + mediators.size() +
            ' ' + mediators.keySet());
        if (mediators.isEmpty()) {
            AgentforceLogger.log(LOG, 'FIND',
                'STOP: nothing in Mediator_Property__c links a mediator to ' + propertyId);
            return MSG_NO_MEDIATOR;
        }

        // This date only. When the day yields nothing the agent asks the
        // visitor for a different date rather than silently sliding forward.
        Date reqDate = businessDate(slotStart);
        Boolean working = isWorkingDay(reqDate);
        AgentforceLogger.log(LOG, 'FIND', 'reqDate=' + reqDate + ' workingDay=' + working +
            ' window=' + asClock(OPEN_MINUTES) + '-' + asClock(CLOSE_MINUTES) + ' ' + BUSINESS_TZ);

        if (!working) {
            res.isWithinBusinessHours = false;
            res.nextOpenText = nextOpenTextFrom(slotStart, dur);
            AgentforceLogger.log(LOG, 'FIND', 'STOP: closed day, nextOpenText=' +
                AgentforceLogger.show(res.nextOpenText));
            return MSG_CLOSED_DAY;
        }

        Integer requestedMinute = businessMinuteOfDay(slotStart);
        Boolean insideHours = requestedMinute >= OPEN_MINUTES && requestedMinute <= CLOSE_MINUTES;
        if (!insideHours) {
            // Still search the day: the visitor asked for a real working day,
            // just at an hour we do not run, so offer the window we do.
            res.isWithinBusinessHours = false;
            res.nextOpenText = nextOpenTextFrom(slotStart, dur);
            AgentforceLogger.log(LOG, 'FIND', 'requested ' + asClock(requestedMinute) +
                ' is outside visiting hours, still searching that day; nextOpenText=' +
                AgentforceLogger.show(res.nextOpenText));
        }

        Integer interval = (req.slotIntervalMinutes != null && req.slotIntervalMinutes > 0)
            ? req.slotIntervalMinutes : SLOT_INTERVAL;
        Integer lead = (req.minLeadMinutes != null && req.minLeadMinutes >= 0)
            ? req.minLeadMinutes : MIN_LEAD_MINUTES;
        Datetime earliestAllowed = Datetime.now().addMinutes(lead);
        AgentforceLogger.log(LOG, 'FIND', 'interval=' + interval + ' lead=' + lead +
            ' earliestAllowed=' + AgentforceLogger.utc(earliestAllowed));

        List<Datetime> candidates = buildCandidates(reqDate, dur, interval, earliestAllowed);
        AgentforceLogger.log(LOG, 'FIND', 'candidate starts built: ' + candidates.size());

        // One query for the whole day, rather than one per candidate.
        Datetime dayStart = businessDatetime(reqDate, OPEN_MINUTES);
        Datetime dayEnd = businessDatetime(reqDate, CLOSE_MINUTES);
        Map<Id, List<ServiceAppointment>> byMediator =
            AgentforceDataService.appointmentsForMediators(mediators.keySet(), dayStart, dayEnd);
        Integer apptCount = 0;
        for (List<ServiceAppointment> booked : byMediator.values()) {
            apptCount += booked.size();
        }
        AgentforceLogger.log(LOG, 'FIND', 'appointments loaded for that day: ' + apptCount);

        // One best slot per mediator: the free candidate nearest the requested
        // time, later winning a tie so a visitor is nudged forward not back.
        List<Candidate> best = new List<Candidate>();
        for (Id mediatorId : mediators.keySet()) {
            Contact mediator = mediators.get(mediatorId);
            List<ServiceAppointment> booked = byMediator.containsKey(mediatorId)
                ? byMediator.get(mediatorId) : new List<ServiceAppointment>();

            Datetime chosen = null;
            Long chosenDelta = null;
            Integer freeCount = 0;
            for (Datetime candidate : candidates) {
                if (overlapsAny(candidate, candidate.addMinutes(dur), booked)) {
                    continue;
                }
                freeCount++;
                Long delta = Math.abs(candidate.getTime() - slotStart.getTime()) / 60000;
                if (chosen == null || delta < chosenDelta ||
                    (delta == chosenDelta && candidate > chosen)) {
                    chosen = candidate;
                    chosenDelta = delta;
                }
            }
            AgentforceLogger.log(LOG, 'FIND', 'mediator ' + mediatorId + ' ' + mediator.Name +
                ': free candidates=' + freeCount + ' chosen=' +
                (chosen == null ? '<none>' : AgentforceDataService.formatBusinessTimeForRoundTrip(chosen)));
            if (chosen != null) {
                best.add(new Candidate(mediatorId, mediator, chosen, chosenDelta));
            }
        }

        if (best.isEmpty()) {
            AgentforceLogger.log(LOG, 'FIND', 'no mediator had a free candidate on ' + reqDate);
            return MSG_NONE_FREE;
        }

        // Nearest to the requested time first, mediator name breaking ties so
        // the same request twice returns the same three mediators.
        candidateSortBy = 'DISTANCE';
        best.sort();
        List<Candidate> chosenSlots = new List<Candidate>();
        for (Candidate c : best) {
            if (chosenSlots.size() >= MAX_SLOTS) {
                break;
            }
            chosenSlots.add(c);
        }

        // Presented in the order the day runs, not in ranking order.
        candidateSortBy = 'START';
        chosenSlots.sort();

        for (Candidate c : chosenSlots) {
            res.slots.add(c.toSlotInfo(dur));
            res.mediators.add(new MediatorInfo(c.mediator));
        }
        res.slotCount = res.slots.size();
        res.mediatorCount = res.mediators.size();

        assertShape(res);

        return insideHours ? MSG_SLOTS_INSIDE : MSG_SLOTS_OUTSIDE;
    }

    /**
     * Every start inside that day's window where a full visit still fits and
     * that is far enough ahead of now. Hard capped, so no input can spin.
     */
    private static List<Datetime> buildCandidates(
        Date reqDate, Integer dur, Integer interval, Datetime earliestAllowed
    ) {
        List<Datetime> candidates = new List<Datetime>();
        Integer minute = OPEN_MINUTES;
        Integer guard = 0;
        while (minute + dur <= CLOSE_MINUTES && guard < MAX_CANDIDATES) {
            guard++;
            Datetime candidate = businessDatetime(reqDate, minute);
            if (candidate >= earliestAllowed) {
                candidates.add(candidate);
            }
            minute += interval;
        }
        return candidates;
    }

    private static Boolean overlapsAny(
        Datetime candidateStart, Datetime candidateEnd, List<ServiceAppointment> booked
    ) {
        for (ServiceAppointment sa : booked) {
            if (sa.SchedStartTime == null || sa.SchedEndTime == null) {
                continue;
            }
            if (sa.SchedStartTime < candidateEnd && sa.SchedEndTime > candidateStart) {
                return true;
            }
        }
        return false;
    }

    /**
     * The contract the agent config depends on: at most three slots, one per
     * mediator, and the mediator list mirroring the slot list.
     */
    private static void assertShape(MediatorSearchResult res) {
        Assert.isTrue(res.slots.size() <= MAX_SLOTS,
            'Returned more than ' + MAX_SLOTS + ' slots: ' + res.slots.size());
        Set<String> seen = new Set<String>();
        for (SlotInfo slot : res.slots) {
            Assert.isTrue(seen.add(slot.mediatorId),
                'Returned two slots for the same mediator: ' + slot.mediatorId);
        }
        Assert.areEqual(res.slots.size(), res.mediatorCount,
            'mediatorCount does not match the number of slots');
    }

    /**
     * The next date a whole visit still fits inside visiting hours, as text a
     * visitor can act on. Today counts only for the part of the window still
     * ahead. Returns null rather than throwing when nothing fits in range.
     */
    @TestVisible
    private static String nextOpenTextFrom(Datetime fromMoment, Integer dur) {
        try {
            Integer length = (dur == null || dur <= 0) ? DEFAULT_DURATION : dur;
            Date scan = businessDate(fromMoment);
            for (Integer offset = 0; offset <= LOOKAHEAD_DAYS; offset++) {
                Date day = scan.addDays(offset);
                if (!isWorkingDay(day)) {
                    continue;
                }
                Integer earliest = OPEN_MINUTES;
                if (offset == 0) {
                    Integer nowMinute = businessMinuteOfDay(fromMoment);
                    earliest = Math.max(OPEN_MINUTES, nowMinute);
                }
                if (earliest + length > CLOSE_MINUTES) {
                    continue;
                }
                Datetime noon = businessDatetime(day, 12 * 60);
                return noon.format('EEEE, d MMMM yyyy', BUSINESS_TZ) +
                    ', between ' + asClock(OPEN_MINUTES) + ' and ' + asClock(CLOSE_MINUTES);
            }
            return null;
        } catch (Exception e) {
            // Only ever decoration on a result that already stands without it.
            AgentforceLogger.logException(LOG, 'NEXT_OPEN', e);
            return null;
        }
    }

    private static String asClock(Integer minuteOfDay) {
        Integer hr = minuteOfDay / 60;
        Integer mi = Math.mod(minuteOfDay, 60);
        return (hr < 10 ? '0' : '') + hr + ':' + (mi < 10 ? '0' : '') + mi;
    }

    /**
     * Which order Candidate.compareTo sorts in. It lives out here because
     * Apex forbids static members on an inner class, and Comparable gives
     * compareTo no room for an argument. Each sort runs to completion before
     * the next order is set.
     */
    private static String candidateSortBy = 'DISTANCE';

    /** One mediator's best slot, sortable by either ranking or clock order. */
    private class Candidate implements Comparable {
        private Id mediatorId;
        private Contact mediator;
        private Datetime slotStart;
        private Long distance;

        private Candidate(Id mediatorId, Contact mediator, Datetime slotStart, Long distance) {
            this.mediatorId = mediatorId;
            this.mediator = mediator;
            this.slotStart = slotStart;
            this.distance = distance;
        }

        public Integer compareTo(Object other) {
            Candidate that = (Candidate) other;
            Integer primary;
            if (candidateSortBy == 'START') {
                primary = this.slotStart < that.slotStart ? -1 : (this.slotStart > that.slotStart ? 1 : 0);
            } else {
                primary = this.distance < that.distance ? -1 : (this.distance > that.distance ? 1 : 0);
            }
            if (primary != 0) {
                return primary;
            }
            // Name last in both orders, so repeat requests are stable.
            String a = this.mediator.Name == null ? '' : this.mediator.Name;
            String b = that.mediator.Name == null ? '' : that.mediator.Name;
            return a.compareTo(b);
        }

        private SlotInfo toSlotInfo(Integer dur) {
            SlotInfo slot = new SlotInfo();
            slot.mediatorId = this.mediatorId;
            slot.mediatorName = this.mediator.Name;
            // Round-trip form: booking passes startTimeText back verbatim.
            slot.startTimeText = AgentforceDataService.formatBusinessTimeForRoundTrip(this.slotStart);
            slot.endTimeText =
                AgentforceDataService.formatBusinessTimeForRoundTrip(this.slotStart.addMinutes(dur));
            slot.displayText = this.mediator.Name + ' - ' +
                this.slotStart.format('EEEE, d MMMM yyyy, h:mm a', BUSINESS_TZ);
            return slot;
        }
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

        @InvocableVariable(label='Slot Interval (Minutes)'
            description='Step size of candidate times inside visiting hours. Blank uses the default.')
        public Integer slotIntervalMinutes;

        @InvocableVariable(label='Minimum Lead (Minutes)'
            description='How far ahead of now a slot must start. Blank uses the default.')
        public Integer minLeadMinutes;
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

        @InvocableVariable(label='Within Business Hours')
        public Boolean isWithinBusinessHours;

        @InvocableVariable(label='Next Available Window')
        public String nextOpenText;

        @InvocableVariable(label='Slot Count')
        public Integer slotCount;

        @InvocableVariable(label='Slots')
        public List<SlotInfo> slots;
    }

    public class SlotInfo {
        @InvocableVariable(label='Mediator Id')
        public String mediatorId;

        @InvocableVariable(label='Mediator Name')
        public String mediatorName;

        @InvocableVariable(label='Start Time (IST Text)')
        public String startTimeText;

        @InvocableVariable(label='End Time (IST Text)')
        public String endTimeText;

        @InvocableVariable(label='Display Text')
        public String displayText;
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
