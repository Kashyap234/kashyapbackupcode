/**
 * @description Schedulable wrapper for ChildFamilyMatchingMatrixBatch
 */
public class MatchingMatrixSchedulable implements Schedulable {
    
    public void execute(SchedulableContext sc) {
        System.debug('=== Executing Scheduled Batch Job ===');
        System.debug('Job ID: ' + sc.getTriggerId());
        
        try {
            // Execute the batch with batch size of 10 children at a time
            ChildFamilyMatchingMatrixBatch batch = new ChildFamilyMatchingMatrixBatch();
            Database.executeBatch(batch, 10);
            
            System.debug('Batch job submitted successfully');
            
        } catch (Exception e) {
            System.debug('Error executing batch: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }
    }
}