public with sharing class PublishWorkFlowRuleController
{
    public MetadataService.AsyncResult AsyncResult {get; private set;}
    public String MetaDataRetrieveZip { get; private set; }
    public List<MetadataFile> MetadataFiles { get; set; }
    public String MetadataFileName {get; set;}     
    public String MetadataFileData {get; set;} 

    public String Host {get;set;}
    public String RemoteSiteSettingName {get;set;}
    public String MetadataResponse {get;set;}
    public Boolean MetadataConnectionWarning {get;set;}
    public Boolean AllowPublish {get;set;}
        
    public PageReference init()
    {
        AllowPublish = false;
        checkMetadataAPIConnection();
        if (!MetadataConnectionWarning) {
            Set<String> wkfs = getObjectsWithWorkflows();
            if ( wkfs != null && !wkfs.isEmpty() ) {
                AllowPublish = true;
                Datetime lmd = getLastModifiedDate();
                if (lmd != null) {
                    Set<String> oodWkfs = getOutOfDateWorkflows(lmd);
                    if ( oodWkfs != null && !oodWkfs.isEmpty() ) {
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Warning, 'One or more Workflow Rules have been created or modified since you last published: (last pusblished: ' + lmd.format() + ')'));
                    }
                }
                else {
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Warning, 'Workflow Rules have not been published (static resource file does not exist).'));
                }

            }
            else {
                AllowPublish = false;
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'You have no Workflow Rules to publish.'));                    
            }
        }

        return null;
    }

    public PageReference checkMetadataAPIConnection()
    {
        // Get Host Domain
        Host = ApexPages.currentPage().getHeaders().get('Host');
        RemoteSiteSettingName = RemoteSiteSettingsService.RemoteSiteSettingName;

        // Attempt to connect to the Metadata API
        MetadataConnectionWarning = false;
        if(!RemoteSiteSettingsService.checkMetadataAPIConnection())
        {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, 'Unable to connect to the Salesforce Metadata API.'));
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, 'A Remote Site Setting must be created in your org before you can use this tool.'));
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, 'Press the Create Remote Site Setting button to perform this step or refer to the post install step below to perform this manually.'));
            MetadataConnectionWarning = true;
        }
        
        return null;                
    }
    
    public PageReference displayMetadataResponse()
    {
        // Display the response from the client side Metadata API callout
        if(metadataResponse.length()==0)
        {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Remote Site Setting ' + RemoteSiteSettingName + ' has been created.' ));
            MetadataConnectionWarning = false;
        }
        else
        {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, metadataResponse));
            MetadataConnectionWarning = true;
        }
        return null;
    }   

        
    public PageReference retrieveWorkflowMetadata()
    {       
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Retrieving Workflow Rules...'));
        
        // Reset state from any previous requests
        MetaDataRetrieveZip = null;
        MetadataFiles = null;
         
        // Construct unmanaged package with list of desired components to retrieve in zip
        MetadataService.MetadataPort service = createService();             
        MetadataService.RetrieveRequest retrieveRequest = new MetadataService.RetrieveRequest();
        retrieveRequest.apiVersion = 25;
        retrieveRequest.packageNames = null;
        retrieveRequest.singlePackage = true;
        retrieveRequest.specificFiles = null;
        retrieveRequest.unpackaged = new MetadataService.Package_x();
        retrieveRequest.unpackaged.types = new List<MetadataService.PackageTypeMembers>();
        
        MetadataService.PackageTypeMembers packageType = new MetadataService.PackageTypeMembers();
        packageType.name = 'Workflow'; 

        Set<String> objs = getObjectsWithWorkflows();
        packageType.members = new List<String>(objs);

        retrieveRequest.unpackaged.types.add(packageType);
        AsyncResult = service.retrieve(retrieveRequest);
                        
        return null;    
    }
    

    public Datetime getLastModifiedDate() {
        ToolingApi toolingAPI = new ToolingApi();
        List<ToolingAPI.StaticResource> staticResource = 
            (List<ToolingAPI.StaticResource>)toolingAPI.query('SELECT LastModifiedDate FROM StaticResource Where Name = \'MobileWorkflowRules\' ').records;

        Datetime dt = Datetime.now();
        if ( staticResource != null && !staticResource.isEmpty() ) {
            ToolingAPI.StaticResource file = staticResource[0];
            dt = file.LastModifiedDate;
        }
        return dt;
    }
    
    public Set<String> getObjectsWithWorkflows() {
        ToolingApi toolingAPI = new ToolingApi();
        List<ToolingAPI.WorkflowRule> workflowRules = 
            (List<ToolingAPI.WorkflowRule>)toolingAPI.query('SELECT TableEnumOrId, lastModifiedDate FROM WorkflowRule ').records;

        Set<String> objects = new Set<String>();
        if (workflowRules != null) {
            for(ToolingAPI.WorkflowRule workflowRule : workflowRules) {
                if(!objects.contains(workflowRule.TableEnumOrId)) objects.add(workflowRule.TableEnumOrId);
            }
        }
        return objects;
    }

    public Set<String> getOutOfDateWorkflows(Datetime dt) {
        ToolingApi toolingAPI = new ToolingApi();
        List<ToolingAPI.WorkflowRule> workflowRules = 
            (List<ToolingAPI.WorkflowRule>)toolingAPI.query('SELECT TableEnumOrId, LastModifiedDate FROM WorkflowRule Where LastModifiedDate > ' + json.serialize(dt).replace('"', '') ).records;

        Set<String> objects = new Set<String>();
        if (workflowRules != null) {
            for(ToolingAPI.WorkflowRule workflowRule : workflowRules) {
                if(!objects.contains(workflowRule.TableEnumOrId)) objects.add(workflowRule.TableEnumOrId);
            }
        }
        return objects;
    }


    public PageReference checkAsyncRequest()
    {
        // Check the status of the retrieve request
        MetadataService.MetadataPort service = createService();
        MetadataService.RetrieveResult retrieveResult = service.checkRetrieveStatus(AsyncResult.Id);
        if(retrieveResult.done)
        {
            // Errors?
            if(retrieveResult.status != 'Succeeded')
            {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, retrieveResult.errorMessage));
                AsyncResult = null;             
            }
            else
            {
                // Place Base64 encoded zip data onto the page for the JSZip library to handle
                MetaDataRetrieveZip = retrieveResult.zipFile;
                MetadataFiles = new List<MetadataFile>();
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Expanding...'));
                AsyncResult = null;
            }
        }
        else
        {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Retrieving Workflow Rules...'));
        }   

        return null;
    }
    
    public PageReference receiveMetadataZipFile()
    {
        // In this example the retrieved metadata is stored in viewstate in production cases you would probably use a custom object / attachment
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Expanding ' + MetaDataFileName + '...'));
        MetadataFile metaDataFile = new MetadataFile();
        metaDataFile.fullName = MetaDataFileName;
        metaDataFile.content = MetaDataFileData;
        MetadataFiles.add(metaDataFile);
        return null;
    }
    
    public PageReference receiveComplete()
    {
        // Completed, cleared Base64 encoded zip data from viewstate
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, 'Publishing of Workflow Rules to Static Resource completed (' + Datetime.now().format() + ')'));
        MetaDataRetrieveZip = null;
        deleteStaticResource();
        String content = parseFiles();
        createStaticResource(content);     
        return null;
    }
    
    private static MetadataService.MetadataPort createService()
    { 
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();
        service.SessionHeader = new MetadataService.SessionHeader_element();
        service.SessionHeader.sessionId = UserInfo.getSessionId();
        return service;
    }   
    
    public void createStaticResource(String content)
    {
        MetadataService.MetadataPort service = createService();     
        MetadataService.StaticResource staticResource = new MetadataService.StaticResource();
        staticResource.fullName = 'MobileWorkflowRules';
        staticResource.contentType = 'text';
        staticResource.cacheControl = 'public';
        
        staticResource.content = EncodingUtil.base64Encode(Blob.valueOf(content));
        List<MetadataService.SaveResult> results =      
            service.createMetadata(
                new MetadataService.Metadata[] { staticResource });             
    }
    
    public static void deleteStaticResource()
    {
        MetadataService.MetadataPort service = createService();     
        List<MetadataService.DeleteResult> results =        
            service.deleteMetadata(
                'StaticResource', new String[] { 'MobileWorkflowRules' });
    }
    
    public String getObjectNameFromFileName(String filename) {
        return filename.split('/')[1].replace('.workflow', '');
    }

    public String parseFiles() {
        String content = '';
        String comma = '';
        WorkflowParsingService wps = new WorkflowParsingService();
        for (MetadataFile metadatafile: MetadataFiles) {
            if (metadatafile.fullName != 'package.xml') {
                content += comma + getObjectNameFromFileName(metadatafile.fullName) + ' : ' + wps.parseWorkflowRuleXml(metadatafile.content);
                comma = ',\n';
            }
        }
            
        System.debug(content);
        // return content;
        return 'window.FX_Mobile_Workflow = {\n    ' + content.replace('\n', '\n    ') + '\n}';
    }
    
    /**
     * Simple container class for retrieve metadata file, may as well leverage the Metadata API class for this
     **/
    public class MetadataFile extends MetadataService.MetadataWithContent
    {
        public String getFullname()
        {
            return fullName;
        }
        
        public String getContent()
        {
            return content;
        }
    }
}