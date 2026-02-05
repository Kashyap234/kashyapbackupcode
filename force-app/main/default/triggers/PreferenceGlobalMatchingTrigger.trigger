/**
 * @description Trigger on Preference__c to schedule global matching batch
 */
trigger PreferenceGlobalMatchingTrigger on Preference__c (after insert, after update, after delete) {
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            GlobalMatchingTriggerHandler.handlePreferenceChanges(
                Trigger.new, 
                null, 
                'INSERT'
            );
        } else if (Trigger.isUpdate) {
            GlobalMatchingTriggerHandler.handlePreferenceChanges(
                Trigger.new, 
                Trigger.oldMap, 
                'UPDATE'
            );
        } else if (Trigger.isDelete) {
            GlobalMatchingTriggerHandler.handlePreferenceChanges(
                Trigger.old, 
                Trigger.oldMap, 
                'DELETE'
            );
        }
    }
}
