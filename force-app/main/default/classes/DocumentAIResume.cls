public without sharing class DocumentAIResume {
    
    // Request wrapper for Invocable method
    public class Request {
        @InvocableVariable(required=true)
        public String Name;
    }

    // Response wrapper with all resume fields
    public class ResumeResponse {
        @InvocableVariable public String candidateName;
        @InvocableVariable public String email;
        @InvocableVariable public String phone;
        @InvocableVariable public String linkedin;
        @InvocableVariable public String github;
        @InvocableVariable public String trailhead;
        @InvocableVariable public String professionalSummary;
        @InvocableVariable public String workExperience;
        @InvocableVariable public String education;
        @InvocableVariable public String skills;
        @InvocableVariable public String projects;
        @InvocableVariable public String certifications;
        @InvocableVariable public Decimal totalExperience;
    }

    // Constants
    private static final String IDP_CONFIG_NAME = 'Resume_Extraction_Schema';
    private static final String API_VERSION = 'v64.0';
    private static final Integer MAX_FIELD_LENGTH = 32000;
    
    @InvocableMethod(label='Process Resume PDF' description='Extract resume data using Document AI')
    public static List<ResumeResponse> requestDocumentAI(List<Request> requests) {
        List<ResumeResponse> results = new List<ResumeResponse>();

        if (requests == null || requests.isEmpty()) {
            throw new IllegalArgumentException('Request list cannot be null or empty');
        }

        String resumeName = requests[0].Name;
        
        try {
            // Get Resume record with error handling
            Resume__c resumeRecord = getResumeRecord(resumeName);
            
            // Get file content with validation
            ContentVersion fileToProcess = getFileContent(resumeRecord.file_id__c);
            
            // Convert to base64
            String fileDataAsBase64 = EncodingUtil.base64Encode(fileToProcess.VersionData);
            
            // Make API callout
            HttpResponse res = callDocumentAIAPI(fileDataAsBase64);
            
            // Process successful response
            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                ResumeResponse response = parseDocumentAIResponse(res.getBody());
                updateResumeRecord(resumeRecord.Id, response);
                results.add(response);
            } else {
                handleAPIError(resumeRecord.Id, res);
            }
            
        } catch(Exception e) {
            System.debug(LoggingLevel.ERROR, 'Exception in requestDocumentAI: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Failed to process resume: ' + e.getMessage());
        }
        
        return results;
    }

    // Get Resume record with error handling
    private static Resume__c getResumeRecord(String resumeName) {
        List<Resume__c> resumes = [
            SELECT Id, file_id__c, Name 
            FROM Resume__c 
            WHERE Name = :resumeName 
            LIMIT 1
        ];
        
        if (resumes.isEmpty()) {
            throw new QueryException('Resume record not found: ' + resumeName);
        }
        
        return resumes[0];
    }

    // Get file content with validation
    private static ContentVersion getFileContent(Id contentDocumentId) {
        List<ContentVersion> files = [
            SELECT VersionData, FileType, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        
        if (files.isEmpty()) {
            throw new QueryException('File not found for ContentDocumentId: ' + contentDocumentId);
        }
        
        return files[0];
    }

    // Make Document AI API callout
    private static HttpResponse callDocumentAIAPI(String fileDataAsBase64) {
        HttpRequest req = new HttpRequest();
        
        // Build endpoint URL
        String endpoint = System.Url.getOrgDomainUrl().toExternalForm() +
                          '/services/data/' + API_VERSION + '/ssot/document-processing/actions/extract-data?htmlEncode=false';
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setTimeout(120000); // 120 seconds timeout
        
        // Set headers
        String accessToken = OAuthTokenUtil.getAccessToken(); 
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json;charset=UTF-8');

        // Build request body
        Map<String, Object> requestBodyMap = new Map<String, Object>{
            'idpConfigurationIdOrName' => IDP_CONFIG_NAME,
            'files' => new List<Object>{ 
                new Map<String, Object>{
                    'mimeType' => 'application/pdf',
                    'data' => fileDataAsBase64
                }
            }
        };

        req.setBody(JSON.serialize(requestBodyMap, true));

        // Execute callout
        Http http = new Http();
        return http.send(req);
    }

    // Parse Document AI API response
    private static ResumeResponse parseDocumentAIResponse(String responseBody) {
        try {
            // Parse outer JSON
            Map<String, Object> outerJson = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> dataList = (List<Object>) outerJson.get('data');
            
            if (dataList == null || dataList.isEmpty()) {
                throw new JSONException('No data returned from Document AI API');
            }
            
            Map<String, Object> firstData = (Map<String, Object>) dataList[0];
            
            // Parse inner JSON (actual resume data)
            String encodedJson = (String) firstData.get('data');
            String decodedJson = cleanJsonString(encodedJson);
            
            Map<String, Object> finalJson = (Map<String, Object>) JSON.deserializeUntyped(decodedJson);
            System.debug('Parsed JSON: ' + JSON.serializePretty(finalJson));
            
            // Map to response object
            return mapJsonToResponse(finalJson);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error parsing response: ' + e.getMessage());
            throw new JSONException('Failed to parse Document AI response: ' + e.getMessage());
        }
    }

    // Clean JSON string from HTML entities
    private static String cleanJsonString(String encodedJson) {
        return encodedJson
            .replace('&quot;', '"')
            .replace('&#92;', '\\')
            .replace('&amp;', '&')
            .replace('&lt;', '<')
            .replace('&gt;', '>');
    }

    // Map JSON to ResumeResponse object
    private static ResumeResponse mapJsonToResponse(Map<String, Object> jsonMap) {
        ResumeResponse response = new ResumeResponse();
        
        // Basic info
        response.candidateName = getFieldValue(jsonMap, 'name');
        
        // Contact details (nested in 'contact' array)
        response.email = getComplexValue(jsonMap, 'contact', 'email');
        response.phone = getComplexValue(jsonMap, 'contact', 'phone');
        response.linkedin = getComplexValue(jsonMap, 'contact', 'linkedin');
        response.github = getComplexValue(jsonMap, 'contact', 'github');
        response.trailhead = getComplexValue(jsonMap, 'contact', 'trailhead');
        
        // Professional summary
        response.professionalSummary = getFieldValue(jsonMap, 'professional_summary');
        
        // Array-based fields (formatted as text blocks)
        response.education = formatEducation(jsonMap);
        response.workExperience = formatExperience(jsonMap);
        response.projects = formatProjects(jsonMap);
        response.skills = formatSkills(jsonMap);
        response.certifications = formatCertifications(jsonMap);
        
        // Calculate total experience
        response.totalExperience = calculateTotalExperience(jsonMap);
        
        return response;
    }

    // Helper: Get simple field value
    private static String getFieldValue(Map<String, Object> jsonMap, String fieldName) {
        try {
            if (jsonMap.containsKey(fieldName)) {
                Object fieldObj = jsonMap.get(fieldName);
                if (fieldObj instanceof Map<String, Object>) {
                    Map<String, Object> valMap = (Map<String, Object>) fieldObj;
                    Object value = valMap.get('value');
                    return value != null ? String.valueOf(value) : null;
                }
            }
        } catch (Exception e) {
            System.debug('Error getting field ' + fieldName + ': ' + e.getMessage());
        }
        return null;
    }

    // Helper: Get nested field value (e.g., contact.email)
    private static String getComplexValue(Map<String, Object> jsonMap, String parentField, String childField) {
        try {
            if (jsonMap.containsKey(parentField)) {
                Map<String, Object> parentObj = (Map<String, Object>) jsonMap.get(parentField);
                Object valObj = parentObj.get('value');
                
                if (valObj instanceof List<Object>) {
                    List<Object> listData = (List<Object>) valObj;
                    if (!listData.isEmpty()) {
                        Map<String, Object> firstItem = (Map<String, Object>) listData[0];
                        Map<String, Object> valueMap = (Map<String, Object>) firstItem.get('value');
                        
                        if (valueMap != null && valueMap.containsKey(childField)) {
                            Map<String, Object> fieldObj = (Map<String, Object>) valueMap.get(childField);
                            Object value = fieldObj.get('value');
                            return value != null ? String.valueOf(value) : null;
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting complex value ' + parentField + '.' + childField + ': ' + e.getMessage());
        }
        return null;
    }

    // Format Education section
    private static String formatEducation(Map<String, Object> jsonMap) {
        List<String> lines = new List<String>();
        List<Map<String, Object>> items = extractList(jsonMap, 'education');
        
        if (items == null || items.isEmpty()) return null;

        for (Map<String, Object> item : items) {
            String degree = getStringValue(item, 'degree');
            String university = getStringValue(item, 'university');
            String duration = getStringValue(item, 'duration');
            String cgpa = getStringValue(item, 'cgpa');
            
            lines.add('🎓 ' + (degree != null ? degree : 'Degree'));
            if (university != null) lines.add('   ' + university);
            if (duration != null) lines.add('   ' + duration);
            if (cgpa != null) lines.add('   CGPA: ' + cgpa);
            lines.add('');
        }
        
        return truncateField(String.join(lines, '\n'));
    }

    // Format Work Experience section
    private static String formatExperience(Map<String, Object> jsonMap) {
        List<String> lines = new List<String>();
        List<Map<String, Object>> items = extractList(jsonMap, 'experience');
        
        if (items == null || items.isEmpty()) return null;

        for (Map<String, Object> item : items) {
            String role = getStringValue(item, 'role');
            String company = getStringValue(item, 'company');
            String duration = getStringValue(item, 'duration');
            String responsibilities = getStringValue(item, 'responsibilities');

            lines.add('💼 ' + (role != null ? role : 'Role') + ' at ' + (company != null ? company : 'Company'));
            
            if (duration != null) lines.add('   📅 ' + duration);
            
            if (responsibilities != null) {
                String[] respList = responsibilities.split('\n');
                for (String resp : respList) {
                    if (String.isNotBlank(resp)) {
                        lines.add('   • ' + resp.trim());
                    }
                }
            }
            lines.add('');
        }
        
        return truncateField(String.join(lines, '\n'));
    }

    // Format Projects section
    private static String formatProjects(Map<String, Object> jsonMap) {
        List<String> lines = new List<String>();
        List<Map<String, Object>> items = extractList(jsonMap, 'projects');
        
        if (items == null || items.isEmpty()) return null;

        for (Map<String, Object> item : items) {
            String name = getStringValue(item, 'name');
            String technologies = getStringValue(item, 'technologies');
            String description = getStringValue(item, 'description');

            lines.add('🚀 ' + (name != null ? name : 'Project'));
            if (technologies != null) lines.add('   🔧 ' + technologies);
            if (description != null) lines.add('   ' + description);
            lines.add('');
        }
        
        return truncateField(String.join(lines, '\n'));
    }

    // Format Skills section
    private static String formatSkills(Map<String, Object> jsonMap) {
        List<String> lines = new List<String>();
        List<Map<String, Object>> items = extractList(jsonMap, 'technical_skills');
        
        if (items == null || items.isEmpty()) return null;

        for (Map<String, Object> item : items) {
            String category = getStringValue(item, 'category');
            String skillList = getStringValue(item, 'skills');
            
            if (category != null && skillList != null) {
                lines.add('▪ ' + category + ': ' + skillList);
            } else if (skillList != null) {
                lines.add('▪ ' + skillList);
            }
        }
        
        return truncateField(String.join(lines, '\n'));
    }

    // Format Certifications section
    private static String formatCertifications(Map<String, Object> jsonMap) {
        List<String> lines = new List<String>();
        List<Map<String, Object>> items = extractList(jsonMap, 'certifications');
        
        if (items == null || items.isEmpty()) return null;

        for (Map<String, Object> item : items) {
            String certName = getStringValue(item, 'name');
            String issuer = getStringValue(item, 'issuer');
            String dateIssued = getStringValue(item, 'date');
            
            lines.add('🏆 ' + (certName != null ? certName : 'Certification'));
            if (issuer != null) lines.add('   Issued by: ' + issuer);
            if (dateIssued != null) lines.add('   Date: ' + dateIssued);
            lines.add('');
        }
        
        return truncateField(String.join(lines, '\n'));
    }

    // Calculate total experience from work history
    private static Decimal calculateTotalExperience(Map<String, Object> jsonMap) {
        try {
            // First check if totalExperience field exists
            String totalExp = getFieldValue(jsonMap, 'totalExperience');
            if (totalExp != null) {
                return Decimal.valueOf(totalExp);
            }
            
            // Calculate from experience array
            List<Map<String, Object>> items = extractList(jsonMap, 'experience');
            if (items == null || items.isEmpty()) return 0;
            
            Decimal total = 0;
            for (Map<String, Object> item : items) {
                String duration = getStringValue(item, 'duration');
                if (duration != null) {
                    total += extractYearsFromDuration(duration);
                }
            }
            
            return total;
        } catch (Exception e) {
            System.debug('Error calculating experience: ' + e.getMessage());
            return 0;
        }
    }

    // Extract years from duration string (e.g., "2 years 3 months" -> 2.25)
    private static Decimal extractYearsFromDuration(String duration) {
        Decimal years = 0;
        
        Pattern yearPattern = Pattern.compile('(\\d+)\\s*year');
        Matcher yearMatcher = yearPattern.matcher(duration.toLowerCase());
        if (yearMatcher.find()) {
            years += Decimal.valueOf(yearMatcher.group(1));
        }
        
        Pattern monthPattern = Pattern.compile('(\\d+)\\s*month');
        Matcher monthMatcher = monthPattern.matcher(duration.toLowerCase());
        if (monthMatcher.find()) {
            years += Decimal.valueOf(monthMatcher.group(1)) / 12;
        }
        
        return years;
    }

    // Extract list of items from JSON
    private static List<Map<String, Object>> extractList(Map<String, Object> jsonMap, String fieldName) {
        List<Map<String, Object>> resultList = new List<Map<String, Object>>();
        
        try {
            if (jsonMap.containsKey(fieldName)) {
                Map<String, Object> fieldObj = (Map<String, Object>) jsonMap.get(fieldName);
                Object valObj = fieldObj.get('value');
                
                if (valObj instanceof List<Object>) {
                    for (Object item : (List<Object>) valObj) {
                        if (item instanceof Map<String, Object>) {
                            Map<String, Object> wrapper = (Map<String, Object>) item;
                            if (wrapper.containsKey('value')) {
                                resultList.add((Map<String, Object>) wrapper.get('value'));
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error extracting list ' + fieldName + ': ' + e.getMessage());
        }
        
        return resultList;
    }

    // Get string value from map object
    private static String getStringValue(Map<String, Object> item, String key) {
        if (item == null || !item.containsKey(key)) return null;
        
        try {
            Object valObj = item.get(key);
            if (valObj instanceof Map<String, Object>) {
                Map<String, Object> fieldMap = (Map<String, Object>) valObj;
                Object value = fieldMap.get('value');
                return value != null ? String.valueOf(value) : null;
            }
        } catch (Exception e) {
            System.debug('Error getting string value for ' + key + ': ' + e.getMessage());
        }
        
        return null;
    }

    // Truncate field to maximum length
    private static String truncateField(String value) {
        if (value == null) return null;
        return value.length() > MAX_FIELD_LENGTH ? value.substring(0, MAX_FIELD_LENGTH) : value;
    }

    // Update Resume record with extracted data
    private static void updateResumeRecord(Id resumeId, ResumeResponse response) {
        Resume__c resume = new Resume__c(Id = resumeId);
        
        resume.Candidate_Name__c = response.candidateName;
        resume.Email__c = response.email;
        resume.Phone__c = response.phone;
        resume.LinkedIn__c = response.linkedin;
        resume.GitHub__c = response.github;
        resume.Trailhead__c = response.trailhead;
        resume.Professional_Summary__c = response.professionalSummary;
        resume.Work_Experience__c = response.workExperience;
        resume.Education__c = response.education;
        resume.Skills__c = response.skills;
        resume.Projects__c = response.projects;
        resume.Certifications__c = response.certifications;
        resume.Total_Experience__c = response.totalExperience;
        resume.Processing_Status__c = 'Completed';
        
        update resume;
    }

    // Handle API error
    private static void handleAPIError(Id resumeId, HttpResponse res) {
        String errorMessage = 'API Error: ' + res.getStatusCode() + ' - ' + res.getStatus();
        System.debug(LoggingLevel.ERROR, errorMessage);
        System.debug(LoggingLevel.ERROR, 'Response Body: ' + res.getBody());
        
        updateResumeStatus(resumeId, 'Failed');
        throw new CalloutException(errorMessage);
    }

    // Update resume status
    private static void updateResumeStatus(Id resumeId, String status) {
        update new Resume__c(Id = resumeId, Processing_Status__c = status);
    }

    // Async wrapper for processing
    @future(callout=true)
    public static void processResumeAsync(Id resumeId, String resumeName) {
        try {
            if (String.isBlank(resumeName)) {
                Resume__c r = [SELECT Name FROM Resume__c WHERE Id = :resumeId LIMIT 1];
                resumeName = r.Name;
            }
            
            List<Request> requests = new List<Request>();
            Request req = new Request();
            req.Name = resumeName;
            requests.add(req);
            
            requestDocumentAI(requests);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in processResumeAsync: ' + e.getMessage());
            updateResumeStatus(resumeId, 'Failed');
        }
    }

    // LWC Methods
    @AuraEnabled
    public static String uploadAndProcessResume(String fileName, String base64Data, String contentType) {
        try {
            // Create ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.IsMajorVersion = true;
            insert cv;
            
            // Get ContentDocumentId
            ContentVersion insertedCV = [
                SELECT ContentDocumentId 
                FROM ContentVersion 
                WHERE Id = :cv.Id 
                LIMIT 1
            ];
            
            // Create Resume record
            Resume__c resume = new Resume__c();
            resume.Resume_File_Name__c = fileName;
            resume.file_id__c = insertedCV.ContentDocumentId;
            resume.Processing_Status__c = 'Pending';
            insert resume;
            
            // Create ContentDocumentLink
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = insertedCV.ContentDocumentId;
            cdl.LinkedEntityId = resume.Id;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            insert cdl;
            
            // Process asynchronously
            processResumeAsync(resume.Id, resume.Name);
            
            return resume.Id;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Upload error: ' + e.getMessage());
            throw new AuraHandledException('Error uploading resume: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Resume__c getResumeDetails(Id resumeId) {
        try {
            return [
                SELECT Id, Name, Candidate_Name__c, Email__c, Phone__c, 
                       Total_Experience__c, Professional_Summary__c, Education__c, 
                       Skills__c, Work_Experience__c, Certifications__c, Projects__c, 
                       LinkedIn__c, GitHub__c, Trailhead__c, Processing_Status__c, 
                       Resume_File_Name__c, CreatedDate, LastModifiedDate
                FROM Resume__c 
                WHERE Id = :resumeId 
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving resume details: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Resume__c> getAllResumes() {
        try {
            return [
                SELECT Id, Name, Candidate_Name__c, Email__c, Phone__c, 
                       Total_Experience__c, Processing_Status__c, 
                       Resume_File_Name__c, CreatedDate
                FROM Resume__c 
                ORDER BY CreatedDate DESC 
                LIMIT 100
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving resumes: ' + e.getMessage());
        }
    }
}