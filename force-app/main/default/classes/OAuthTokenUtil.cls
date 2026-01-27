public class OAuthTokenUtil {
    public static String getAccessToken() {
        // Replace with your actual values or retrieve from Named Credential/Custom Setting
        String clientId = 'Replace with your actual values or retrieve from Named Credential/Custom Setting';
        String clientSecret = 'Replace with your actual values or retrieve from Named Credential/Custom Setting';
        String username = 'username';
        String password = 'userrpassword+securitytoken';

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://login.salesforce.com/services/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        String body = 'grant_type=password'
            + '&client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8')
            + '&client_secret=' + EncodingUtil.urlEncode(clientSecret, 'UTF-8')
            + '&username=' + EncodingUtil.urlEncode(username, 'UTF-8')
            + '&password=' + EncodingUtil.urlEncode(password, 'UTF-8');
        req.setBody(body);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            system.debug('result'+result);
            return (String)result.get('access_token');
        } else {
            System.debug('OAuth error: ' + res.getBody());
            return null;
        }
    }
}