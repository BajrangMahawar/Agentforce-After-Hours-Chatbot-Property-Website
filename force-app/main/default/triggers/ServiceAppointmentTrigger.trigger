/**
 * One trigger per object, all logic in the handler.
 */
trigger ServiceAppointmentTrigger on ServiceAppointment (after insert, after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ServiceAppointmentTriggerHandler.createMediatorTasks(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        // A mediator added after the fact still has to get a task, and a
        // re-parented appointment has to carry its Lead down to the tasks.
        ServiceAppointmentTriggerHandler.syncOnUpdate(Trigger.new, Trigger.oldMap);
    }
}
