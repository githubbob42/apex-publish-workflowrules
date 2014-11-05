global with sharing class RemoteSiteSettingsService {
    // this method simply tries to query the RemoteSiteSetting object via the MetadataAPI.  If it succeeds, the remote site setting is setup correctly
    global static Boolean checkMetadataAPIConnection()
    {
        try {
            MetadataService.MetadataPort service = new MetadataService.MetadataPort();
            service.SessionHeader = new MetadataService.SessionHeader_element();
            service.SessionHeader.sessionId = UserInfo.getSessionId();
            List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
            MetadataService.ListMetadataQuery remoteSites = new MetadataService.ListMetadataQuery();
            remoteSites.type_x = 'RemoteSiteSetting';
            queries.add(remoteSites);
            service.listMetadata(queries, 28);
        } catch (System.CalloutException e) {
            return false;
        }
        return true;
    }
}