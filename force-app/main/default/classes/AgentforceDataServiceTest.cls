@isTest
private class AgentforceDataServiceTest {
    private static Property__c property;
    private static Contact mediatorA;
    private static Contact mediatorB;
    
    private static void makeData() {
        Account firm = new Account(Name = 'Test Mediator Network');
        insert firm;
        
        property = new Property__c(
            Name = 'Test Tower', City__c = 'Delhi', Status__c = 'Ready to Move',
        Configurations__c = '3 BHK', Price_Min__c = 10000000, Price_Max__c = 20000000
            );
        insert property;
        
        mediatorA = new Contact(AccountId = firm.Id, FirstName = 'Asha', LastName = 'Verma', Phone = '011-1111');
        mediatorB = new Contact(AccountId = firm.Id, FirstName = 'Bharat', LastName = 'Singh', MobilePhone = '+91-90000');
        insert new List<Contact>{ mediatorA, mediatorB };
        
        insert new List<Mediator_Property__c>{
            new Mediator_Property__c(Property__c = property.Id, Mediator__c = mediatorA.Id),
            new Mediator_Property__c(Property__c = property.Id, Mediator__c = mediatorB.Id)
        };
    }
    
    private static User restrictedUser() {
        User u = new User(
            Alias = 'agtst',
        Email = 'agent.test@example.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'AgentTest',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        Username = 'agent.test.' + DateTime.now().getTime() + '@example.com.invalid'
            );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet
                                     WHERE Name IN ('Agentforce_Property_Data', 'Agentforce_Site_Visit_Scheduling')]) {
                assignments.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert assignments;
        }
        return u;
    }
    
    private static User userInTimeZone(String timeZoneSidKey) {
        User u = new User(
            Alias = 'agtz',
        Email = 'agent.tz@example.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'AgentTz',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
        TimeZoneSidKey = timeZoneSidKey,
        Username = 'agent.tz.' + DateTime.now().getTime() + '@example.com.invalid'
            );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [SELECT Id FROM PermissionSet
                                     WHERE Name IN ('Agentforce_Property_Data', 'Agentforce_Site_Visit_Scheduling')]) {
                assignments.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert assignments;
        }
        return u;
    }
    
    @isTest
    static void mediatorsStayReadableForAUserWhoOwnsNothing() {
        makeData();
        User agent = restrictedUser();
        
        Integer visibleToAgent;
        System.runAs(agent) {
            visibleToAgent = AgentforceDataService.mediatorsForProperty(property.Id).size();
        }
        
        Assert.areEqual(
            2, visibleToAgent,
        'A Contact with no Account is private and takes its junction rows down with it - ' +
            'mediators must hang off an Account'
            );
    }
    
    @isTest
    static void availabilitySurvivesNoAccessToTheMediatorContacts() {
        makeData();
        User agent = restrictedUser();
        
        Test.startTest();
        List<AgentforceMediatorController.MediatorSearchResult> results;
        System.runAs(agent) {
            AgentforceMediatorController.MediatorSearchRequest req =
                new AgentforceMediatorController.MediatorSearchRequest();
            req.propertyId = property.Id;
            req.startTime = Datetime.newInstanceGmt(2027, 1, 4, 11, 0, 0);
            results = AgentforceMediatorController.getMediator(
            new List<AgentforceMediatorController.MediatorSearchRequest>{ req }
            );
        }
        Test.stopTest();
        
        Assert.isTrue(results[0].isSuccess, 'The action should not error for a restricted user');
        Assert.areEqual(
            2, results[0].mediatorCount,
        'Both mediators must come back even though the running user cannot see their Contacts'
            );
    }
    
    @isTest
    static void propertyDetailListsMediatorsForARestrictedUser() {
        makeData();
        User agent = restrictedUser();
        
        Test.startTest();
        List<AgentforcePropertyDetailController.PropertyDetailResult> results;
        System.runAs(agent) {
            AgentforcePropertyDetailController.PropertyDetailRequest req =
                new AgentforcePropertyDetailController.PropertyDetailRequest();
            req.propertyName = 'Test Tower';
            results = AgentforcePropertyDetailController.getPropertyDetail(
            new List<AgentforcePropertyDetailController.PropertyDetailRequest>{ req }
            );
        }
        Test.stopTest();
        
        Assert.isTrue(results[0].isFound, 'The property should be found');
        Assert.areEqual(2, results[0].mediatorCount, 'Both mediators belong on the detail response');
    }
    
    @isTest
    static void bookingResolvesAMediatorTheUserCannotRead() {
        makeData();
        User agent = restrictedUser();
        
        Test.startTest();
        List<AgentforceSiteVisitController.SiteVisitResult> results;
        System.runAs(agent) {
            AgentforceSiteVisitController.SiteVisitRequest req =
                new AgentforceSiteVisitController.SiteVisitRequest();
            req.propertyId = property.Id;
            req.mediatorName = 'Asha Verma';
            req.customerEmail = 'visitor@example.com';
            req.customerPhone = '+91-98000-00000';
            req.startTime = Datetime.newInstanceGmt(2027, 1, 4, 11, 0, 0);
            results = AgentforceSiteVisitController.createSiteVisit(
            new List<AgentforceSiteVisitController.SiteVisitRequest>{ req }
            );
        }
        Test.stopTest();
        
        Assert.areNotEqual(
            'No matching mediator found, so nothing was booked.', results[0].message,
        'The mediator must resolve by name even without read access to the Contact'
            );
    }

    @isTest
    static void istTextBooksTheStatedClockTimeForANonIstUser() {
        makeData();
        User pacific = userInTimeZone('America/Los_Angeles');
        List<AgentforceSiteVisitController.SiteVisitResult> results;

        Test.startTest();
        System.runAs(pacific) {
            AgentforceSiteVisitController.SiteVisitRequest req =
                new AgentforceSiteVisitController.SiteVisitRequest();
            req.propertyId = property.Id;
            req.mediatorName = 'Asha Verma';
            req.customerEmail = 'pacific.visitor@example.com';
            req.startTimeText = '2027-03-09 15:00';
            results = AgentforceSiteVisitController.createSiteVisit(
                new List<AgentforceSiteVisitController.SiteVisitRequest>{ req }
            );
        }
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'The booking should succeed: ' + results[0].message);

        ServiceAppointment sa = [
            SELECT SchedStartTime, SchedEndTime FROM ServiceAppointment
            WHERE Id = :results[0].serviceAppointmentId LIMIT 1
        ];
        // 3 PM IST is 09:30 UTC no matter who submitted the request.
        Assert.areEqual(
            Datetime.newInstanceGmt(2027, 3, 9, 9, 30, 0), sa.SchedStartTime,
            '3 PM IST text must store 09:30 UTC regardless of the running user timezone'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2027, 3, 9, 10, 30, 0), sa.SchedEndTime,
            'The default 60 minute slot must run to 4 PM IST'
        );
    }

    @isTest
    static void istTextGivesTheSameInstantForAnIstUser() {
        makeData();
        User ist = restrictedUser();
        List<AgentforceSiteVisitController.SiteVisitResult> results;

        Test.startTest();
        System.runAs(ist) {
            AgentforceSiteVisitController.SiteVisitRequest req =
                new AgentforceSiteVisitController.SiteVisitRequest();
            req.propertyId = property.Id;
            req.mediatorName = 'Asha Verma';
            req.customerEmail = 'ist.visitor@example.com';
            req.startTimeText = '2027-03-09 15:00';
            results = AgentforceSiteVisitController.createSiteVisit(
                new List<AgentforceSiteVisitController.SiteVisitRequest>{ req }
            );
        }
        Test.stopTest();

        ServiceAppointment sa = [
            SELECT SchedStartTime FROM ServiceAppointment
            WHERE Id = :results[0].serviceAppointmentId LIMIT 1
        ];
        Assert.areEqual(
            Datetime.newInstanceGmt(2027, 3, 9, 9, 30, 0), sa.SchedStartTime,
            'Both timezones must agree on the instant'
        );
    }

    @isTest
    static void istTextWinsOverTheDatetimeField() {
        makeData();
        User pacific = userInTimeZone('America/Los_Angeles');
        List<AgentforceSiteVisitController.SiteVisitResult> results;

        Test.startTest();
        System.runAs(pacific) {
            AgentforceSiteVisitController.SiteVisitRequest req =
                new AgentforceSiteVisitController.SiteVisitRequest();
            req.propertyId = property.Id;
            req.mediatorName = 'Asha Verma';
            req.customerEmail = 'both.fields@example.com';
            req.startTimeText = '2027-03-09 15:00';
            // A conflicting instant, the shape that produced the wrong booking.
            req.startTime = Datetime.newInstanceGmt(2027, 3, 8, 21, 0, 0);
            results = AgentforceSiteVisitController.createSiteVisit(
                new List<AgentforceSiteVisitController.SiteVisitRequest>{ req }
            );
        }
        Test.stopTest();

        ServiceAppointment sa = [
            SELECT SchedStartTime FROM ServiceAppointment
            WHERE Id = :results[0].serviceAppointmentId LIMIT 1
        ];
        Assert.areEqual(
            Datetime.newInstanceGmt(2027, 3, 9, 9, 30, 0), sa.SchedStartTime,
            'The IST text must take precedence over the Datetime field'
        );
    }

    @isTest
    static void theDatetimeFieldStillWorksWhenNoTextIsGiven() {
        makeData();
        User ist = restrictedUser();
        List<AgentforceSiteVisitController.SiteVisitResult> results;

        Test.startTest();
        System.runAs(ist) {
            AgentforceSiteVisitController.SiteVisitRequest req =
                new AgentforceSiteVisitController.SiteVisitRequest();
            req.propertyId = property.Id;
            req.mediatorName = 'Asha Verma';
            req.customerEmail = 'fallback@example.com';
            req.startTime = Datetime.newInstanceGmt(2027, 3, 9, 9, 30, 0);
            results = AgentforceSiteVisitController.createSiteVisit(
                new List<AgentforceSiteVisitController.SiteVisitRequest>{ req }
            );
        }
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess, 'The fallback path must still book: ' + results[0].message);
        ServiceAppointment sa = [
            SELECT SchedStartTime FROM ServiceAppointment
            WHERE Id = :results[0].serviceAppointmentId LIMIT 1
        ];
        Assert.areEqual(
            Datetime.newInstanceGmt(2027, 3, 9, 9, 30, 0), sa.SchedStartTime,
            'An absolute instant must be stored untouched'
        );
    }

    @isTest
    static void parseBusinessTimeAcceptsTheShapesTheAgentSends() {
        Datetime expected = Datetime.newInstanceGmt(2027, 3, 9, 9, 30, 0);
        Assert.areEqual(expected, AgentforceDataService.parseBusinessTime('2027-03-09 15:00'), 'space separator');
        Assert.areEqual(expected, AgentforceDataService.parseBusinessTime('2027-03-09T15:00'), 'T separator');
        Assert.areEqual(expected, AgentforceDataService.parseBusinessTime('2027-03-09 15:00:00'), 'with seconds');
        Assert.areEqual(expected, AgentforceDataService.parseBusinessTime('  2027-03-09 15:00  '), 'padded');
    }

    @isTest
    static void parseBusinessTimeRejectsWhatItCannotTrust() {
        Assert.isNull(AgentforceDataService.parseBusinessTime(null), 'null');
        Assert.isNull(AgentforceDataService.parseBusinessTime('   '), 'blank');
        Assert.isNull(AgentforceDataService.parseBusinessTime('9 March 2027 3pm'), 'prose');
        Assert.isNull(AgentforceDataService.parseBusinessTime('2027-03-09'), 'date only');
        Assert.isNull(AgentforceDataService.parseBusinessTime('2027-13-09 15:00'), 'month 13');
        Assert.isNull(AgentforceDataService.parseBusinessTime('2027-03-09 25:00'), 'hour 25');
    }

    @isTest
    static void formatBusinessTimeReadsBackInIst() {
        String shown = AgentforceDataService.formatBusinessTime(
            Datetime.newInstanceGmt(2027, 3, 9, 9, 30, 0)
        );
        Assert.isTrue(shown.contains('3:00 PM'), 'Should read back as 3 PM IST but was: ' + shown);
        Assert.isTrue(shown.endsWith('IST'), 'Should be labelled IST but was: ' + shown);
    }
}
