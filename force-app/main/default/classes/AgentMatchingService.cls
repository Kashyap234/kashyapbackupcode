public with sharing class AgentMatchingService {

    // INPUT
    public class MatchingRequest {
        @InvocableVariable(label='Record Identifier' required=true)
        public String recordIdentifier;
    }

    // OUTPUT
    public class MatchOutput {
        @InvocableVariable(label='Placement Results')
        public PlacementResults results;
    }

    @InvocableMethod(label='Run Placement Matching' description='Finds matches and returns them for Custom Lightning UI')
    public static List<MatchOutput> runAgentMatching(List<MatchingRequest> requests) {
        List<MatchOutput> outputs = new List<MatchOutput>();
        
        for (MatchingRequest req : requests) {
            MatchOutput output = new MatchOutput();
            PlacementResults resultContainer = new PlacementResults();
            resultContainer.matches = new List<PlacementResults.MatchCard>();
            
            String input = (req.recordIdentifier != null) ? req.recordIdentifier.trim() : '';
            
            // Logic to fetch and map data
            if (isChildRecord(input)) {
                String childId = resolveChildId(input);
                if (childId != null) {
                    FamilyMatchingService.MatchingResponse response = FamilyMatchingService.runReverseMatching(childId);
                    if (response.success && response.results != null) {
                        resultContainer.matches = mapFamiliesToCards(response.results);
                    }
                }
            } 
            else if (isPreferenceRecord(input)) {
                String prefId = resolvePreferenceId(input);
                if (prefId != null) {
                    ChildMatchingService.MatchingResponse response = ChildMatchingService.runMatching(prefId);
                    if (response.success && response.results != null) {
                        resultContainer.matches = mapChildrenToCards(response.results);
                    }
                }
            }
            
            output.results = resultContainer;
            outputs.add(output);
        }
        return outputs;
    }

    // --- MAPPERS ---
    private static List<PlacementResults.MatchCard> mapFamiliesToCards(List<FamilyMatchResult> results) {
        List<PlacementResults.MatchCard> cards = new List<PlacementResults.MatchCard>();
        Integer count = 0;
        for (FamilyMatchResult res : results) {
            if (count >= 3) break; 
            PlacementResults.MatchCard card = new PlacementResults.MatchCard();
            card.recordId = res.familyId;
            card.title = res.familyName;
            card.subtitle = 'Capacity: ' + res.familyCapacity;
            card.score = Integer.valueOf(res.overallScore);
            card.details = (res.matchReasons != null) ? String.join(res.matchReasons, ', ') : '';
            
            // NEW: Map detailed scores
            card.criteria = mapCriteriaDetails(res.detailedScores);
            
            cards.add(card);
            count++;
        }
        return cards;
    }

    private static List<PlacementResults.MatchCard> mapChildrenToCards(List<ChildMatchResult> results) {
        List<PlacementResults.MatchCard> cards = new List<PlacementResults.MatchCard>();
        Integer count = 0;
        for (ChildMatchResult res : results) {
            if (count >= 3) break;
            PlacementResults.MatchCard card = new PlacementResults.MatchCard();
            card.recordId = res.childId;
            card.title = res.childName;
            card.subtitle = 'Age: ' + res.childAge;
            card.score = Integer.valueOf(res.overallScore);
            card.details = (res.matchReasons != null) ? String.join(res.matchReasons, ', ') : '';
            
            // NEW: Map detailed scores
            card.criteria = mapCriteriaDetails(res.detailedScores);
            
            cards.add(card);
            count++;
        }
        return cards;
    }

    // NEW: Helper to extract map data into List<CriterionDetail>
    private static List<PlacementResults.CriterionDetail> mapCriteriaDetails(Map<String, Object> detailedScores) {
        List<PlacementResults.CriterionDetail> detailsList = new List<PlacementResults.CriterionDetail>();
        
        if (detailedScores != null) {
            for (Object obj : detailedScores.values()) {
                Map<String, Object> scoreMap = (Map<String, Object>)obj;
                
                PlacementResults.CriterionDetail detail = new PlacementResults.CriterionDetail();
                detail.fieldName = (String)scoreMap.get('criterionName');
                detail.childValue = String.valueOf(scoreMap.get('childValue'));
                detail.preferenceValue = String.valueOf(scoreMap.get('preferenceValue'));
                detail.score = (Decimal)scoreMap.get('score');
                
                detailsList.add(detail);
            }
        }
        return detailsList;
    }

    // --- HELPERS (Keep existing logic) ---
    private static Boolean isChildRecord(String input) { return input.startsWithIgnoreCase('C-') || (input instanceof Id && ((Id)input).getSobjectType() == Child__c.SObjectType); }
    private static Boolean isPreferenceRecord(String input) { return input.startsWithIgnoreCase('PID-') || (input instanceof Id && ((Id)input).getSobjectType() == Preference__c.SObjectType); }
    private static String resolveChildId(String input) { try { return [SELECT Id FROM Child__c WHERE Name = :input OR Id = :input LIMIT 1].Id; } catch(Exception e) { return null; } }
    private static String resolvePreferenceId(String input) { try { return [SELECT Id FROM Preference__c WHERE Name = :input OR Id = :input LIMIT 1].Id; } catch(Exception e) { return null; } }
}