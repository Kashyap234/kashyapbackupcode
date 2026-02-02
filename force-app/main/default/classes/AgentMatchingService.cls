public with sharing class AgentMatchingService {

    // INPUT: Only the identifier is needed now
    public class MatchingRequest {
        @InvocableVariable(label='Record Identifier' description='The Name (e.g., C-001, PID-005) or ID of the record.' required=true)
        public String recordIdentifier;
    }

    // OUTPUT: Same as before
    public class AgentMatchSummary {
        @InvocableVariable(label='Match Summary' description='Natural language summary of results')
        public String matchSummary;
        @InvocableVariable(label='Top Match ID')
        public String topMatchId;
    }

    @InvocableMethod(label='Run Placement Matching' description='Auto-detects if the input is a Child or Preference and finds matches.')
    public static List<AgentMatchSummary> runAgentMatching(List<MatchingRequest> requests) {
        List<AgentMatchSummary> summaries = new List<AgentMatchSummary>();
        
        for (MatchingRequest req : requests) {
            AgentMatchSummary summary = new AgentMatchSummary();
            String input = req.recordIdentifier;
            
            // LOGIC: Auto-Detect based on prefix or ID
            if (isChildRecord(input)) {
                // It's a Child -> Find Families
                String resolvedId = resolveChildId(input);
                if (resolvedId != null) {
                    FamilyMatchingService.MatchingResponse response = FamilyMatchingService.runReverseMatching(resolvedId);
                    summary.matchSummary = formatFamilyResultsForAgent(response);
                    if (response.results != null && !response.results.isEmpty()) summary.topMatchId = response.results[0].familyId;
                } else {
                    summary.matchSummary = 'I detected a Child ID format (' + input + ') but could not find the record in the database.';
                }
            } 
            else if (isPreferenceRecord(input)) {
                // It's a Preference -> Find Children
                String resolvedId = resolvePreferenceId(input);
                if (resolvedId != null) {
                    ChildMatchingService.MatchingResponse response = ChildMatchingService.runMatching(resolvedId);
                    summary.matchSummary = formatChildResultsForAgent(response);
                    if (response.results != null && !response.results.isEmpty()) summary.topMatchId = response.results[0].childId;
                } else {
                    summary.matchSummary = 'I detected a Preference ID format (' + input + ') but could not find the record.';
                }
            } 
            else {
                // Fallback: Try to find ANY record that matches
                summary.matchSummary = 'I could not determine if "' + input + '" is a Child (C-xxxx) or Preference (PID-xxxx). Please check the format.';
            }
            
            summaries.add(summary);
        }
        return summaries;
    }

    // --- HELPER: Detection Logic ---
    
    private static Boolean isChildRecord(String input) {
        // Check for 'C-' prefix or if it's a Salesforce ID that points to Child__c
        if (input.startsWithIgnoreCase('C-')) return true;
        if (input instanceof Id && ((Id)input).getSobjectType() == Child__c.SObjectType) return true;
        return false;
    }

    private static Boolean isPreferenceRecord(String input) {
        // Check for 'PID-' prefix or if it's a Salesforce ID that points to Preference__c
        if (input.startsWithIgnoreCase('PID-')) return true;
        if (input instanceof Id && ((Id)input).getSobjectType() == Preference__c.SObjectType) return true;
        return false;
    }

    private static String resolveChildId(String input) {
        try {
            Child__c c = [SELECT Id FROM Child__c WHERE Name = :input OR Id = :input LIMIT 1];
            return c.Id;
        } catch(Exception e) { return null; }
    }

    private static String resolvePreferenceId(String input) {
        try {
            Preference__c p = [SELECT Id FROM Preference__c WHERE Name = :input OR Id = :input LIMIT 1];
            return p.Id;
        } catch(Exception e) { return null; }
    }

    // --- HELPER: Formatting ---

    private static String formatChildResultsForAgent(ChildMatchingService.MatchingResponse response) {
         if (!response.success || response.results == null || response.results.isEmpty()) return 'No matches found.';
         String text = 'Found ' + response.results.size() + ' matches. \n';
         for (ChildMatchResult result : response.results) {
             text += '- Child: ' + result.childName + ' (Age: ' + result.childAge + '). Score: ' + result.overallScore + '%. ';
             if (result.matchReasons != null && !result.matchReasons.isEmpty()) text += 'Reasons: ' + String.join(result.matchReasons, ', ') + '. ';
             if (result.flags != null && !result.flags.isEmpty()) text += 'Flags: ' + String.join(result.flags, ', ') + '.';
             text += '\n';
         }
         return text;
    }

    private static String formatFamilyResultsForAgent(FamilyMatchingService.MatchingResponse response) {
         if (!response.success || response.results == null || response.results.isEmpty()) return 'No matches found.';
         String text = 'Found ' + response.results.size() + ' matches. \n';
         for (FamilyMatchResult result : response.results) {
             text += '- Family: ' + result.familyName + '. Score: ' + result.overallScore + '%. Capacity: ' + result.familyCapacity + '. ';
             if (result.matchReasons != null && !result.matchReasons.isEmpty()) text += 'Reasons: ' + String.join(result.matchReasons, ', ') + '. ';
             text += '\n';
         }
         return text;
    }
}