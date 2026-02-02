/**
 * @description Service class for child matching algorithm - ENHANCED VERSION WITH DEBUG
 * Includes detailed score breakdowns for user-friendly display
 * 
 * FIX APPLIED: Added Medical_Needs_Willingness_If_any__c to loadPreference() query
 * DEBUG ADDED: Comprehensive logging for troubleshooting
 */
public with sharing class ChildMatchingService {
    
    private static final Integer MAX_RESULTS = 4;
    private static final Decimal PASSING_SCORE = 50.0;
    
    /**
     * @description Main entry point for matching
     */
    @AuraEnabled
    public static MatchingResponse runMatching(String preferenceId) {
        System.debug('=== START runMatching ===');
        System.debug('preferenceId: ' + preferenceId);
        
        try {
            System.debug('Step 1: Loading preference...');
            Preference__c preference = loadPreference(preferenceId);
            System.debug('Preference loaded: ' + preference.Name + ', Family: ' + preference.Family__c);
            
            System.debug('Step 2: Loading family...');
            Account family = loadFamily(preference.Family__c);
            System.debug('Family loaded: ' + family.Name + ', Jurisdiction: ' + family.Jurisdiction__c);
            
            System.debug('Step 3: Validating family hard constraints...');
            Boolean familyValid = validateFamilyHardConstraints(family);
            System.debug('Family validation result: ' + familyValid);
            
            if (!familyValid) {
                System.debug('Family does not meet hard constraints');
                return new MatchingResponse(
                    false, 
                    'Family does not meet hard constraints for fostering', 
                    null
                );
            }
            
            System.debug('Step 4: Loading matching configurations...');
            List<MatchingConfiguration> configs = MatchingConfiguration.loadConfigurations();
            System.debug('Loaded ' + configs.size() + ' active configurations');
            
            System.debug('Step 5: Loading eligible children...');
            List<Child__c> children = loadEligibleChildren(family.Jurisdiction__c);
            System.debug('Found ' + children.size() + ' eligible children');
            
            System.debug('Step 6: Scoring children...');
            List<ChildMatchResult> results = new List<ChildMatchResult>();
            Integer childCounter = 0;
            
            for (Child__c child : children) {
                childCounter++;
                System.debug('Scoring child ' + childCounter + '/' + children.size() + ': ' + child.Name);
                
                ChildMatchResult result = scoreChild(child, preference, family, configs);
                System.debug('Child ' + child.Name + ' score: ' + result.overallScore + ', Hard constraints met: ' + result.hardConstraintsMet);
                
                if (result.hardConstraintsMet && result.overallScore >= PASSING_SCORE) {
                    results.add(result);
                    System.debug('Added to results (Score: ' + result.overallScore + ')');
                } else {
                    System.debug('Not added - Score: ' + result.overallScore + ', Constraints: ' + result.hardConstraintsMet);
                }
            }
            
            System.debug('Step 7: Sorting results...');
            results.sort();
            System.debug('Total qualified matches: ' + results.size());
            
            System.debug('Step 8: Selecting top results...');
            List<ChildMatchResult> topResults = new List<ChildMatchResult>();
            for (Integer i = 0; i < Math.min(MAX_RESULTS, results.size()); i++) {
                topResults.add(results[i]);
                System.debug('Top match #' + (i+1) + ': ' + results[i].childName + ' (Score: ' + results[i].overallScore + ')');
            }
            
            System.debug('Step 9: Saving match results to database...');
            saveMatchResults(preferenceId, topResults);
            System.debug('Match results saved successfully');
            
            System.debug('Step 10: Creating response...');
            MatchingResponse response = new MatchingResponse(true, 'Matching completed successfully', topResults);
            System.debug('Response created - Success: ' + response.success + ', Results count: ' + (response.results != null ? response.results.size() : 0));
            
            System.debug('=== END runMatching SUCCESS ===');
            return response;
            
        } catch (Exception e) {
            System.debug('=== ERROR in runMatching ===');
            System.debug('Error Type: ' + e.getTypeName());
            System.debug('Error Message: ' + e.getMessage());
            System.debug('Line Number: ' + e.getLineNumber());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            System.debug('=== END runMatching ERROR ===');
            
            return new MatchingResponse(false, 'Error: ' + e.getMessage(), null);
        }
    }
    
    /**
     * @description Load preference with all related fields
     * FIX: Added Medical_Needs_Willingness_If_any__c to the query
     */
    private static Preference__c loadPreference(String preferenceId) {
        System.debug('Loading preference with ID: ' + preferenceId);
        Preference__c pref = [
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
                   Status__c
            FROM Preference__c
            WHERE Id = :preferenceId
            LIMIT 1
        ];
        System.debug('Preference query completed');
        return pref;
    }
    
    /**
     * @description Load family account with all necessary fields
     */
    private static Account loadFamily(String familyId) {
        System.debug('Loading family with ID: ' + familyId);
        Account family = [
            SELECT Id, Name,
                   License_Status__c,
                   Background_Check_Status__c,
                   Training_Status__c,
                   Jurisdiction__c,
                   Latitude__c,
                   Longitude__c,
                   Current_Capacity__c,
                   Available_Capacity__c,
                   Previous_Foster_Experience__c,
                   BillingStreet,
                   BillingCity,
                   BillingState,
                   BillingPostalCode
            FROM Account
            WHERE Id = :familyId
            LIMIT 1
        ];
        System.debug('Family query completed');
        return family;
    }
    
    /**
     * @description Validate family meets hard constraints
     */
    private static Boolean validateFamilyHardConstraints(Account family) {
        System.debug('Validating family constraints:');
        System.debug('  License Status: ' + family.License_Status__c);
        System.debug('  Background Check: ' + family.Background_Check_Status__c);
        System.debug('  Training Status: ' + family.Training_Status__c);
        System.debug('  Available Capacity: ' + family.Available_Capacity__c);
        
        Boolean isValid = family.License_Status__c == 'Active' &&
               family.Background_Check_Status__c == 'Complete' &&
               family.Training_Status__c == 'Complete' &&
               family.Available_Capacity__c >= 1;
               
        System.debug('Overall validation result: ' + isValid);
        return isValid;
    }
    
    /**
     * @description Load all children needing placement
     */
    private static List<Child__c> loadEligibleChildren(String jurisdiction) {
        System.debug('Loading children for jurisdiction: ' + jurisdiction);
        List<Child__c> children = [
            SELECT Id, Name,
                   First_Name__c,
                   Middle_Name__c,
                   Last_Name__c,
                   Current_Age__c,
                   Date_of_Birth__c,
                   Gender__c,
                   Age_Group__c,
                   Race__c,
                   Jurisdiction__c,
                   Is_Sibling_Group__c,
                   Sibling_Group_Size__c,
                   SpecialNeeds__c,
                   MedicalNeedsWillingness__c,
                   BehavioralSupport__c,
                   TherapyRequired__c,
                   Reunification__c,
                   School_Name__c,
                   Latitude__c,
                   Longitude__c,
                   Status__c
            FROM Child__c
            WHERE Status__c = 'Needs Placement'
            AND Jurisdiction__c = :jurisdiction
            ORDER BY Date_of_Birth__c DESC
        ];
        System.debug('Children query completed: ' + children.size() + ' records');
        return children;
    }
    
    /**
     * @description Score a single child with detailed breakdown
     */
    private static ChildMatchResult scoreChild(
        Child__c child, 
        Preference__c pref, 
        Account family,
        List<MatchingConfiguration> configs
    ) {
        System.debug('--- Scoring child: ' + child.Name + ' ---');
        ChildMatchResult result = new ChildMatchResult();
        
        // Basic info
        result.childId = child.Id;
        result.childName = child.First_Name__c + ' ' + child.Last_Name__c;
        result.childRecordLink = '/' + child.Id;
        result.childAge = Integer.valueOf(child.Current_Age__c);
        result.childGender = child.Gender__c;
        result.familyName = family.Name;
        result.familyCapacity = Integer.valueOf(family.Available_Capacity__c);
        
        System.debug('Child basic info: Age=' + result.childAge + ', Gender=' + result.childGender);
        
        // Calculate distance
        result.distanceMiles = calculateDistance(
            family.Latitude__c, family.Longitude__c,
            child.Latitude__c, child.Longitude__c
        );
        System.debug('Distance calculated: ' + result.distanceMiles + ' miles');
        
        // Check hard constraints
        result.hardConstraintsMet = checkHardConstraints(child, family);
        System.debug('Hard constraints met: ' + result.hardConstraintsMet);
        
        if (!result.hardConstraintsMet) {
            result.overallScore = 0;
            result.matchReasons.add('Failed hard constraints');
            System.debug('Child failed hard constraints, returning early');
            return result;
        }
        
        // Calculate scores with detailed breakdown
        System.debug('Calculating criterion scores...');
        Decimal highPriorityTotal = 0;
        Decimal highPriorityMax = 0;
        Decimal mediumPriorityTotal = 0;
        Decimal mediumPriorityMax = 0;
        Decimal lowPriorityTotal = 0; // NEW - Added for Low Priority
        Decimal lowPriorityMax = 0;   // NEW - Added for Low Priority
        
        Integer configCounter = 0;
        for (MatchingConfiguration config : configs) {
            if (!config.isActive) continue;
            configCounter++;
            
            Decimal score = calculateCriterionScore(child, pref, config);
            System.debug('  Config #' + configCounter + ' (' + config.criterionName + '): Score=' + score + ', Weight=' + config.weight + ', Priority=' + config.priorityLevel);
            
            // Store detailed score information for UI
            Map<String, Object> scoreDetail = new Map<String, Object>();
            scoreDetail.put('criterionName', config.criterionName);
            scoreDetail.put('priority', config.priorityLevel);
            scoreDetail.put('weight', config.weight);
            scoreDetail.put('score', score.setScale(2)); // FIX: Ensure proper decimal format
            scoreDetail.put('matchingLogic', config.matchingLogic);
            
            // Get actual field values for comparison
            String childValue = getFieldValue(child, config.childFieldAPI);
            String prefValue = getFieldValue(pref, config.preferenceFieldAPI);
            
            scoreDetail.put('childValue', childValue);
            scoreDetail.put('preferenceValue', prefValue);
            
            result.detailedScores.put(config.criterionName, scoreDetail);
            
            // Track weighted scores by priority
            if (config.priorityLevel == 'High') {
                highPriorityTotal += (score * config.weight);
                highPriorityMax += (100 * config.weight);
            } else if (config.priorityLevel == 'Medium') {
                mediumPriorityTotal += (score * config.weight);
                mediumPriorityMax += (100 * config.weight);
            } else if (config.priorityLevel == 'Low') { // NEW - Added for Low Priority
                lowPriorityTotal += (score * config.weight);
                lowPriorityMax += (100 * config.weight);
            }
            
            // Add to match reasons if score > 80
            if (score >= 80) {
                result.matchReasons.add(config.criterionName);
            }
        }
        
        // Calculate final scores
        result.highPriorityScore = highPriorityMax > 0 ? 
            (highPriorityTotal / highPriorityMax * 100).setScale(2) : 0;
        result.mediumPriorityScore = mediumPriorityMax > 0 ? 
            (mediumPriorityTotal / mediumPriorityMax * 100).setScale(2) : 0;
        result.lowPriorityScore = lowPriorityMax > 0 ?  // NEW - Calculate Low Priority score
            (lowPriorityTotal / lowPriorityMax * 100).setScale(2) : 0;
        
        System.debug('High Priority Score: ' + result.highPriorityScore);
        System.debug('Medium Priority Score: ' + result.mediumPriorityScore);
        System.debug('Low Priority Score: ' + result.lowPriorityScore); // NEW - Log Low Priority score
        
        // Weighted average: 60% high priority, 30% medium priority, 10% low priority
        result.overallScore = (
            (result.highPriorityScore * 0.6) +
            (result.mediumPriorityScore * 0.3) +
            (result.lowPriorityScore * 0.1) +
            getDistanceAdjustment(result.distanceMiles)
        ).setScale(2);
        
        System.debug('Overall Score (before distance): ' + 
            ((result.highPriorityScore * 0.6) + (result.mediumPriorityScore * 0.3) + (result.lowPriorityScore * 0.1)));
        System.debug('Distance adjustment: ' + getDistanceAdjustment(result.distanceMiles));
        System.debug('Final Overall Score: ' + result.overallScore);
        
        // Add flags
        addFlags(result, child, family);
        System.debug('Flags added: ' + result.flags.size());
        
        System.debug('--- End scoring child ---');
        return result;
    }
    
    /**
     * @description Check if child passes family's hard constraints
     */
    private static Boolean checkHardConstraints(Child__c child, Account family) {
        System.debug('Checking hard constraints for child: ' + child.Name);
        
        // Check available capacity
        if (family.Available_Capacity__c < 1) {
            System.debug('  Failed: No available capacity');
            return false;
        }
        
        // Check sibling groups
        if (child.Is_Sibling_Group__c && 
            child.Sibling_Group_Size__c > family.Available_Capacity__c) {
            System.debug('  Failed: Sibling group too large for capacity');
            return false;
        }
        
        System.debug('  Passed all hard constraints');
        return true;
    }
    
    /**
     * @description Calculate score for a single criterion
     */
    private static Decimal calculateCriterionScore(
        Child__c child,
        Preference__c pref,
        MatchingConfiguration config
    ) {
        try {
            String childValue = getFieldValue(child, config.childFieldAPI);
            String prefValue = getFieldValue(pref, config.preferenceFieldAPI);
            
            // Handle null preferences as "No Preference" = 100%
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
            System.debug('Error calculating score for ' + config.criterionName + ': ' + e.getMessage());
            return 0;
        }
    }
    
    /**
     * @description Get field value dynamically
     * ENHANCED: Better error handling for missing fields
     */
    private static String getFieldValue(SObject record, String fieldAPI) {
        try {
            Object value = record.get(fieldAPI);
            return value != null ? String.valueOf(value) : '';
        } catch (SObjectException e) {
            System.debug('Warning: Field ' + fieldAPI + ' not queried on ' + 
                        record.getSObjectType() + '. Error: ' + e.getMessage());
            return '';
        } catch (Exception e) {
            System.debug('Error accessing field ' + fieldAPI + ': ' + e.getMessage());
            return '';
        }
    }
    
    /**
     * @description Score age range matching
     */
    private static Decimal scoreAgeRange(Child__c child, Preference__c pref) {
        Decimal childAge = child.Current_Age__c;
        Decimal minAge = pref.Preferred_Age_Range_Min__c;
        Decimal maxAge = pref.Preferred_Age_Range_Max__c;
        
        if (minAge == null || maxAge == null) return 100;
        
        if (childAge >= minAge && childAge <= maxAge) {
            return 100; // Perfect match
        } else if (childAge >= minAge - 1 && childAge <= maxAge + 1) {
            return 50; // Within 1 year tolerance
        } else {
            return 0; // Outside range
        }
    }
    
    /**
     * @description Score multi-select picklist matching
     */
    private static Decimal scoreMultiSelectMatch(String childValue, String prefValue) {
        if (String.isBlank(childValue)) return 100;
        if (String.isBlank(prefValue)) return 100;
        
        Set<String> childSet = new Set<String>(childValue.split(';'));
        Set<String> prefSet = new Set<String>(prefValue.split(';'));
        
        Integer matches = 0;
        for (String childItem : childSet) {
            if (prefSet.contains(childItem.trim())) {
                matches++;
            }
        }
        
        return (Decimal.valueOf(matches) / childSet.size() * 100);
    }
    
    /**
     * @description Score checkbox matching
     */
    private static Decimal scoreCheckboxMatch(String childValue, String prefValue) {
        Boolean childBool = childValue == 'true';
        Boolean prefBool = prefValue == 'true';
        
        if (!childBool) return 100; // Child doesn't need it
        if (childBool && prefBool) return 100; // Both true
        return 0; // Child needs but family not willing
    }
    
    /**
     * @description Calculate distance using Haversine formula
     */
    private static Decimal calculateDistance(
        Decimal lat1, Decimal lon1, 
        Decimal lat2, Decimal lon2
    ) {
        if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
            return 0;
        }
        
        Decimal R = 3959; // Earth radius in miles
        Decimal dLat = (lat2 - lat1) * Math.PI / 180;
        Decimal dLon = (lon2 - lon1) * Math.PI / 180;
        
        Decimal a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                   Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                   Math.sin(dLon/2) * Math.sin(dLon/2);
        
        Decimal c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        Decimal distance = R * c;
        
        return distance.setScale(2);
    }
    
    /**
     * @description Get distance adjustment for scoring
     */
    private static Decimal getDistanceAdjustment(Decimal miles) {
        if (miles < 10) return 10;
        if (miles < 25) return 0;
        if (miles < 50) return -5;
        return -10;
    }
    
    /**
     * @description Add warning flags to results
     */
    private static void addFlags(ChildMatchResult result, Child__c child, Account family) {
        if (child.BehavioralSupport__c == 'Severe') {
            result.flags.add('⚠ Severe behavioral needs - requires specialized support');
        }
        
        if (child.Is_Sibling_Group__c) {
            result.flags.add('👥 Sibling group of ' + child.Sibling_Group_Size__c + ' children');
        }
        
        if (result.distanceMiles > 50) {
            result.flags.add('📍 Distance: ' + result.distanceMiles.intValue() + ' miles');
        }
        
        if (String.isNotBlank(child.SpecialNeeds__c)) {
            result.flags.add('♿ Child has special needs: ' + child.SpecialNeeds__c);
        }
        
        if (child.TherapyRequired__c == true) {
            result.flags.add('🏥 Therapy required');
        }
    }
    
    /**
     * @description Save match results to database
     */
    private static void saveMatchResults(String preferenceId, List<ChildMatchResult> results) {
        System.debug('Saving ' + results.size() + ' match results to database...');
        List<Match_Result__c> recordsToInsert = new List<Match_Result__c>();
        
        for (ChildMatchResult result : results) {
            Match_Result__c record = new Match_Result__c(
                Preference__c = preferenceId,
                Child__c = result.childId,
                Match_Score__c = result.overallScore,
                Match_Date__c = System.now(),
                Match_Status__c = 'New',
                Match_Reasons__c = JSON.serialize(result.matchReasons),
                Hard_Constraints_Met__c = result.hardConstraintsMet,
                High_Priority_Score__c = result.highPriorityScore,
                Medium_Priority_Score__c = result.mediumPriorityScore,
                Low_Priority_Score__c = result.lowPriorityScore, // NEW - Save Low Priority score
                Distance_Miles__c = result.distanceMiles
            );
            recordsToInsert.add(record);
        }
        
        if (!recordsToInsert.isEmpty()) {
            System.debug('Inserting ' + recordsToInsert.size() + ' Match_Result__c records...');
            insert recordsToInsert;
            System.debug('Insert completed');
            
            // Update results with the inserted IDs
            for (Integer i = 0; i < recordsToInsert.size(); i++) {
                results[i].matchResultId = recordsToInsert[i].Id;
                System.debug('Match Result ' + (i+1) + ' ID: ' + recordsToInsert[i].Id);
            }
        } else {
            System.debug('No records to insert');
        }
    }
    
    /**
     * @description Response wrapper class
     */
    public class MatchingResponse {
        @AuraEnabled
        public Boolean success {get; set;}
        
        @AuraEnabled
        public String message {get; set;}
        
        @AuraEnabled
        public List<ChildMatchResult> results {get; set;}
        
        public MatchingResponse(Boolean success, String message, List<ChildMatchResult> results) {
            System.debug('Creating MatchingResponse: success=' + success + ', message=' + message + ', results count=' + (results != null ? results.size() : 0));
            this.success = success;
            this.message = message;
            this.results = results;
        }
    }
}