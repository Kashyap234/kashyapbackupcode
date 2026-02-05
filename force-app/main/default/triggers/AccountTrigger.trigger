/**
 * @description Trigger on Account to schedule batch processing when families are modified
 * Only triggers for accounts that are foster families (have active preferences)
 */
trigger AccountTrigger on Account (after update) {
    
    // Collect Account IDs that might be families
    Set<Id> accountIds = new Set<Id>();
    
    for (Account acc : Trigger.new) {
        Account oldAcc = Trigger.oldMap.get(acc.Id);
        
        // Check if relevant fields changed
        if (acc.License_Status__c != oldAcc.License_Status__c ||
            acc.Background_Check_Status__c != oldAcc.Background_Check_Status__c ||
            acc.Training_Status__c != oldAcc.Training_Status__c ||
            acc.Available_Capacity__c != oldAcc.Available_Capacity__c ||
            acc.Jurisdiction__c != oldAcc.Jurisdiction__c ||
            acc.Latitude__c != oldAcc.Latitude__c ||
            acc.Longitude__c != oldAcc.Longitude__c) {
            
            accountIds.add(acc.Id);
        }
    }
    
    if (!accountIds.isEmpty()) {
        // Check if any of these accounts have active preferences
        List<Preference__c> activePrefs = [
            SELECT Id 
            FROM Preference__c 
            WHERE Family__c IN :accountIds 
            AND Status__c = 'Active'
            LIMIT 1
        ];
        
        if (!activePrefs.isEmpty()) {
            MatchingMatrixScheduler.scheduleBatchWithDelay(5);
        }
    }
}
