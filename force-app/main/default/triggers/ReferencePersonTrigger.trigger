trigger ReferencePersonTrigger on Reference_Person__c (before insert) {
    for (Reference_Person__c ref : Trigger.new) {
        if (ref.Verification_Token__c == null) {
            // Generate unique token
            ref.Verification_Token__c = generateToken();
            // Set expiry date (30 days from now)
            ref.Token_Expiry_Date__c = System.now().addDays(30);
            ref.Verification_Status__c = 'Pending';
        }
    }
    
    private static String generateToken() {
        String timestamp = String.valueOf(System.currentTimeMillis());
        String random = String.valueOf(Math.random()).substring(2, 8);
        Blob hash = Crypto.generateDigest('SHA-256', 
            Blob.valueOf(timestamp + random));
        return EncodingUtil.convertToHex(hash).substring(0, 32);
    }
}