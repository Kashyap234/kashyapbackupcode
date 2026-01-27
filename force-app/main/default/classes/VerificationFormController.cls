public without sharing class VerificationFormController {
    
    public Reference_Person__c referencePerson {get; set;}
    public Verification_Response__c response {get; set;}
    public Boolean isValidToken {get; set;}
    public Boolean isSubmitted {get; set;}
    public Boolean isAlreadyUsed {get; set;}
    
    private String token;
    
    public VerificationFormController() {
        token = ApexPages.currentPage().getParameters().get('token');
        isSubmitted = false;
        isValidToken = false;
        isAlreadyUsed = false;
        
        if (String.isNotBlank(token)) {
            validateToken();
        }
    }
    
    private void validateToken() {
        // Check if token exists and is not expired
        List<Reference_Person__c> refs = [
            SELECT Id, Your_Name__c, Verification_Token__c, 
                   Token_Expiry_Date__c, Verification_Status__c
            FROM Reference_Person__c 
            WHERE Verification_Token__c = :token 
            AND Token_Expiry_Date__c > :System.now()
            LIMIT 1
        ];
        
        if (!refs.isEmpty()) {
            referencePerson = refs[0];
            
            // Check if this token has already been used to submit a response
            List<Verification_Response__c> existingResponses = [
                SELECT Id 
                FROM Verification_Response__c 
                WHERE Verification_Token__c = :token 
                LIMIT 1
            ];
            
            if (!existingResponses.isEmpty()) {
                // Token already used
                isAlreadyUsed = true;
                isValidToken = false;
            } else {
                // Token is valid and not used yet
                isValidToken = true;
                
                // Initialize response object
                response = new Verification_Response__c();
                response.Reference_Person__c = referencePerson.Id;
                response.Verification_Token__c = token;
            }
        }
    }
    
    public PageReference submitVerification() {
        try {
            // Double-check token hasn't been used (in case of multiple simultaneous submissions)
            List<Verification_Response__c> existingResponses = [
                SELECT Id 
                FROM Verification_Response__c 
                WHERE Verification_Token__c = :token 
                LIMIT 1
            ];
            
            if (!existingResponses.isEmpty()) {
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.ERROR, 
                    'This verification link has already been used. Each link can only be used once.'
                ));
                return null;
            }
            
            // Capture IP address (if needed)
            response.Referee_IP_Address__c = ApexPages.currentPage()
                .getHeaders().get('X-Salesforce-SIP');
            
            insert response;
            
            // Update reference person status
            referencePerson.Verification_Status__c = 'Completed';
            update referencePerson;
            
            isSubmitted = true;
            
        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, 
                'Error submitting verification: ' + e.getMessage()
            ));
        }
        
        return null;
    }
}