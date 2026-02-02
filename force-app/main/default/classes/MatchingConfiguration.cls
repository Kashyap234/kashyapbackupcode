/**
 * @description Wrapper class for matching configuration
 */
public class MatchingConfiguration {
    
    @AuraEnabled
    public String criterionName {get; set;}
    
    @AuraEnabled
    public String priorityLevel {get; set;}
    
    @AuraEnabled
    public Decimal weight {get; set;}
    
    @AuraEnabled
    public Boolean isActive {get; set;}
    
    @AuraEnabled
    public String childFieldAPI {get; set;}
    
    @AuraEnabled
    public String preferenceFieldAPI {get; set;}
    
    @AuraEnabled
    public String matchingLogic {get; set;}
    
    public MatchingConfiguration() {}
    
    public MatchingConfiguration(Matching_Configuration__mdt config) {
        this.criterionName = config.MasterLabel;
        this.priorityLevel = config.Priority_Level__c;
        this.weight = config.Weight_Value__c;
        this.isActive = config.Is_Active__c;
        this.childFieldAPI = config.Matching_Field_API_Name__c;
        this.preferenceFieldAPI = config.Preference_Field_API_Name__c;
        this.matchingLogic = config.Matching_Logic__c;
    }
    
    /**
     * @description Load all active matching configurations
     */
    public static List<MatchingConfiguration> loadConfigurations() {
        List<MatchingConfiguration> configs = new List<MatchingConfiguration>();
        
        for (Matching_Configuration__mdt config : [
            SELECT MasterLabel, Priority_Level__c, Weight_Value__c, 
                   Is_Active__c, Matching_Field_API_Name__c,
                   Preference_Field_API_Name__c, Matching_Logic__c
            FROM Matching_Configuration__mdt
            WHERE Is_Active__c = true
            ORDER BY Priority_Level__c, Weight_Value__c DESC
        ]) {
            configs.add(new MatchingConfiguration(config));
        }
        
        return configs;
    }
}