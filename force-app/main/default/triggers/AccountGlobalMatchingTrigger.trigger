/**
 * @description Trigger on Account (Family) to schedule global matching batch
 */
trigger AccountGlobalMatchingTrigger on Account (after insert, after update, after delete) {
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            GlobalMatchingTriggerHandler.handleAccountChanges(
                Trigger.new, 
                null, 
                'INSERT'
            );
        } else if (Trigger.isUpdate) {
            GlobalMatchingTriggerHandler.handleAccountChanges(
                Trigger.new, 
                Trigger.oldMap, 
                'UPDATE'
            );
        } else if (Trigger.isDelete) {
            GlobalMatchingTriggerHandler.handleAccountChanges(
                Trigger.old, 
                Trigger.oldMap, 
                'DELETE'
            );
        }
    }
}
