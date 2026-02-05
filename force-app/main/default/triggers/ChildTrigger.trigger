/**
 * @description Trigger on Child__c to schedule batch processing when children are modified
 */
trigger ChildTrigger on Child__c (after insert, after update, after delete) {
    
    // Only process if status is 'Needs Placement' or was 'Needs Placement'
    Boolean shouldScheduleBatch = false;
    
    if (Trigger.isInsert || Trigger.isUpdate) {
        for (Child__c child : Trigger.new) {
            if (child.Status__c == 'Needs Placement') {
                shouldScheduleBatch = true;
                break;
            }
        }
    }
    
    if (Trigger.isUpdate) {
        for (Child__c child : Trigger.old) {
            if (child.Status__c == 'Needs Placement') {
                shouldScheduleBatch = true;
                break;
            }
        }
    }
    
    if (Trigger.isDelete) {
        for (Child__c child : Trigger.old) {
            if (child.Status__c == 'Needs Placement') {
                shouldScheduleBatch = true;
                break;
            }
        }
    }
    
    if (shouldScheduleBatch) {
        MatchingMatrixScheduler.scheduleBatchWithDelay(5); // Schedule after 5 seconds
    }
}
