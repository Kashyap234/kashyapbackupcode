/**
 * @description Controller for Matrix-Based Family Matching Component
 * Retrieves pre-calculated matches from the Child_Family_Match_Matrix__c object
 */
public with sharing class MatrixFamilyMatchingController {
    
    /**
     * Get top family matches for a child from the matrix
     */
    @AuraEnabled(cacheable=true)
    public static List<MatrixFamilyMatch> getMatrixMatches(String childId) {
        System.debug('=== Getting Matrix Matches for Child: ' + childId + ' ===');
        
        try {
            // Query matrix records with all related data
            List<Child_Family_Match_Matrix__c> matrixRecords = [
                SELECT Id, Child__c, Preference__c, Family__c,
                       Overall_Score__c, High_Priority_Score__c,
                       Medium_Priority_Score__c, Low_Priority_Score__c,
                       Distance_Miles__c, Match_Rank__c,
                       Hard_Constraints_Met__c, Calculated_Date__c,
                       Family__r.Name,
                       Family__r.Available_Capacity__c,
                       Family__r.License_Status__c,
                       Family__r.BillingCity,
                       Family__r.BillingState,
                       Preference__r.Id,
                       Preference__r.Name
                FROM Child_Family_Match_Matrix__c
                WHERE Child__c = :childId
                AND Is_Active__c = true
                ORDER BY Match_Rank__c ASC, Overall_Score__c DESC
                LIMIT 10
            ];
            
            System.debug('Found ' + matrixRecords.size() + ' matrix matches');
            
            if (matrixRecords.isEmpty()) {
                System.debug('No matrix matches found - batch may not have run yet');
                return new List<MatrixFamilyMatch>();
            }
            
            // Convert to wrapper objects
            List<MatrixFamilyMatch> matches = new List<MatrixFamilyMatch>();
            
            for (Child_Family_Match_Matrix__c matrix : matrixRecords) {
                MatrixFamilyMatch match = new MatrixFamilyMatch();
                
                match.matrixId = matrix.Id;
                match.familyId = matrix.Family__c;
                match.familyName = matrix.Family__r.Name;
                match.familyRecordLink = '/' + matrix.Family__c;
                match.preferenceId = matrix.Preference__c;
                match.preferenceName = matrix.Preference__r.Name;
                
                match.overallScore = matrix.Overall_Score__c;
                match.highPriorityScore = matrix.High_Priority_Score__c != null ? 
                    matrix.High_Priority_Score__c : 0;
                match.mediumPriorityScore = matrix.Medium_Priority_Score__c != null ? 
                    matrix.Medium_Priority_Score__c : 0;
                match.lowPriorityScore = matrix.Low_Priority_Score__c != null ? 
                    matrix.Low_Priority_Score__c : 0;
                
                match.distanceMiles = matrix.Distance_Miles__c;
                match.matchRank = Integer.valueOf(matrix.Match_Rank__c);
                match.hardConstraintsMet = matrix.Hard_Constraints_Met__c;
                match.calculatedDate = matrix.Calculated_Date__c;
                
                match.familyCapacity = Integer.valueOf(matrix.Family__r.Available_Capacity__c);
                match.licenseStatus = matrix.Family__r.License_Status__c;
                match.familyLocation = (matrix.Family__r.BillingCity != null ? 
                    matrix.Family__r.BillingCity + ', ' : '') + 
                    (matrix.Family__r.BillingState != null ? 
                    matrix.Family__r.BillingState : '');
                
                matches.add(match);
            }
            
            System.debug('Returning ' + matches.size() + ' matches');
            return matches;
            
        } catch (Exception e) {
            System.debug('ERROR: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving matches: ' + e.getMessage());
        }
    }
    
    /**
     * Manually trigger batch recalculation for a specific child
     */
    @AuraEnabled
    public static String triggerRecalculation(String childId) {
        try {
            // Schedule the batch to run immediately
            MatchingMatrixScheduler.scheduleBatchWithDelay(1);
            return 'SUCCESS: Batch recalculation scheduled';
        } catch (Exception e) {
            throw new AuraHandledException('Error scheduling recalculation: ' + e.getMessage());
        }
    }
    
    /**
     * Check if batch is currently running
     */
    @AuraEnabled(cacheable=true)
    public static BatchStatus getBatchStatus() {
        BatchStatus status = new BatchStatus();
        
        // Check for running batch
        List<AsyncApexJob> runningBatches = [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems,
                   NumberOfErrors, CreatedDate
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'ChildFamilyMatchingMatrixBatch'
            AND Status IN ('Processing', 'Preparing', 'Queued')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (!runningBatches.isEmpty()) {
            AsyncApexJob job = runningBatches[0];
            status.isRunning = true;
            status.status = job.Status;
            status.itemsProcessed = job.JobItemsProcessed;
            status.totalItems = job.TotalJobItems;
            status.errors = job.NumberOfErrors;
        } else {
            status.isRunning = false;
            status.status = 'Not Running';
        }
        
        // Get last successful run
        List<AsyncApexJob> completedBatches = [
            SELECT Id, CompletedDate
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'ChildFamilyMatchingMatrixBatch'
            AND Status = 'Completed'
            ORDER BY CompletedDate DESC
            LIMIT 1
        ];
        
        if (!completedBatches.isEmpty()) {
            status.lastRunDate = completedBatches[0].CompletedDate;
        }
        
        return status;
    }
    
    /**
     * Wrapper class for matrix match
     */
    public class MatrixFamilyMatch {
        @AuraEnabled public String matrixId {get; set;}
        @AuraEnabled public String familyId {get; set;}
        @AuraEnabled public String familyName {get; set;}
        @AuraEnabled public String familyRecordLink {get; set;}
        @AuraEnabled public String preferenceId {get; set;}
        @AuraEnabled public String preferenceName {get; set;}
        @AuraEnabled public Decimal overallScore {get; set;}
        @AuraEnabled public Decimal highPriorityScore {get; set;}
        @AuraEnabled public Decimal mediumPriorityScore {get; set;}
        @AuraEnabled public Decimal lowPriorityScore {get; set;}
        @AuraEnabled public Decimal distanceMiles {get; set;}
        @AuraEnabled public Integer matchRank {get; set;}
        @AuraEnabled public Boolean hardConstraintsMet {get; set;}
        @AuraEnabled public DateTime calculatedDate {get; set;}
        @AuraEnabled public Integer familyCapacity {get; set;}
        @AuraEnabled public String licenseStatus {get; set;}
        @AuraEnabled public String familyLocation {get; set;}
    }
    
    /**
     * Wrapper class for batch status
     */
    public class BatchStatus {
        @AuraEnabled public Boolean isRunning {get; set;}
        @AuraEnabled public String status {get; set;}
        @AuraEnabled public Integer itemsProcessed {get; set;}
        @AuraEnabled public Integer totalItems {get; set;}
        @AuraEnabled public Integer errors {get; set;}
        @AuraEnabled public DateTime lastRunDate {get; set;}
        
        public BatchStatus() {
            this.isRunning = false;
            this.status = 'Unknown';
            this.itemsProcessed = 0;
            this.totalItems = 0;
            this.errors = 0;
        }
    }
}