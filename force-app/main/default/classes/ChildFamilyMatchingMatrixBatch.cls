/**
 * @description Batch class to calculate and store child-family matching scores in a matrix
 * This batch processes all children needing placement and calculates scores against all
 * eligible families, storing results for optimized retrieval.
 * 
 * SCHEDULE: Run this batch whenever:
 * - Child records are created/updated/deleted (Status = 'Needs Placement')
 * - Preference records are created/updated/deleted (Status = 'Active')
 * - Family (Account) records are updated
 * 
 * Schedule Example: System.schedule('Child Family Matrix - Hourly', '0 0 * * * ?', new ChildFamilyMatchingMatrixBatch());
 */
public class ChildFamilyMatchingMatrixBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    // Track batch statistics
    private Integer totalChildrenProcessed = 0;
    private Integer totalScoresCalculated = 0;
    private Integer totalMatchesCreated = 0;
    private DateTime batchStartTime;
    
    // Configuration
    private static final Integer TOP_MATCHES_PER_CHILD = 3;
    private static final Decimal MINIMUM_PASSING_SCORE = 50.0;
    
    public ChildFamilyMatchingMatrixBatch() {
        this.batchStartTime = System.now();
    }
    
    /**
     * Start method - Query all children needing placement
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('=== BATCH START: Child-Family Matching Matrix ===');
        System.debug('Batch Start Time: ' + this.batchStartTime);
        
        // Query all children needing placement
        String query = 'SELECT Id, Name, ' +
                      'First_Name__c, Middle_Name__c, Last_Name__c, ' +
                      'Current_Age__c, Date_of_Birth__c, Gender__c, ' +
                      'Age_Group__c, Race__c, Jurisdiction__c, ' +
                      'Is_Sibling_Group__c, Sibling_Group_Size__c, ' +
                      'SpecialNeeds__c, MedicalNeedsWillingness__c, ' +
                      'BehavioralSupport__c, TherapyRequired__c, ' +
                      'Reunification__c, School_Name__c, ' +
                      'Latitude__c, Longitude__c, Status__c ' +
                      'FROM Child__c ' +
                      'WHERE Status__c = \'Needs Placement\' ' +
                      'ORDER BY Date_of_Birth__c DESC';
        
        System.debug('Query: ' + query);
        return Database.getQueryLocator(query);
    }
    
    /**
     * Execute method - Process each batch of children
     */
    public void execute(Database.BatchableContext bc, List<Child__c> children) {
        System.debug('=== BATCH EXECUTE: Processing ' + children.size() + ' children ===');
        
        try {
            // Load matching configurations once per batch
            List<MatchingConfiguration> configs = MatchingConfiguration.loadConfigurations();
            System.debug('Loaded ' + configs.size() + ' matching configurations');
            
            // Process each child
            for (Child__c child : children) {
                processChildMatching(child, configs);
            }
            
        } catch (Exception e) {
            System.debug('ERROR in batch execute: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }
    
    /**
     * Process matching for a single child
     */
    private void processChildMatching(Child__c child, List<MatchingConfiguration> configs) {
        System.debug('--- Processing child: ' + child.Name + ' (ID: ' + child.Id + ') ---');
        
        try {
            // Load all eligible families with preferences in the same jurisdiction
            List<PreferenceWrapper> eligibleFamilies = loadEligibleFamilies(child.Jurisdiction__c);
            System.debug('Found ' + eligibleFamilies.size() + ' eligible families');
            
            if (eligibleFamilies.isEmpty()) {
                System.debug('No eligible families found for child ' + child.Name);
                return;
            }
            
            // Calculate scores for all families
            Map<String, FamilyScore> familyScoreMap = new Map<String, FamilyScore>();
            
            for (PreferenceWrapper wrapper : eligibleFamilies) {
                FamilyScore score = calculateFamilyScore(child, wrapper.preference, wrapper.family, configs);
                
                // Only store if passes minimum score and hard constraints
                if (score.overallScore >= MINIMUM_PASSING_SCORE && score.hardConstraintsMet) {
                    familyScoreMap.put(wrapper.preference.Id, score);
                    totalScoresCalculated++;
                }
            }
            
            System.debug('Calculated ' + familyScoreMap.size() + ' passing scores for child ' + child.Name);
            
            // Get top N matches
            List<FamilyScore> topMatches = getTopMatches(familyScoreMap, TOP_MATCHES_PER_CHILD);
            System.debug('Selected top ' + topMatches.size() + ' matches');
            
            // Save the matrix results
            saveChildMatchMatrix(child.Id, topMatches);
            
            totalChildrenProcessed++;
            
        } catch (Exception e) {
            System.debug('ERROR processing child ' + child.Name + ': ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Continue processing other children
        }
    }
    
    /**
     * Load all eligible families with active preferences
     */
    private List<PreferenceWrapper> loadEligibleFamilies(String jurisdiction) {
        List<PreferenceWrapper> wrappers = new List<PreferenceWrapper>();
        
        List<Preference__c> preferences = [
            SELECT Id, Name, Family__c,
                   Gender_Preference__c,
                   Preferred_Age_Range_Min__c,
                   Preferred_Age_Range_Max__c,
                   Sibling_Group_Acceptance__c,
                   Special_Needs_Acceptance__c,
                   Medical_Needs_Willingness__c,
                   Medical_Needs_Willingness_If_any__c,
                   Willing_to_Support_Reunification__c,
                   Behavioral_Support_Willingness__c,
                   Behavioral_Support_Willingness_If_any__c,
                   Previous_Foster_Experience__c,
                   Preferred_School_Name__c,
                   Race_Or_Ethnicity_Preferences__c,
                   Religion_Preference_Flexibility__c,
                   Status__c,
                   Family__r.Id,
                   Family__r.Name,
                   Family__r.License_Status__c,
                   Family__r.Background_Check_Status__c,
                   Family__r.Training_Status__c,
                   Family__r.Jurisdiction__c,
                   Family__r.Latitude__c,
                   Family__r.Longitude__c,
                   Family__r.Current_Capacity__c,
                   Family__r.Available_Capacity__c,
                   Family__r.Previous_Foster_Experience__c,
                   Family__r.BillingStreet,
                   Family__r.BillingCity,
                   Family__r.BillingState,
                   Family__r.BillingPostalCode
            FROM Preference__c
            WHERE Status__c = 'Active'
            AND Family__r.Jurisdiction__c = :jurisdiction
            AND Family__r.License_Status__c = 'Active'
            AND Family__r.Background_Check_Status__c = 'Complete'
            AND Family__r.Training_Status__c = 'Complete'
            AND Family__r.Available_Capacity__c >= 1
        ];
        
        for (Preference__c pref : preferences) {
            PreferenceWrapper wrapper = new PreferenceWrapper();
            wrapper.preference = pref;
            wrapper.family = pref.Family__r;
            wrappers.add(wrapper);
        }
        
        return wrappers;
    }
    
    /**
     * Calculate score for a single family-child match
     */
    private FamilyScore calculateFamilyScore(
        Child__c child,
        Preference__c pref,
        Account family,
        List<MatchingConfiguration> configs
    ) {
        FamilyScore result = new FamilyScore();
        result.preferenceId = pref.Id;
        result.familyId = family.Id;
        result.familyName = family.Name;
        result.childId = child.Id;
        
        // Check hard constraints
        result.hardConstraintsMet = checkHardConstraints(child, family);
        
        if (!result.hardConstraintsMet) {
            result.overallScore = 0;
            return result;
        }
        
        // Calculate distance
        result.distanceMiles = calculateDistance(
            family.Latitude__c, family.Longitude__c,
            child.Latitude__c, child.Longitude__c
        );
        
        // Calculate scores by priority
        Decimal highPriorityTotal = 0;
        Decimal highPriorityMax = 0;
        Decimal mediumPriorityTotal = 0;
        Decimal mediumPriorityMax = 0;
        Decimal lowPriorityTotal = 0;
        Decimal lowPriorityMax = 0;
        
        for (MatchingConfiguration config : configs) {
            if (!config.isActive) continue;
            
            Decimal score = calculateCriterionScore(child, pref, config);
            
            if (config.priorityLevel == 'High') {
                highPriorityTotal += (score * config.weight);
                highPriorityMax += (100 * config.weight);
            } else if (config.priorityLevel == 'Medium') {
                mediumPriorityTotal += (score * config.weight);
                mediumPriorityMax += (100 * config.weight);
            } else if (config.priorityLevel == 'Low') {
                lowPriorityTotal += (score * config.weight);
                lowPriorityMax += (100 * config.weight);
            }
        }
        
        // Calculate final scores
        result.highPriorityScore = highPriorityMax > 0 ? 
            (highPriorityTotal / highPriorityMax * 100).setScale(2) : 0;
        result.mediumPriorityScore = mediumPriorityMax > 0 ? 
            (mediumPriorityTotal / mediumPriorityMax * 100).setScale(2) : 0;
        result.lowPriorityScore = lowPriorityMax > 0 ? 
            (lowPriorityTotal / lowPriorityMax * 100).setScale(2) : 0;
        
        // Weighted average: 60% high, 30% medium, 10% low + distance adjustment
        result.overallScore = (
            (result.highPriorityScore * 0.6) +
            (result.mediumPriorityScore * 0.3) +
            (result.lowPriorityScore * 0.1) +
            getDistanceAdjustment(result.distanceMiles)
        ).setScale(2);
        
        return result;
    }
    
    /**
     * Check hard constraints
     */
    private Boolean checkHardConstraints(Child__c child, Account family) {
        if (family.Available_Capacity__c < 1) return false;
        
        if (child.Is_Sibling_Group__c && 
            child.Sibling_Group_Size__c > family.Available_Capacity__c) {
            return false;
        }
        
        return true;
    }
    
    /**
     * Calculate criterion score (reusing logic from existing service)
     */
    private Decimal calculateCriterionScore(
        Child__c child,
        Preference__c pref,
        MatchingConfiguration config
    ) {
        try {
            String childValue = getFieldValue(child, config.childFieldAPI);
            String prefValue = getFieldValue(pref, config.preferenceFieldAPI);
            
            if (String.isBlank(prefValue) || prefValue == 'No Preference') {
                return 100;
            }
            
            switch on config.matchingLogic {
                when 'Exact Match' {
                    return childValue == prefValue ? 100 : 0;
                }
                when 'Range Match' {
                    return scoreAgeRange(child, pref);
                }
                when 'Contains' {
                    return scoreMultiSelectMatch(childValue, prefValue);
                }
                when 'Checkbox' {
                    return scoreCheckboxMatch(childValue, prefValue);
                }
                when else {
                    return 0;
                }
            }
        } catch (Exception e) {
            return 0;
        }
    }
    
    private String getFieldValue(SObject record, String fieldAPI) {
        try {
            Object value = record.get(fieldAPI);
            return value != null ? String.valueOf(value) : '';
        } catch (Exception e) {
            return '';
        }
    }
    
    private Decimal scoreAgeRange(Child__c child, Preference__c pref) {
        Decimal childAge = child.Current_Age__c;
        Decimal minAge = pref.Preferred_Age_Range_Min__c;
        Decimal maxAge = pref.Preferred_Age_Range_Max__c;
        
        if (minAge == null || maxAge == null) return 100;
        
        if (childAge >= minAge && childAge <= maxAge) return 100;
        if (childAge >= minAge - 1 && childAge <= maxAge + 1) return 50;
        return 0;
    }
    
    private Decimal scoreMultiSelectMatch(String childValue, String prefValue) {
        if (String.isBlank(childValue)) return 100;
        if (String.isBlank(prefValue)) return 100;
        
        Set<String> childSet = new Set<String>(childValue.split(';'));
        Set<String> prefSet = new Set<String>(prefValue.split(';'));
        
        Integer matches = 0;
        for (String childItem : childSet) {
            if (prefSet.contains(childItem.trim())) matches++;
        }
        
        return (Decimal.valueOf(matches) / childSet.size() * 100);
    }
    
    private Decimal scoreCheckboxMatch(String childValue, String prefValue) {
        Boolean childBool = childValue == 'true';
        Boolean prefBool = prefValue == 'true';
        
        if (!childBool) return 100;
        if (childBool && prefBool) return 100;
        return 0;
    }
    
    private Decimal calculateDistance(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return 0;
        
        Decimal R = 3959;
        Decimal dLat = (lat2 - lat1) * Math.PI / 180;
        Decimal dLon = (lon2 - lon1) * Math.PI / 180;
        
        Decimal a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                   Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                   Math.sin(dLon/2) * Math.sin(dLon/2);
        
        Decimal c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        return (R * c).setScale(2);
    }
    
    private Decimal getDistanceAdjustment(Decimal miles) {
        if (miles < 10) return 10;
        if (miles < 25) return 0;
        if (miles < 50) return -5;
        return -10;
    }
    
    /**
     * Get top N matches from the score map
     */
    private List<FamilyScore> getTopMatches(Map<String, FamilyScore> scoreMap, Integer topN) {
        List<FamilyScore> allScores = scoreMap.values();
        allScores.sort();
        
        List<FamilyScore> topMatches = new List<FamilyScore>();
        for (Integer i = 0; i < Math.min(topN, allScores.size()); i++) {
            topMatches.add(allScores[i]);
        }
        
        return topMatches;
    }
    
    /**
     * Save the matrix results to database
     */
    private void saveChildMatchMatrix(String childId, List<FamilyScore> topMatches) {
        if (topMatches.isEmpty()) {
            System.debug('No matches to save for child: ' + childId);
            return;
        }
        
        // Delete existing matrix records for this child
        List<Child_Family_Match_Matrix__c> existingRecords = [
            SELECT Id 
            FROM Child_Family_Match_Matrix__c 
            WHERE Child__c = :childId
        ];
        
        if (!existingRecords.isEmpty()) {
            delete existingRecords;
            System.debug('Deleted ' + existingRecords.size() + ' existing matrix records');
        }
        
        // Create new matrix records
        List<Child_Family_Match_Matrix__c> matrixRecords = new List<Child_Family_Match_Matrix__c>();
        
        Integer rank = 1;
        for (FamilyScore score : topMatches) {
            Child_Family_Match_Matrix__c matrix = new Child_Family_Match_Matrix__c(
                Child__c = childId,
                Preference__c = score.preferenceId,
                Family__c = score.familyId,
                Overall_Score__c = score.overallScore,
                High_Priority_Score__c = score.highPriorityScore,
                Medium_Priority_Score__c = score.mediumPriorityScore,
                Low_Priority_Score__c = score.lowPriorityScore,
                Distance_Miles__c = score.distanceMiles,
                Match_Rank__c = rank,
                Hard_Constraints_Met__c = score.hardConstraintsMet,
                Calculated_Date__c = System.now(),
                Is_Active__c = true
            );
            matrixRecords.add(matrix);
            rank++;
        }
        
        insert matrixRecords;
        totalMatchesCreated += matrixRecords.size();
        System.debug('Inserted ' + matrixRecords.size() + ' matrix records for child: ' + childId);
    }
    
    /**
     * Finish method - Log batch statistics
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('=== BATCH FINISH: Child-Family Matching Matrix ===');
        System.debug('Batch Start Time: ' + this.batchStartTime);
        System.debug('Batch End Time: ' + System.now());
        System.debug('Total Children Processed: ' + this.totalChildrenProcessed);
        System.debug('Total Scores Calculated: ' + this.totalScoresCalculated);
        System.debug('Total Match Records Created: ' + this.totalMatchesCreated);
        
        // Optionally send email notification
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems,
                   CreatedBy.Email, ExtendedStatus
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];
        
        System.debug('Job Status: ' + job.Status);
        System.debug('Job Items Processed: ' + job.JobItemsProcessed + ' / ' + job.TotalJobItems);
        System.debug('Number of Errors: ' + job.NumberOfErrors);
    }
    
    /**
     * Wrapper class for Preference and Family
     */
    private class PreferenceWrapper {
        public Preference__c preference;
        public Account family;
    }
    
    /**
     * Wrapper class for family score
     */
    private class FamilyScore implements Comparable {
        public String preferenceId;
        public String familyId;
        public String familyName;
        public String childId;
        public Decimal overallScore = 0;
        public Decimal highPriorityScore = 0;
        public Decimal mediumPriorityScore = 0;
        public Decimal lowPriorityScore = 0;
        public Decimal distanceMiles = 0;
        public Boolean hardConstraintsMet = false;
        
        public Integer compareTo(Object compareTo) {
            FamilyScore other = (FamilyScore) compareTo;
            
            if (this.overallScore > other.overallScore) return -1;
            if (this.overallScore < other.overallScore) return 1;
            
            if (this.distanceMiles < other.distanceMiles) return -1;
            if (this.distanceMiles > other.distanceMiles) return 1;
            
            return 0;
        }
    }
}