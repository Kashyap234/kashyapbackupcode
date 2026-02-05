/**
 * @description Trigger on Preference__c to schedule batch processing when preferences are modified
 */
trigger PreferenceTrigger on Preference__c (after insert, after update, after delete) {
    
    // Only process if status is 'Active' or was 'Active'
    Boolean shouldScheduleBatch = false;
    
    if (Trigger.isInsert || Trigger.isUpdate) {
        for (Preference__c pref : Trigger.new) {
            if (pref.Status__c == 'Active') {
                shouldScheduleBatch = true;
                break;
            }
        }
    }
    
    if (Trigger.isUpdate) {
        for (Preference__c pref : Trigger.old) {
            if (pref.Status__c == 'Active') {
                shouldScheduleBatch = true;
                break;
            }
        }
    }
    
    if (Trigger.isDelete) {
        for (Preference__c pref : Trigger.old) {
            if (pref.Status__c == 'Active') {
                shouldScheduleBatch = true;
                break;
            }
        }
    }
    
    if (shouldScheduleBatch) {
        MatchingMatrixScheduler.scheduleBatchWithDelay(5); // Schedule after 5 seconds
    }
}
