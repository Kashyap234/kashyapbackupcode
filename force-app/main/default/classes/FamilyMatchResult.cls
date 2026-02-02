/**
 * @description Wrapper class for individual family match result - REVERSE MATCHING
 * This mirrors ChildMatchResult but for Family matches from a Child's perspective
 */
public class FamilyMatchResult implements Comparable {
    
    @AuraEnabled
    public String familyId {get; set;}
    
    @AuraEnabled
    public String familyName {get; set;}
    
    @AuraEnabled
    public String familyRecordLink {get; set;}
    
    @AuraEnabled
    public Integer familyCapacity {get; set;}
    
    @AuraEnabled
    public String licenseStatus {get; set;}
    
    @AuraEnabled
    public Decimal overallScore {get; set;}
    
    @AuraEnabled
    public Decimal highPriorityScore {get; set;}
    
    @AuraEnabled
    public Decimal mediumPriorityScore {get; set;}
    
    @AuraEnabled
    public Decimal lowPriorityScore {get; set;}
    
    @AuraEnabled
    public Boolean hardConstraintsMet {get; set;}
    
    @AuraEnabled
    public List<String> matchReasons {get; set;}
    
    @AuraEnabled
    public List<String> flags {get; set;}
    
    @AuraEnabled
    public Decimal distanceMiles {get; set;}
    
    @AuraEnabled
    public String preferenceId {get; set;}
    
    @AuraEnabled
    public Map<String, Object> detailedScores {get; set;}
    
    // Match Result record ID for status updates (reverse lookup)
    @AuraEnabled
    public String matchResultId {get; set;}
    
    public FamilyMatchResult() {
        this.matchReasons = new List<String>();
        this.flags = new List<String>();
        this.detailedScores = new Map<String, Object>();
        this.lowPriorityScore = 0;
    }
    
    /**
     * @description Compare method for sorting by score
     */
    public Integer compareTo(Object compareTo) {
        FamilyMatchResult other = (FamilyMatchResult) compareTo;
        
        // Sort by score descending
        if (this.overallScore > other.overallScore) return -1;
        if (this.overallScore < other.overallScore) return 1;
        
        // If scores equal, sort by distance ascending
        if (this.distanceMiles < other.distanceMiles) return -1;
        if (this.distanceMiles > other.distanceMiles) return 1;
        
        return 0;
    }
}