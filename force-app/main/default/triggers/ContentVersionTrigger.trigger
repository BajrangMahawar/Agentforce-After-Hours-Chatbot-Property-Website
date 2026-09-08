trigger ContentVersionTrigger on ContentVersion (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        ContentVersionShareHandler.shareWithAgentUser(Trigger.new);
    }
}
