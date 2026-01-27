public class ReferenceVerificationEmailService {
    
    @InvocableMethod(label='Send Verification Email')
    public static void sendVerificationEmail(List<Id> referencePersonIds) {
        List<Reference_Person__c> refPersons = [
            SELECT Id, Referee_Email__c, Referee_Full_Name__c, 
                   Your_Name__c, Verification_Token__c
            FROM Reference_Person__c 
            WHERE Id IN :referencePersonIds
        ];
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        for (Reference_Person__c ref : refPersons) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[] { ref.Referee_Email__c });
            email.setSubject('Reference Verification Request from ' + ref.Your_Name__c);
            
            // Use System.URL.getOrgDomainUrl() instead of deprecated method
            String baseUrl = System.URL.getOrgDomainUrl().toExternalForm();
            String verificationLink = baseUrl + 
                '/apex/VerificationFormPage?token=' + ref.Verification_Token__c;
            
            String body = 'Dear ' + ref.Referee_Full_Name__c + ',\n\n';
            body += ref.Your_Name__c + ' has requested you to provide a reference verification.\n\n';
            body += 'Please click the link below to fill out the verification form:\n';
            body += verificationLink + '\n\n';
            body += 'This link will expire in 30 days.\n\n';
            body += 'Thank you for your time.';
            
            email.setPlainTextBody(body);
            emails.add(email);
            
            // Update status
            ref.Verification_Status__c = 'Email Sent';
        }
        
        Messaging.sendEmail(emails);
        update refPersons;
    }
}