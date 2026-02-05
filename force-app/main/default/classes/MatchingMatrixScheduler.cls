/**
 * @description Utility class to schedule the matching matrix batch with delay
 * Prevents multiple concurrent batch jobs and implements smart scheduling
 */
public class MatchingMatrixScheduler {
    
    private static final String JOB_NAME_PREFIX = 'Child Family Matrix Batch';
    
    /**
     * Schedule the batch to run after a delay (in seconds)
     * Prevents duplicate scheduling
     */
    public static void scheduleBatchWithDelay(Integer delaySeconds) {
        // Check if batch is already scheduled or running
        if (isBatchRunningOrScheduled()) {
            System.debug('Batch already running or scheduled, skipping duplicate schedule');
            return;
        }
        
        // Calculate run time
        DateTime runTime = System.now().addSeconds(delaySeconds);
        String cronExp = buildCronExpression(runTime);
        
        // Schedule the batch
        try {
            String jobName = JOB_NAME_PREFIX + ' - ' + System.now().format('yyyy-MM-dd HH:mm:ss');
            System.schedule(jobName, cronExp, new MatchingMatrixSchedulable());
            System.debug('Scheduled batch job: ' + jobName + ' to run at: ' + runTime);
        } catch (Exception e) {
            System.debug('Error scheduling batch: ' + e.getMessage());
        }
    }
    
    /**
     * Check if batch is currently running or scheduled
     */
    private static Boolean isBatchRunningOrScheduled() {
        // Check for running batch jobs
        List<AsyncApexJob> runningBatches = [
            SELECT Id, Status, ApexClass.Name
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'ChildFamilyMatchingMatrixBatch'
            AND Status IN ('Processing', 'Preparing', 'Queued')
            LIMIT 1
        ];
        
        if (!runningBatches.isEmpty()) {
            return true;
        }
        
        // Check for scheduled jobs
        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name, State, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            AND State = 'WAITING'
            AND NextFireTime != null
            LIMIT 1
        ];
        
        return !scheduledJobs.isEmpty();
    }
    
    /**
     * Build CRON expression from DateTime
     */
    private static String buildCronExpression(DateTime dt) {
        Integer second = dt.second();
        Integer minute = dt.minute();
        Integer hour = dt.hour();
        Integer day = dt.day();
        Integer month = dt.month();
        Integer year = dt.year();
        
        // CRON format: Seconds Minutes Hours Day_of_month Month Day_of_week Year
        return second + ' ' + minute + ' ' + hour + ' ' + day + ' ' + month + ' ? ' + year;
    }
    
    /**
     * Delete old scheduled jobs
     */
    public static void cleanupOldScheduledJobs() {
        List<CronTrigger> oldJobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
            AND State = 'DELETED'
        ];
        
        System.debug('Found ' + oldJobs.size() + ' old scheduled jobs to clean up');
    }
}