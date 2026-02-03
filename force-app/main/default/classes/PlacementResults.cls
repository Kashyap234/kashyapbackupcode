@JsonAccess(serializable='always' deserializable='always')
public class PlacementResults {

    @AuraEnabled
    public List<MatchCard> matches;

    // Inner class defining the structure of a single card
    public class MatchCard {
        @AuraEnabled public String recordId;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String details; // Keeps the summary string
        @AuraEnabled public Integer score;
        
        // NEW: List to hold detailed field-level comparisons for the Bot to read
        @AuraEnabled public List<CriterionDetail> criteria;
    }

    // NEW: Wrapper for individual field score and value comparison
    public class CriterionDetail {
        @AuraEnabled public String fieldName;      // e.g., "Age", "Religion"
        @AuraEnabled public String childValue;     // e.g., "10"
        @AuraEnabled public String preferenceValue;// e.g., "0-12"
        @AuraEnabled public Decimal score;         // e.g., 100.0
    }
}