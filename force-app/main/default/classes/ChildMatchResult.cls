/**
 * @description Wrapper class for individual child match result - ENHANCED VERSION
 * Includes matchResultId for tracking saved records
 * UPDATED: Added lowPriorityScore to support Low Priority criteria
 */
public class ChildMatchResult implements Comparable {
    
    @AuraEnabled
    public String childId {get; set;}
    
    @AuraEnabled
    public String childName {get; set;}
    
    @AuraEnabled
    public String childRecordLink {get; set;}
    
    @AuraEnabled
    public Integer childAge {get; set;}
    
    @AuraEnabled
    public String childGender {get; set;}
    
    @AuraEnabled
    public Decimal overallScore {get; set;}
    
    @AuraEnabled
    public Decimal highPriorityScore {get; set;}
    
    @AuraEnabled
    public Decimal mediumPriorityScore {get; set;}
    
    @AuraEnabled
    public Decimal lowPriorityScore {get; set;} // NEW - Added for Low Priority criteria
    
    @AuraEnabled
    public Boolean hardConstraintsMet {get; set;}
    
    @AuraEnabled
    public List<String> matchReasons {get; set;}
    
    @AuraEnabled
    public List<String> flags {get; set;}
    
    @AuraEnabled
    public Decimal distanceMiles {get; set;}
    
    @AuraEnabled
    public String familyName {get; set;}
    
    @AuraEnabled
    public Integer familyCapacity {get; set;}
    
    @AuraEnabled
    public Map<String, Object> detailedScores {get; set;}
    
    // Match Result record ID for status updates
    @AuraEnabled
    public String matchResultId {get; set;}
    
    public ChildMatchResult() {
        this.matchReasons = new List<String>();
        this.flags = new List<String>();
        this.detailedScores = new Map<String, Object>();
        this.lowPriorityScore = 0; // Initialize to 0
    }
    
    /**
     * @description Compare method for sorting by score
     */
    public Integer compareTo(Object compareTo) {
        ChildMatchResult other = (ChildMatchResult) compareTo;
        
        // Sort by score descending
        if (this.overallScore > other.overallScore) return -1;
        if (this.overallScore < other.overallScore) return 1;
        
        // If scores equal, sort by distance ascending
        if (this.distanceMiles < other.distanceMiles) return -1;
        if (this.distanceMiles > other.distanceMiles) return 1;
        
        return 0;
    }
}