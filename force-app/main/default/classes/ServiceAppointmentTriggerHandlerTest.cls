@isTest
private class ServiceAppointmentTriggerHandlerTest {
    private static Account firm;
    private static Property__c property;
    private static Contact mediator;
    private static Lead visitor;

    private static void makeData() {
        firm = new Account(Name = 'Test Mediator Network');
        insert firm;

        property = new Property__c(
            Name = 'Test Tower', City__c = 'Delhi', Address__c = 'Barakhamba Road, New Delhi',
            Status__c = 'Ready to Move'
        );
        insert property;

        mediator = new Contact(AccountId = firm.Id, FirstName = 'Asha', LastName = 'Verma',
                               MobilePhone = '+91-90000-00001', Email = 'asha@example.com');
        insert mediator;

        // ServiceAppointment requires a parent record in this org.
        visitor = new Lead(LastName = 'Visitor', Company = 'Website Enquiry', Email = 'visitor@example.com');
        insert visitor;
    }

    private static ServiceAppointment newAppointment(Id mediatorId) {
        Datetime start = Datetime.newInstanceGmt(2027, 2, 3, 11, 0, 0);
        return new ServiceAppointment(
            ParentRecordId = visitor.Id,
            Property__c = property.Id,
            Mediator__c = mediatorId,
            Subject = 'Site visit - Test Tower',
            Status = 'Scheduled',
            SchedStartTime = start,
            SchedEndTime = start.addHours(1),
            Email = 'visitor@example.com',
            Phone = '+91-98000-00000'
        );
    }

    @isTest
    static void createsATaskForTheMediator() {
        makeData();

        Test.startTest();
        ServiceAppointment sa = newAppointment(mediator.Id);
        insert sa;
        Test.stopTest();

        List<Task> tasks = [
            SELECT Subject, OwnerId, WhoId, WhatId, Status, Priority, ActivityDate, Description
            FROM Task WHERE WhatId = :sa.Id
        ];
        Assert.areEqual(1, tasks.size(), 'One task per new appointment');

        Task t = tasks[0];
        Assert.areEqual('Site visit - Test Tower', t.Subject, 'Subject names the property');
        Assert.areEqual(mediator.Id, t.WhoId, 'Task is against the mediator who does the visit');
        Assert.areEqual(sa.Id, t.WhatId, 'Task is related to the appointment');
        Assert.areEqual('Not Started', t.Status, 'New tasks start open');
        Assert.areEqual(Date.newInstance(2027, 2, 3), t.ActivityDate, 'Due on the day of the visit');
        Assert.isTrue(t.Description.contains('visitor@example.com'), 'Visitor email is carried over');
        Assert.isTrue(t.Description.contains('Asha Verma'), 'Mediator is named in the body');

        Contact owner = [SELECT OwnerId FROM Contact WHERE Id = :mediator.Id];
        Assert.areEqual(owner.OwnerId, t.OwnerId, 'Task lands with the user who owns the mediator');
    }

    @isTest
    static void linksTheTaskToTheAppointmentAndTheLead() {
        makeData();

        Test.startTest();
        ServiceAppointment sa = newAppointment(mediator.Id);
        sa.Lead__c = visitor.Id;
        insert sa;
        Test.stopTest();

        Task t = [SELECT WhatId, WhoId FROM Task WHERE WhatId = :sa.Id];
        Assert.areEqual(sa.Id, t.WhatId, 'Task points back at its appointment');
        Assert.areEqual(mediator.Id, t.WhoId, 'Task names the mediator doing the work');

        // The platform refuses a Lead in WhoId next to a WhatId, so the lead
        // and the property are both read back through the appointment.
        ServiceAppointment linked = [
            SELECT Lead__c, Property__c FROM ServiceAppointment WHERE Id = :sa.Id
        ];
        Assert.areEqual(visitor.Id, linked.Lead__c, 'the lead is one hop away');
        Assert.areEqual(property.Id, linked.Property__c, 'and so is the property');
    }

    @isTest
    static void fillsLeadFromTheParentRecordWhenTheLookupIsBlank() {
        makeData();

        Test.startTest();
        // Booked by hand from the layout: only ParentRecordId is set.
        ServiceAppointment sa = newAppointment(mediator.Id);
        insert sa;
        Test.stopTest();

        Assert.areEqual(
            visitor.Id,
            [SELECT Lead__c FROM ServiceAppointment WHERE Id = :sa.Id].Lead__c,
            'Lead__c is derived from ParentRecordId'
        );
        Assert.areEqual(
            1, [SELECT COUNT() FROM Task WHERE WhatId = :sa.Id],
            'and the appointment carrying it has its task'
        );
    }

    @isTest
    static void oneLeadCarriesManyAppointmentsEachWithItsOwnTask() {
        makeData();

        List<ServiceAppointment> visits = new List<ServiceAppointment>();
        for (Integer i = 0; i < 3; i++) {
            ServiceAppointment sa = newAppointment(mediator.Id);
            sa.SchedStartTime = sa.SchedStartTime.addDays(i);
            sa.SchedEndTime = sa.SchedEndTime.addDays(i);
            sa.Lead__c = visitor.Id;
            visits.add(sa);
        }

        Test.startTest();
        insert visits;
        Test.stopTest();

        Assert.areEqual(
            3, [SELECT COUNT() FROM ServiceAppointment WHERE Lead__c = :visitor.Id],
            'The lead holds all three site visits'
        );
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Task WHERE WhatId IN
                (SELECT Id FROM ServiceAppointment WHERE Lead__c = :visitor.Id)],
            'and reaches a task for each of them through those visits'
        );
        for (ServiceAppointment sa : visits) {
            Assert.areEqual(
                1, [SELECT COUNT() FROM Task WHERE WhatId = :sa.Id],
                'each appointment owns its own task'
            );
        }
    }

    @isTest
    static void createsTheTaskWhenTheMediatorIsAddedLater() {
        makeData();

        ServiceAppointment sa = newAppointment(null);
        sa.Lead__c = visitor.Id;
        insert sa;
        Assert.areEqual(
            0, [SELECT COUNT() FROM Task WHERE WhatId = :sa.Id],
            'no mediator yet, so no task yet'
        );

        Test.startTest();
        update new ServiceAppointment(Id = sa.Id, Mediator__c = mediator.Id);
        Test.stopTest();

        Assert.areEqual(
            1, [SELECT COUNT() FROM Task WHERE WhatId = :sa.Id],
            'the task arrives with the mediator'
        );
    }

    @isTest
    static void doesNotDuplicateTheTaskOnLaterEdits() {
        makeData();

        ServiceAppointment sa = newAppointment(mediator.Id);
        sa.Lead__c = visitor.Id;
        insert sa;

        Test.startTest();
        update new ServiceAppointment(Id = sa.Id, Status = 'Dispatched');
        update new ServiceAppointment(Id = sa.Id, Subject = 'Site visit - Test Tower (rescheduled)');
        Test.stopTest();

        Assert.areEqual(
            1, [SELECT COUNT() FROM Task WHERE WhatId = :sa.Id],
            'still exactly one task'
        );
    }

    @isTest
    static void aLaterAttachedLeadIsReachableFromExistingTasks() {
        makeData();

        // Parented to something that is not a Lead, so nothing to back-fill.
        ServiceAppointment sa = newAppointment(mediator.Id);
        sa.ParentRecordId = firm.Id;
        insert sa;
        Assert.areEqual(
            1, [SELECT COUNT() FROM Task WHERE WhatId = :sa.Id],
            'the task exists even though no lead is attached yet'
        );

        Test.startTest();
        update new ServiceAppointment(Id = sa.Id, Lead__c = visitor.Id);
        Test.stopTest();

        // The task did not have to change: it points at the appointment, and
        // the appointment now points at the lead.
        Assert.areEqual(
            visitor.Id,
            [SELECT Lead__c FROM ServiceAppointment WHERE Id = :sa.Id].Lead__c,
            'the lead is now reachable from the task that already existed'
        );
        Assert.areEqual(
            1, [SELECT COUNT() FROM Task WHERE WhatId = :sa.Id],
            'and it was not duplicated on the way'
        );
    }

    @isTest
    static void skipsAppointmentsWithNoMediator() {
        makeData();

        Test.startTest();
        insert newAppointment(null);
        Test.stopTest();

        Assert.areEqual(
            0, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Site visit%'],
            'No mediator means there is nobody to follow up'
        );
    }

    @isTest
    static void handlesABulkInsert() {
        makeData();

        List<ServiceAppointment> batch = new List<ServiceAppointment>();
        for (Integer i = 0; i < 20; i++) {
            batch.add(newAppointment(mediator.Id));
        }

        Test.startTest();
        insert batch;
        Test.stopTest();

        Assert.areEqual(
            20, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Site visit%'],
            'One task each, no governor trouble'
        );
    }
}
