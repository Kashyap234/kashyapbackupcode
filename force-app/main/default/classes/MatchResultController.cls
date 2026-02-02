/**
 * @description Controller for updating match result statuses
 */
public with sharing class MatchResultController {
    
    @AuraEnabled
    public static String updateMatchStatus(
        String matchResultId, 
        String newStatus, 
        String notes,
        String notSuitableReason
    ) {
        try {
            Match_Result__c matchResult = [
                SELECT Id, Match_Status__c, Preference__c
                FROM Match_Result__c
                WHERE Id = :matchResultId
                LIMIT 1
            ];
            
            // If marking as "Outreach Approved", ensure only one per preference
            if (newStatus == 'Outreach Approved') {
                List<Match_Result__c> existingApproved = [
                    SELECT Id
                    FROM Match_Result__c
                    WHERE Preference__c = :matchResult.Preference__c
                    AND Match_Status__c = 'Outreach Approved'
                    AND Id != :matchResultId
                ];
                
                if (!existingApproved.isEmpty()) {
                    return 'ERROR: Another child is already approved for outreach for this preference. ' +
                           'Please change that status first.';
                }
                
                matchResult.Recommended_By__c = UserInfo.getUserId();
                matchResult.Recommended_Date__c = System.now();
            }
            
            matchResult.Match_Status__c = newStatus;
            
            if (String.isNotBlank(notes)) {
                matchResult.Caseworker_Notes__c = 
                    (matchResult.Caseworker_Notes__c != null ? 
                     matchResult.Caseworker_Notes__c + '\n\n' : '') +
                    System.now().format('yyyy-MM-dd HH:mm') + ' - ' + notes;
            }
            
            if (String.isNotBlank(notSuitableReason)) {
                matchResult.Not_Suitable_Reason__c = notSuitableReason;
            }
            
            update matchResult;
            
            return 'SUCCESS';
            
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Match_Result__c> getMatchHistory(String preferenceId) {
        return [
            SELECT Id, Child__c, Child__r.Name, Child__r.First_Name__c,
                   Match_Score__c, Match_Status__c, Match_Date__c,
                   Match_Reasons__c, Caseworker_Notes__c,
                   Recommended_By__r.Name, Recommended_Date__c
            FROM Match_Result__c
            WHERE Preference__c = :preferenceId
            ORDER BY Match_Date__c DESC
        ];
    }
}