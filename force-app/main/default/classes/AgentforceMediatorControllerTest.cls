/**
 * Slot search behaviour.
 *
 * Every date here is a fixed literal, never Date.today(), so a test that
 * passes in September still passes in December. The dates are chosen far
 * enough in the future that the minimum-lead rule never trims a candidate:
 *
 *   2026-09-12 Saturday    2026-09-13 Sunday    2026-09-14 Monday
 */
@isTest
private class AgentforceMediatorControllerTest {
    // The working day every slot test runs against.
    private static final String MONDAY = '2026-09-14';
    private static final String SATURDAY = '2026-09-12';
    private static final String SUNDAY = '2026-09-13';

    private static Property__c property;

    private static Property__c makeProperty() {
        property = new Property__c(
            Name = 'Slot Test Tower',
            City__c = 'Pune',
            Status__c = 'Ready to Move',
            Configurations__c = '3 BHK',
            Price_Min__c = 10000000,
            Price_Max__c = 20000000
        );
        insert property;
        return property;
    }

    /** Creates `count` mediators, all mapped to the property, named A.. onward. */
    private static List<Contact> makeMediators(Integer count) {
        Account firm = new Account(Name = 'Slot Test Network');
        insert firm;

        List<Contact> mediators = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            mediators.add(new Contact(
                AccountId = firm.Id,
                FirstName = 'Med' + i,
                LastName = String.fromCharArray(new List<Integer>{ 65 + i }) + ' Mediator'
            ));
        }
        insert mediators;

        List<Mediator_Property__c> links = new List<Mediator_Property__c>();
        for (Contact c : mediators) {
            links.add(new Mediator_Property__c(Property__c = property.Id, Mediator__c = c.Id));
        }
        insert links;
        return mediators;
    }

    /**
     * Books a mediator for `minutes` starting at an IST wall clock.
     * ParentRecordId is the visitor lead, not the property; the property rides
     * on its own lookup, the same shape the booking action creates.
     */
    private static void book(Contact mediator, String istStart, Integer minutes) {
        Datetime start = AgentforceDataService.parseBusinessTime(istStart);
        // ServiceAppointment requires a Lead as its parent in this org.
        Lead visitor = new Lead(LastName = 'Visitor', Company = 'Website Enquiry');
        insert visitor;
        insert new ServiceAppointment(
            ParentRecordId = visitor.Id,
            Property__c = property.Id,
            Mediator__c = mediator.Id,
            Status = 'Scheduled',
            SchedStartTime = start,
            SchedEndTime = start.addMinutes(minutes)
        );
    }

    private static AgentforceMediatorController.MediatorSearchResult run(String istStart) {
        return run(istStart, null, null);
    }

    private static AgentforceMediatorController.MediatorSearchResult run(
        String istStart, Integer durationMinutes, Integer leadMinutes
    ) {
        AgentforceMediatorController.MediatorSearchRequest req =
            new AgentforceMediatorController.MediatorSearchRequest();
        req.propertyId = property.Id;
        req.startTimeText = istStart;
        req.durationMinutes = durationMinutes;
        // The fixture dates sit far in the future, so lead never bites; pinning
        // it to 0 keeps that true even if the constant changes later.
        req.minLeadMinutes = leadMinutes == null ? 0 : leadMinutes;

        Test.startTest();
        List<AgentforceMediatorController.MediatorSearchResult> results =
            AgentforceMediatorController.getMediator(
                new List<AgentforceMediatorController.MediatorSearchRequest>{ req }
            );
        Test.stopTest();
        Assert.areEqual(1, results.size(), 'One request should give one result');
        return results[0];
    }

    /** The IST wall clock a slot starts at, e.g. '15:00'. */
    private static String clockOf(AgentforceMediatorController.SlotInfo slot) {
        return slot.startTimeText.substring(11);
    }

    @isTest
    static void saturdayIsClosedAndPointsAtTheMonday() {
        makeProperty();
        makeMediators(2);

        AgentforceMediatorController.MediatorSearchResult res = run(SATURDAY + ' 15:00');

        Assert.isTrue(res.isSuccess, 'The action itself should succeed');
        Assert.isFalse(res.isWithinBusinessHours, 'Saturday is not a visiting day');
        Assert.areEqual(0, res.slotCount, 'No slots on a closed day');
        Assert.areEqual(0, res.slots.size(), 'No slots on a closed day');
        Assert.areEqual('Site visits do not run on that day.', res.message);

        Assert.isNotNull(res.nextOpenText, 'A closed day should still name the next open one');
        Assert.isTrue(res.nextOpenText.contains('Monday'),
            'Saturday should point at Monday but was: ' + res.nextOpenText);
        Assert.isTrue(res.nextOpenText.contains('14 September 2026'),
            'Should name the following Monday but was: ' + res.nextOpenText);
        Assert.isTrue(res.nextOpenText.contains('11:00'),
            'Should name the opening time but was: ' + res.nextOpenText);
        Assert.isTrue(res.nextOpenText.contains('18:00'),
            'Should name the closing time but was: ' + res.nextOpenText);
    }

    @isTest
    static void sundayIsClosedAndPointsAtTheMonday() {
        makeProperty();
        makeMediators(2);

        AgentforceMediatorController.MediatorSearchResult res = run(SUNDAY + ' 15:00');

        Assert.isFalse(res.isWithinBusinessHours, 'Sunday is not a visiting day');
        Assert.areEqual(0, res.slotCount, 'No slots on a closed day');
        Assert.areEqual(0, res.slots.size(), 'No slots on a closed day');
        Assert.areEqual('Site visits do not run on that day.', res.message);
        Assert.isNotNull(res.nextOpenText, 'A closed day should still name the next open one');
        Assert.isTrue(res.nextOpenText.contains('Monday'),
            'Sunday should point at Monday but was: ' + res.nextOpenText);
        Assert.isTrue(res.nextOpenText.contains('11:00') && res.nextOpenText.contains('18:00'),
            'Should name the window but was: ' + res.nextOpenText);
    }

    @isTest
    static void earlyMorningIsOutsideHoursButTheDayIsStillSearched() {
        makeProperty();
        makeMediators(2);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 09:00');

        Assert.isFalse(res.isWithinBusinessHours, '09:00 is before the window opens');
        Assert.isTrue(res.slotCount > 0, 'A working day should still offer slots');
        Assert.areEqual('11:00', clockOf(res.slots[0]),
            'The earliest offer should be the opening time');
        Assert.areEqual(
            'The requested time is outside site visit hours. Slots are available inside the visiting window that day.',
            res.message
        );
    }

    /**
     * 17:30 falls inside the window, so the request itself is in hours, but a
     * 60 minute visit starting there would run to 18:30. Nothing may be
     * offered at that time; the day's last usable start is 17:00.
     */
    @isTest
    static void aVisitThatWouldRunPastClosingIsNotOffered() {
        makeProperty();
        makeMediators(2);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 17:30', 60, 0);

        Assert.isTrue(res.slotCount > 0, 'Earlier starts that day still fit');
        for (AgentforceMediatorController.SlotInfo slot : res.slots) {
            Assert.isTrue(clockOf(slot) <= '17:00',
                'No slot may start late enough to end past closing: ' + slot.startTimeText);
            Datetime ends = AgentforceDataService.parseBusinessTime(slot.endTimeText);
            Assert.isTrue(ends <= AgentforceDataService.parseBusinessTime(MONDAY + ' 18:00'),
                'No visit may run past closing: ' + slot.endTimeText);
        }
    }

    @isTest
    static void aFreeMediatorIsOfferedTheRequestedTimeNotTheOpeningTime() {
        makeProperty();
        makeMediators(1);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');

        Assert.isTrue(res.isWithinBusinessHours, '15:00 is inside the window');
        Assert.areEqual(1, res.slotCount, 'One mediator gives one slot');
        Assert.areEqual('15:00', clockOf(res.slots[0]),
            'A wholly free mediator should be offered the time actually asked for');
        Assert.areEqual('Slots are available close to the requested time.', res.message);
    }

    @isTest
    static void aBusyMediatorIsOfferedTheNearestFreeTime() {
        makeProperty();
        List<Contact> mediators = makeMediators(1);
        // Free at 14:00 and 16:00, busy across 15:00. Both neighbours are 60
        // minutes away, and a tie resolves to the later one.
        book(mediators[0], MONDAY + ' 15:00', 60);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');

        Assert.areEqual(1, res.slotCount, 'The mediator is free elsewhere that day');
        Assert.areEqual('16:00', clockOf(res.slots[0]),
            'An equidistant tie should resolve to the later slot');
    }

    @isTest
    static void fiveFreeMediatorsGiveExactlyThreeDistinctSlots() {
        makeProperty();
        makeMediators(5);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');

        Assert.areEqual(3, res.slotCount, 'Never more than three slots');
        Assert.areEqual(3, res.slots.size(), 'Never more than three slots');
        Assert.areEqual(3, res.mediatorCount, 'mediatorCount should mirror the slots');

        Set<String> ids = new Set<String>();
        for (AgentforceMediatorController.SlotInfo slot : res.slots) {
            ids.add(slot.mediatorId);
        }
        Assert.areEqual(3, ids.size(), 'Each slot should come from a different mediator');
    }

    @isTest
    static void oneMediatorWithAWhollyFreeDayGivesOneSlotNotThree() {
        makeProperty();
        makeMediators(1);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');

        Assert.areEqual(1, res.slotCount,
            'A single mediator contributes one slot even with a whole day free');
        Assert.areEqual(1, res.mediatorCount, 'mediatorCount should mirror the slots');
    }

    @isTest
    static void aMediatorBookedAllDayIsExcludedButOthersRemain() {
        makeProperty();
        List<Contact> mediators = makeMediators(2);
        // 11:00 to 18:00 covers every hourly start on the grid.
        book(mediators[0], MONDAY + ' 11:00', 7 * 60);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');

        Assert.areEqual(1, res.slotCount, 'Only the free mediator should appear');
        Assert.areNotEqual(String.valueOf(mediators[0].Id), res.slots[0].mediatorId,
            'The fully booked mediator must not be offered');
    }

    @isTest
    static void everyMediatorBookedAllDayGivesAPlainMessage() {
        makeProperty();
        List<Contact> mediators = makeMediators(2);
        for (Contact c : mediators) {
            book(c, MONDAY + ' 11:00', 7 * 60);
        }

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');

        Assert.isTrue(res.isSuccess, 'A full day is a normal outcome, not a failure');
        Assert.areEqual(0, res.slotCount, 'Nobody is free');
        Assert.areEqual('No mediator has a free slot on that day.', res.message);
    }

    @isTest
    static void aPropertyWithNoMediatorFailsGracefully() {
        makeProperty();
        // Deliberately no Mediator_Property__c rows.

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');

        Assert.isTrue(res.isSuccess, 'An unmapped property is a normal outcome, not an exception');
        Assert.areEqual(0, res.slotCount, 'No mediators means no slots');
        Assert.areEqual(0, res.slots.size(), 'The slot list should be empty, not null');
        Assert.areEqual(0, res.mediatorCount, 'No mediators means no mediators');
        Assert.areEqual('No mediator is mapped to this property yet.', res.message);
    }

    @isTest
    static void startTimeTextRoundTripsBackToTheSameInstant() {
        makeProperty();
        makeMediators(1);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');
        Assert.areEqual(1, res.slotCount, 'Expected a slot to round trip');

        AgentforceMediatorController.SlotInfo slot = res.slots[0];
        Datetime reparsed = AgentforceDataService.parseBusinessTime(slot.startTimeText);
        Assert.isNotNull(reparsed,
            'Booking passes startTimeText back verbatim, so it must parse: ' + slot.startTimeText);
        Assert.areEqual(
            AgentforceDataService.parseBusinessTime(MONDAY + ' 15:00'),
            reparsed,
            'The round trip must land on the same instant'
        );

        Datetime reparsedEnd = AgentforceDataService.parseBusinessTime(slot.endTimeText);
        Assert.isNotNull(reparsedEnd, 'The end must round trip too: ' + slot.endTimeText);
        Assert.areEqual(reparsed.addMinutes(60), reparsedEnd, 'A default visit runs 60 minutes');
    }

    @isTest
    static void displayTextNamesTheMediatorAndTheSlot() {
        makeProperty();
        makeMediators(1);

        AgentforceMediatorController.MediatorSearchResult res = run(MONDAY + ' 15:00');
        String shown = res.slots[0].displayText;

        Assert.isTrue(shown.contains(res.slots[0].mediatorName),
            'Display text should name the mediator but was: ' + shown);
        Assert.isTrue(shown.contains('Monday, 14 September 2026'),
            'Display text should spell out the date but was: ' + shown);
        Assert.isTrue(shown.contains('3:00 PM'),
            'Display text should read as a 12 hour clock but was: ' + shown);
    }

    /**
     * The agent reads `message` out loud. A digit in it means an Id, a raw
     * time or a count of who was free leaked into something a visitor hears.
     */
    @isTest
    static void noMessageEverContainsADigit() {
        makeProperty();
        List<Contact> mediators = makeMediators(2);
        book(mediators[0], MONDAY + ' 11:00', 7 * 60);

        List<AgentforceMediatorController.MediatorSearchRequest> requests =
            new List<AgentforceMediatorController.MediatorSearchRequest>();
        for (String istStart : new List<String>{
            SATURDAY + ' 15:00',   // closed day
            SUNDAY + ' 15:00',     // closed day
            MONDAY + ' 09:00',     // outside hours, still searched
            MONDAY + ' 15:00'      // inside hours
        }) {
            AgentforceMediatorController.MediatorSearchRequest req =
                new AgentforceMediatorController.MediatorSearchRequest();
            req.propertyId = property.Id;
            req.startTimeText = istStart;
            req.minLeadMinutes = 0;
            requests.add(req);
        }

        Test.startTest();
        List<AgentforceMediatorController.MediatorSearchResult> results =
            AgentforceMediatorController.getMediator(requests);
        Test.stopTest();

        Assert.areEqual(requests.size(), results.size(), 'Every request should give a result');
        Pattern digit = Pattern.compile('[0-9]');
        for (AgentforceMediatorController.MediatorSearchResult res : results) {
            Assert.isFalse(digit.matcher(res.message).find(),
                'A visitor-facing message must carry no Id, time or count: ' + res.message);
        }
    }

    @isTest
    static void nothingIsReturnedForANullRequestList() {
        Test.startTest();
        List<AgentforceMediatorController.MediatorSearchResult> results =
            AgentforceMediatorController.getMediator(null);
        Test.stopTest();
        Assert.areEqual(0, results.size(), 'A null request list should return nothing, not throw');
    }
}
