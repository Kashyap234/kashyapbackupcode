public with sharing class ResumeAnalyzerController {
    
    // Upload resume and initiate Document AI processing
    @AuraEnabled
    public static String uploadResume(String fileName, String base64Data, String contentType) {
        try {
            // Create ContentVersion (file)
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.IsMajorVersion = true;
            insert cv;
            
            // Get ContentDocumentId
            ContentVersion insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            
            // Create Resume record
            Resume__c resume = new Resume__c();
            resume.Resume_File_Name__c = fileName;
            resume.Processing_Status__c = 'Pending';
            insert resume;
            
            // Link ContentDocument to Resume record
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = insertedCV.ContentDocumentId;
            cdl.LinkedEntityId = resume.Id;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            insert cdl;
            
            // Call Document AI processing (async)
            processWithDocumentAI(resume.Id, insertedCV.ContentDocumentId);
            
            return resume.Id;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading resume: ' + e.getMessage());
        }
    }
    
    // Process document with Document AI
    @future(callout=true)
    public static void processWithDocumentAI(Id resumeId, Id contentDocumentId) {
        try {
            // Get the latest ContentVersion
            ContentVersion cv = [
                SELECT VersionData, FileExtension 
                FROM ContentVersion 
                WHERE ContentDocumentId = :contentDocumentId 
                AND IsLatest = true 
                LIMIT 1
            ];
            
            // Call Einstein Document Reader API or Document AI Service
            String extractedText = callDocumentAIService(cv.VersionData, cv.FileExtension);
            
            // Parse extracted text and update Resume record
            parseAndUpdateResume(resumeId, extractedText);
            
        } catch (Exception e) {
            // Update status as failed
            Resume__c resume = new Resume__c(Id = resumeId);
            resume.Processing_Status__c = 'Failed';
            resume.Document_Content__c = 'Error: ' + e.getMessage();
            update resume;
        }
    }
    
    // // Mock Document AI Service Call (Replace with actual Data Cloud Document AI API)
    // private static String callDocumentAIService(Blob fileData, String fileExtension) {
    //     // In real implementation, call Salesforce Data Cloud Document AI API
    //     // This is a mock implementation
        
    //     /*
    //     HttpRequest req = new HttpRequest();
    //     req.setEndpoint('callout:DataCloud_DocumentAI/extract');
    //     req.setMethod('POST');
    //     req.setHeader('Content-Type', 'application/json');
    //     req.setBodyAsBlob(fileData);
        
    //     Http http = new Http();
    //     HttpResponse res = http.send(req);
        
    //     if (res.getStatusCode() == 200) {
    //         return res.getBody();
    //     }
    //     */
        
    //     // Mock extracted text for demo purposes
    //     String mockExtractedText = 'John Doe\n' +
    //         'Email: john.doe@email.com\n' +
    //         'Phone: +1-234-567-8900\n\n' +
    //         'PROFESSIONAL SUMMARY\n' +
    //         'Senior Software Engineer with 8 years of experience in Salesforce development.\n\n' +
    //         'WORK EXPERIENCE\n' +
    //         'Senior Salesforce Developer - Tech Corp (2020-Present)\n' +
    //         '- Led development of custom LWC components\n' +
    //         '- Implemented integrations with external systems\n\n' +
    //         'Salesforce Developer - Digital Solutions (2016-2020)\n' +
    //         '- Developed Apex triggers and classes\n' +
    //         '- Created custom Lightning Web Components\n\n' +
    //         'EDUCATION\n' +
    //         'Bachelor of Science in Computer Science - University Name (2012-2016)\n\n' +
    //         'SKILLS\n' +
    //         'Salesforce, LWC, Apex, JavaScript, REST APIs, SOQL, Data Cloud, Integration\n\n' +
    //         'CERTIFICATIONS\n' +
    //         'Salesforce Certified Platform Developer I\n' +
    //         'Salesforce Certified Platform Developer II';
        
    //     return mockExtractedText;
    // }
    private static String callDocumentAIService(Blob fileData, String fileExtension) {
    try {
        // Prepare request
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:DataCloud_DocumentAI/services/data/v61.0/connect/data-cloud/document-ai/process');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000); // 2 minutes
        
        // Get schema configuration ID (replace with your actual ID)
        String schemaConfigId = '1OfgK00000005sXSAQ'; // From Step 3
        
        // Prepare request body
        Map<String, Object> requestBody = new Map<String, Object>{
            'schemaConfigurationId' => schemaConfigId,
            'documentType' => 'resume',
            'document' => new Map<String, Object>{
                'contentType' => getMimeType(fileExtension),
                'base64EncodedData' => EncodingUtil.base64Encode(fileData)
            }
        };
        
        req.setBody(JSON.serialize(requestBody));
        
        // Make callout
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        System.debug('Response Status: ' + res.getStatusCode());
        System.debug('Response Body: ' + res.getBody());
        
        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            
            // Extract the text from response
            Map<String, Object> extractedData = (Map<String, Object>) response.get('extractedData');
            
            if (extractedData != null) {
                // Build formatted text from extracted fields
                return buildFormattedText(extractedData);
            }
            
            return 'No data extracted';
        } else {
            throw new CalloutException('Document AI API Error: ' + res.getStatusCode() + ' - ' + res.getBody());
        }
        
    } catch (Exception e) {
        System.debug('Error calling Document AI: ' + e.getMessage());
        throw new CalloutException('Document AI processing failed: ' + e.getMessage());
    }
}

// Helper method to get MIME type
private static String getMimeType(String fileExtension) {
    Map<String, String> mimeTypes = new Map<String, String>{
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png'
    };
    
    return mimeTypes.get(fileExtension.toLowerCase());
}

// Helper method to build formatted text from extracted data
private static String buildFormattedText(Map<String, Object> extractedData) {
    String formattedText = '';
    
    // Build a formatted string from extracted fields
    if (extractedData.containsKey('candidate_name')) {
        formattedText += extractedData.get('candidate_name') + '\n';
    }
    
    if (extractedData.containsKey('email')) {
        formattedText += 'Email: ' + extractedData.get('email') + '\n';
    }
    
    if (extractedData.containsKey('phone')) {
        formattedText += 'Phone: ' + extractedData.get('phone') + '\n\n';
    }
    
    if (extractedData.containsKey('professional_summary')) {
        formattedText += 'PROFESSIONAL SUMMARY\n' + extractedData.get('professional_summary') + '\n\n';
    }
    
    if (extractedData.containsKey('work_experience')) {
        formattedText += 'WORK EXPERIENCE\n' + extractedData.get('work_experience') + '\n\n';
    }
    
    if (extractedData.containsKey('education')) {
        formattedText += 'EDUCATION\n' + extractedData.get('education') + '\n\n';
    }
    
    if (extractedData.containsKey('skills')) {
        formattedText += 'SKILLS\n' + extractedData.get('skills') + '\n\n';
    }
    
    if (extractedData.containsKey('certifications')) {
        formattedText += 'CERTIFICATIONS\n' + extractedData.get('certifications');
    }
    
    return formattedText;
}
    
    // Parse extracted text and update resume
    private static void parseAndUpdateResume(Id resumeId, String extractedText) {
        Resume__c resume = new Resume__c(Id = resumeId);
        resume.Document_Content__c = extractedText;
        resume.Processing_Status__c = 'Processing';
        
        // Simple parsing logic (can be enhanced with AI/ML for better extraction)
        Map<String, String> parsedData = parseResumeText(extractedText);
        
        resume.Candidate_Name__c = parsedData.get('name');
        resume.Email__c = parsedData.get('email');
        resume.Phone__c = parsedData.get('phone');
        resume.Skills__c = parsedData.get('skills');
        resume.Work_Experience__c = parsedData.get('experience');
        resume.Education__c = parsedData.get('education');
        resume.Certifications__c = parsedData.get('certifications');
        resume.Total_Experience__c = calculateExperience(parsedData.get('experience'));
        resume.Processing_Status__c = 'Completed';
        
        update resume;
    }
    
    // Parse resume text into structured data
    private static Map<String, String> parseResumeText(String text) {
        Map<String, String> data = new Map<String, String>();
        
        // Extract email using regex
        Pattern emailPattern = Pattern.compile('[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}');
        Matcher emailMatcher = emailPattern.matcher(text);
        if (emailMatcher.find()) {
            data.put('email', emailMatcher.group());
        }
        
        // Extract phone using regex
        Pattern phonePattern = Pattern.compile('\\+?[0-9]{1,3}?[-.\\s]?\\(?[0-9]{1,4}?\\)?[-.\\s]?[0-9]{1,4}[-.\\s]?[0-9]{1,9}');
        Matcher phoneMatcher = phonePattern.matcher(text);
        if (phoneMatcher.find()) {
            data.put('phone', phoneMatcher.group());
        }
        
        // Extract name (first line typically)
        List<String> lines = text.split('\\n');
        if (lines.size() > 0) {
            data.put('name', lines[0].trim());
        }
        
        // Extract sections
        data.put('skills', extractSection(text, 'SKILLS'));
        data.put('experience', extractSection(text, 'WORK EXPERIENCE'));
        data.put('education', extractSection(text, 'EDUCATION'));
        data.put('certifications', extractSection(text, 'CERTIFICATIONS'));
        
        return data;
    }
    
    // Extract section from text
    private static String extractSection(String text, String sectionName) {
        Integer startIdx = text.toUpperCase().indexOf(sectionName);
        if (startIdx == -1) return '';
        
        // Find next section or end of text
        String[] commonSections = new String[]{'PROFESSIONAL SUMMARY', 'WORK EXPERIENCE', 'EDUCATION', 'SKILLS', 'CERTIFICATIONS', 'PROJECTS'};
        Integer endIdx = text.length();
        
        for (String section : commonSections) {
            if (section.equals(sectionName)) continue;
            Integer idx = text.toUpperCase().indexOf(section, startIdx + sectionName.length());
            if (idx != -1 && idx < endIdx) {
                endIdx = idx;
            }
        }
        
        return text.substring(startIdx + sectionName.length(), endIdx).trim();
    }
    
    // Calculate total experience in years
    private static Decimal calculateExperience(String experienceText) {
        // Simple calculation - count year ranges
        Pattern yearPattern = Pattern.compile('(\\d{4})\\s*-\\s*(\\d{4}|Present)');
        Matcher matcher = yearPattern.matcher(experienceText);
        
        Decimal totalYears = 0;
        Integer currentYear = Date.today().year();
        
        while (matcher.find()) {
            Integer startYear = Integer.valueOf(matcher.group(1));
            Integer endYear = matcher.group(2).equals('Present') ? currentYear : Integer.valueOf(matcher.group(2));
            totalYears += (endYear - startYear);
        }
        
        return totalYears;
    }
    
    // Get resume details
    @AuraEnabled(cacheable=true)
    public static Resume__c getResumeDetails(Id resumeId) {
        return [
            SELECT Id, Name, Candidate_Name__c, Email__c, Phone__c, 
                   Total_Experience__c, Current_Company__c, Current_Position__c,
                   Education__c, Skills__c, Work_Experience__c, Certifications__c,
                   Document_Content__c, Processing_Status__c, Resume_File_Name__c,
                   CreatedDate
            FROM Resume__c 
            WHERE Id = :resumeId 
            LIMIT 1
        ];
    }
    
    // Get all resumes
    @AuraEnabled(cacheable=true)
    public static List<Resume__c> getAllResumes() {
        return [
            SELECT Id, Name, Candidate_Name__c, Email__c, Phone__c, 
                   Total_Experience__c, Processing_Status__c, Resume_File_Name__c,
                   CreatedDate
            FROM Resume__c 
            ORDER BY CreatedDate DESC 
            LIMIT 50
        ];
    }
}