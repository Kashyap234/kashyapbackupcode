/**
 * @description Trigger on Child__c to schedule global matching batch
 */
trigger ChildGlobalMatchingTrigger on Child__c (after insert, after update, after delete) {
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            GlobalMatchingTriggerHandler.handleChildChanges(
                Trigger.new, 
                null, 
                'INSERT'
            );
        } else if (Trigger.isUpdate) {
            GlobalMatchingTriggerHandler.handleChildChanges(
                Trigger.new, 
                Trigger.oldMap, 
                'UPDATE'
            );
        } else if (Trigger.isDelete) {
            GlobalMatchingTriggerHandler.handleChildChanges(
                Trigger.old, 
                Trigger.oldMap, 
                'DELETE'
            );
        }
    }
}
