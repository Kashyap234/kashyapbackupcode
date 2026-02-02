/**
 * @description Service class for reverse matching - finding families for a child
 * Uses the same scoring logic as ChildMatchingService but in reverse
 */
public with sharing class FamilyMatchingService {
    
    private static final Integer MAX_RESULTS = 4;
    private static final Decimal PASSING_SCORE = 50.0;
    
    /**
     * @description Main entry point for reverse matching (Child to Families)
     */
    @AuraEnabled
    public static MatchingResponse runReverseMatching(String childId) {
        System.debug('=== START runReverseMatching ===');
        System.debug('childId: ' + childId);
        
        try {
            System.debug('Step 1: Loading child...');
            Child__c child = loadChild(childId);
            System.debug('Child loaded: ' + child.Name + ', Jurisdiction: ' + child.Jurisdiction__c);
            
            System.debug('Step 2: Loading matching configurations...');
            List<MatchingConfiguration> configs = MatchingConfiguration.loadConfigurations();
            System.debug('Loaded ' + configs.size() + ' active configurations');
            
            System.debug('Step 3: Loading eligible families with preferences...');
            List<PreferenceWrapper> preferenceWrappers = loadEligibleFamiliesWithPreferences(child.Jurisdiction__c);
            System.debug('Found ' + preferenceWrappers.size() + ' families with active preferences');
            
            System.debug('Step 4: Scoring families...');
            List<FamilyMatchResult> results = new List<FamilyMatchResult>();
            Integer familyCounter = 0;
            
            for (PreferenceWrapper wrapper : preferenceWrappers) {
                familyCounter++;
                System.debug('Scoring family ' + familyCounter + '/' + preferenceWrappers.size() + ': ' + wrapper.family.Name);
                
                FamilyMatchResult result = scoreFamily(child, wrapper.preference, wrapper.family, configs);
                System.debug('Family ' + wrapper.family.Name + ' score: ' + result.overallScore + ', Hard constraints met: ' + result.hardConstraintsMet);
                
                if (result.hardConstraintsMet && result.overallScore >= PASSING_SCORE) {
                    results.add(result);
                    System.debug('Added to results (Score: ' + result.overallScore + ')');
                } else {
                    System.debug('Not added - Score: ' + result.overallScore + ', Constraints: ' + result.hardConstraintsMet);
                }
            }
            
            System.debug('Step 5: Sorting results...');
            results.sort();
            System.debug('Total qualified matches: ' + results.size());
            
            System.debug('Step 6: Selecting top results...');
            List<FamilyMatchResult> topResults = new List<FamilyMatchResult>();
            for (Integer i = 0; i < Math.min(MAX_RESULTS, results.size()); i++) {
                topResults.add(results[i]);
                System.debug('Top match #' + (i+1) + ': ' + results[i].familyName + ' (Score: ' + results[i].overallScore + ')');
            }
            
            System.debug('Step 7: Creating response...');
            MatchingResponse response = new MatchingResponse(true, 'Reverse matching completed successfully', topResults);
            System.debug('Response created - Success: ' + response.success + ', Results count: ' + (response.results != null ? response.results.size() : 0));
            
            System.debug('=== END runReverseMatching SUCCESS ===');
            return response;
            
        } catch (Exception e) {
            System.debug('=== ERROR in runReverseMatching ===');
            System.debug('Error Type: ' + e.getTypeName());
            System.debug('Error Message: ' + e.getMessage());
            System.debug('Line Number: ' + e.getLineNumber());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            System.debug('=== END runReverseMatching ERROR ===');
            
            return new MatchingResponse(false, 'Error: ' + e.getMessage(), null);
        }
    }
    
    /**
     * @description Load child with all related fields
     */
    private static Child__c loadChild(String childId) {
        System.debug('Loading child with ID: ' + childId);
        Child__c child = [
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
            WHERE Id = :childId
            LIMIT 1
        ];
        System.debug('Child query completed');
        return child;
    }
    
    /**
     * @description Load all eligible families with their preferences
     */
    private static List<PreferenceWrapper> loadEligibleFamiliesWithPreferences(String jurisdiction) {
        System.debug('Loading families with preferences for jurisdiction: ' + jurisdiction);
        
        List<PreferenceWrapper> wrappers = new List<PreferenceWrapper>();
        
        // Query all active preferences with their associated families
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
        
        System.debug('Found ' + preferences.size() + ' active preferences with qualified families');
        
        for (Preference__c pref : preferences) {
            PreferenceWrapper wrapper = new PreferenceWrapper();
            wrapper.preference = pref;
            wrapper.family = pref.Family__r;
            wrappers.add(wrapper);
        }
        
        return wrappers;
    }
    
    /**
     * @description Score a single family with detailed breakdown
     */
    private static FamilyMatchResult scoreFamily(
        Child__c child,
        Preference__c pref,
        Account family,
        List<MatchingConfiguration> configs
    ) {
        System.debug('--- Scoring family: ' + family.Name + ' ---');
        FamilyMatchResult result = new FamilyMatchResult();
        
        // Basic info
        result.familyId = family.Id;
        result.familyName = family.Name;
        result.familyRecordLink = '/' + family.Id;
        result.familyCapacity = Integer.valueOf(family.Available_Capacity__c);
        result.licenseStatus = family.License_Status__c;
        result.preferenceId = pref.Id;
        
        System.debug('Family basic info: Capacity=' + result.familyCapacity + ', License=' + result.licenseStatus);
        
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
            System.debug('Family failed hard constraints, returning early');
            return result;
        }
        
        // Calculate scores with detailed breakdown (same logic as child matching)
        System.debug('Calculating criterion scores...');
        Decimal highPriorityTotal = 0;
        Decimal highPriorityMax = 0;
        Decimal mediumPriorityTotal = 0;
        Decimal mediumPriorityMax = 0;
        Decimal lowPriorityTotal = 0;
        Decimal lowPriorityMax = 0;
        
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
            scoreDetail.put('score', score.setScale(2));
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
            } else if (config.priorityLevel == 'Low') {
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
        result.lowPriorityScore = lowPriorityMax > 0 ? 
            (lowPriorityTotal / lowPriorityMax * 100).setScale(2) : 0;
        
        System.debug('High Priority Score: ' + result.highPriorityScore);
        System.debug('Medium Priority Score: ' + result.mediumPriorityScore);
        System.debug('Low Priority Score: ' + result.lowPriorityScore);
        
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
        addFlags(result, child, family, pref);
        System.debug('Flags added: ' + result.flags.size());
        
        System.debug('--- End scoring family ---');
        return result;
    }
    
    /**
     * @description Check if family passes child's hard constraints
     */
    private static Boolean checkHardConstraints(Child__c child, Account family) {
        System.debug('Checking hard constraints for family: ' + family.Name);
        
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
     * @description Calculate score for a single criterion (same as ChildMatchingService)
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
    private static void addFlags(FamilyMatchResult result, Child__c child, Account family, Preference__c pref) {
        if (child.BehavioralSupport__c == 'Severe' && pref.Behavioral_Support_Willingness_If_any__c != 'Severe') {
            result.flags.add('⚠ Child has severe behavioral needs');
        }
        
        if (child.Is_Sibling_Group__c) {
            result.flags.add('👥 Child is part of sibling group of ' + child.Sibling_Group_Size__c);
        }
        
        if (result.distanceMiles > 50) {
            result.flags.add('📍 Distance: ' + result.distanceMiles.intValue() + ' miles');
        }
        
        if (String.isNotBlank(child.SpecialNeeds__c)) {
            result.flags.add('♿ Child has special needs: ' + child.SpecialNeeds__c);
        }
        
        if (child.TherapyRequired__c == true) {
            result.flags.add('🏥 Child requires therapy');
        }
        
        if (family.Available_Capacity__c <= 1) {
            result.flags.add('📊 Family has limited capacity (' + family.Available_Capacity__c.intValue() + ')');
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
        public List<FamilyMatchResult> results {get; set;}
        
        public MatchingResponse(Boolean success, String message, List<FamilyMatchResult> results) {
            System.debug('Creating MatchingResponse: success=' + success + ', message=' + message + ', results count=' + (results != null ? results.size() : 0));
            this.success = success;
            this.message = message;
            this.results = results;
        }
    }
    
    /**
     * @description Wrapper class to hold Preference and Family together
     */
    private class PreferenceWrapper {
        public Preference__c preference {get; set;}
        public Account family {get; set;}
    }
}