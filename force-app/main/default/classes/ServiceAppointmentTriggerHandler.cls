public without sharing class ServiceAppointmentTriggerHandler {
    private static final String TASK_SUBJECT_PREFIX = 'Site visit';

    private static final String LOG = 'TRIGGER';

    // backfillLeadFromParent updates ServiceAppointment from inside the
    // ServiceAppointment trigger, which re-enters after update.
    private static Boolean isRunning = false;

    private static void log(String step, String detail) {
        AgentforceLogger.log(LOG, step, detail);
    }

    public static void createMediatorTasks(List<ServiceAppointment> appointments) {
        log('ENTRY', 'appointments=' + (appointments == null ? 0 : appointments.size()));
        if (appointments == null || appointments.isEmpty()) {
            return;
        }

        if (isRunning) {
            log('ENTRY', 'STOP: re-entered by our own update, nothing to do');
            return;
        }
        isRunning = true;
        try {
            run(appointments);
        } finally {
            isRunning = false;
        }
    }

    /**
     * Keeps the chain intact when an appointment changes after it was booked:
     * a mediator filled in later still earns its task. A Lead attached later
     * needs no push down to the tasks, because they reference the appointment
     * and read the Lead back through it.
     */
    public static void syncOnUpdate(List<ServiceAppointment> appointments, Map<Id, ServiceAppointment> oldMap) {
        if (isRunning || appointments == null || appointments.isEmpty()) {
            return;
        }
        List<ServiceAppointment> needTasks = new List<ServiceAppointment>();
        for (ServiceAppointment sa : appointments) {
            ServiceAppointment prior = oldMap == null ? null : oldMap.get(sa.Id);
            Boolean mediatorArrived = sa.Mediator__c != null &&
                (prior == null || prior.Mediator__c != sa.Mediator__c);
            if (mediatorArrived) {
                needTasks.add(sa);
            }
        }
        log('UPDATE', 'appointments=' + appointments.size() +
            ' gained/changed a mediator=' + needTasks.size());

        isRunning = true;
        try {
            if (!needTasks.isEmpty()) {
                run(needTasks);
            }
        } finally {
            isRunning = false;
        }
    }

    private static void run(List<ServiceAppointment> appointments) {
        // An appointment booked by hand from the layout only carries
        // ParentRecordId, so Lead__c is filled in first and the rows are read
        // back to build tasks off values that are certain to be on the record.
        backfillLeadFromParent(appointments);

        List<ServiceAppointment> rows = [
            SELECT Id, AppointmentNumber, Mediator__c, Property__c, Lead__c,
                   ParentRecordId, SchedStartTime, SchedEndTime, Email, Phone
            FROM ServiceAppointment
            WHERE Id IN :appointments
        ];

        Set<Id> mediatorIds = new Set<Id>();
        Set<Id> propertyIds = new Set<Id>();
        for (ServiceAppointment sa : rows) {
            log('ENTRY', 'sa=' + sa.Id + ' Mediator__c=' + sa.Mediator__c +
                ' Property__c=' + sa.Property__c +
                ' Lead__c=' + sa.Lead__c +
                ' SchedStartTime=' + sa.SchedStartTime);
            if (sa.Mediator__c != null) {
                mediatorIds.add(sa.Mediator__c);
            }
            if (sa.Property__c != null) {
                propertyIds.add(sa.Property__c);
            }
        }
        if (mediatorIds.isEmpty()) {
            log('ENTRY', 'STOP: no appointment carried a Mediator__c, no tasks to create');
            return;
        }

        Map<Id, Contact> mediators = new Map<Id, Contact>([
            SELECT Id, Name, OwnerId, Email, Phone, MobilePhone
            FROM Contact WHERE Id IN :mediatorIds
        ]);
        Map<Id, Property__c> properties = new Map<Id, Property__c>([
            SELECT Id, Name, City__c, Address__c FROM Property__c WHERE Id IN :propertyIds
        ]);
        log('LOOKUP', 'mediators found=' + mediators.size() + '/' + mediatorIds.size() +
            ' properties found=' + properties.size() + '/' + propertyIds.size());

        // An update can re-enter this path, so an appointment that already
        // carries its site-visit task must not earn a duplicate.
        Set<Id> alreadyHaveTask = new Set<Id>();
        String subjectLike = TASK_SUBJECT_PREFIX + '%';
        for (Task existing : [
            SELECT WhatId FROM Task
            WHERE WhatId IN :rows AND Subject LIKE :subjectLike
        ]) {
            alreadyHaveTask.add(existing.WhatId);
        }
        log('BUILD', 'appointments that already have a site-visit task=' + alreadyHaveTask.size());

        List<Task> tasks = new List<Task>();
        for (ServiceAppointment sa : rows) {
            if (alreadyHaveTask.contains(sa.Id)) {
                log('BUILD', 'skipping ' + sa.Id + ': its site-visit task already exists');
                continue;
            }
            Contact mediator = mediators.get(sa.Mediator__c);
            if (mediator == null) {
                log('BUILD', 'skipping ' + sa.Id + ': mediator ' + sa.Mediator__c + ' not readable');
                continue;
            }
            Property__c property = properties.get(sa.Property__c);
            String propertyName = property == null ? 'the property' : property.Name;

            // Task takes no custom lookups, so the standard polymorphic
            // fields have to carry the chain. The platform refuses a Lead in
            // WhoId together with any WhatId ("cannot specify whatID with lead
            // whoID"), and WhatId is the more valuable of the two here: it
            // points at the appointment, which itself holds the Lead and the
            // Property, so the whole chain stays one hop away. WhoId therefore
            // names the mediator who has to make the call.
            tasks.add(new Task(
                OwnerId = mediator.OwnerId,
            WhoId = mediator.Id,
            WhatId = sa.Id,
            Subject = TASK_SUBJECT_PREFIX + ' - ' + propertyName,
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = sa.SchedStartTime == null ? Date.today() : sa.SchedStartTime.date(),
            Description = buildDescription(sa, mediator, property)
                ));
        }
        if (tasks.isEmpty()) {
            log('BUILD', 'STOP: no tasks were built');
            return;
        }

        log('INSERT', 'inserting ' + tasks.size() + ' mediator task(s)');
        Database.SaveResult[] results = Database.insert(tasks, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                log('INSERT', 'task created ' + results[i].getId() + ' for "' + tasks[i].Subject + '"');
            } else {
                log('INSERT', 'FAILED for "' + tasks[i].Subject + '": ' + results[i].getErrors());
                System.debug(LoggingLevel.ERROR,
                'Mediator task not created for "' + tasks[i].Subject + '": ' + results[i].getErrors());
            }
        }
        log('EXIT', 'done');
    }

    /**
     * ParentRecordId is polymorphic, so it only tells us about a Lead when it
     * actually points at one. Where it does and Lead__c is still blank, the
     * lookup is filled in so the whole chain hangs off one field.
     */
    private static void backfillLeadFromParent(List<ServiceAppointment> appointments) {
        List<ServiceAppointment> updates = new List<ServiceAppointment>();
        for (ServiceAppointment sa : appointments) {
            if (sa.Lead__c != null || sa.ParentRecordId == null) {
                continue;
            }
            if (sa.ParentRecordId.getSObjectType() != Lead.SObjectType) {
                continue;
            }
            updates.add(new ServiceAppointment(Id = sa.Id, Lead__c = sa.ParentRecordId));
        }
        if (updates.isEmpty()) {
            log('BACKFILL', 'no appointment needed Lead__c filled in from ParentRecordId');
            return;
        }
        log('BACKFILL', 'setting Lead__c from ParentRecordId on ' + updates.size() + ' appointment(s)');
        Database.SaveResult[] saved = Database.update(updates, false);
        for (Integer i = 0; i < saved.size(); i++) {
            if (!saved[i].isSuccess()) {
                log('BACKFILL', 'FAILED for ' + updates[i].Id + ': ' + saved[i].getErrors());
            }
        }
    }

    private static String buildDescription(ServiceAppointment sa, Contact mediator, Property__c property) {
        List<String> lines = new List<String>{
            'Site visit booked with ' + mediator.Name + '.',
            'Appointment: ' + (sa.AppointmentNumber == null ? String.valueOf(sa.Id) : sa.AppointmentNumber)
        };
        if (property != null) {
            lines.add('Property: ' + property.Name + (String.isBlank(property.City__c) ? '' : ', ' + property.City__c));
            if (String.isNotBlank(property.Address__c)) {
                lines.add('Address: ' + property.Address__c);
            }
        }
        if (sa.SchedStartTime != null) {
            // format() would render in whichever timezone the running user
            // carries; the visit is always an IST appointment.
            lines.add('When: ' + AgentforceDataService.formatBusinessTime(sa.SchedStartTime) + ' - ' +
                (sa.SchedEndTime == null
                    ? 'open ended'
                    : AgentforceDataService.formatBusinessTime(sa.SchedEndTime)));
        }
        if (String.isNotBlank(sa.Email)) {
            lines.add('Visitor email: ' + sa.Email);
        }
        if (String.isNotBlank(sa.Phone)) {
            lines.add('Visitor phone: ' + sa.Phone);
        }
        lines.add('Mediator contact: ' +
        String.join(new List<String>{
            String.isBlank(mediator.MobilePhone) ? '' : mediator.MobilePhone,
            String.isBlank(mediator.Phone) ? '' : mediator.Phone,
            String.isBlank(mediator.Email) ? '' : mediator.Email
        }, ' ').trim());
        return String.join(lines, '\n');
    }
}