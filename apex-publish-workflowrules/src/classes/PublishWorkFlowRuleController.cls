
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

        
    public PageReference retrieveMetadataItem()
    {       
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Retrieving metadata...'));
        
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
        //packageType.members = new String[] { MetadataFolder, MetaDataItem };
        packageType.members = new String[] { 'FX5__Job__c', 'FX5__Ticket__c' };
        retrieveRequest.unpackaged.types.add(packageType);
        AsyncResult = service.retrieve(retrieveRequest);
                        
        return null;    
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
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, retrieveResult.errorMessage));
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
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Publishing of Workflow Rules to Static Resource completed'));
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
        for (MetadataFile metadatafile: MetadataFiles) {
            if (metadatafile.fullName != 'package.xml') {
                content += comma + getObjectNameFromFileName(metadatafile.fullName) + ': ' + parse(metadatafile.content);
                comma = ',\n';
            }
        }
            
        System.debug(content);
        return content;
    }

    private String parse(String toParse) {
        System.debug('hello world');
        DOM.Document doc = new DOM.Document();     
        try {
            doc.load(toParse);   
            DOM.XMLNode root = doc.getRootElement();

            Map<String, List<String>> sections = new Map<String, List<String>>();
            for (Dom.XMLNode child: root.getChildElements()) {
                String sectionName = child.getName();
                if(!sections.containsKey(sectionName)) sections.put(sectionName, new List<String>());
                sections.get(sectionName).add(walkThrough(child, sectionName));
            }

            String results = '';
            String comma = '';
            for (String key : sections.keySet()) {
                String openParen = '', closeParen = '';
                if (key != 'rules') {
                    openParen = '[';
                    closeParen = ']';
                }
                results += String.format('{0}{1} : {2}{3}{4}', new string[]{comma, key, openParen, String.join(sections.get(key), ',\n'), closeParen});
                comma = ',\n';
            }
            return '{' + results + '\n}';


        } catch (System.XMLException e) {  // invalid XML
            return e.getMessage() + ' it broke';
        }
    }
    
    private String indent = '';
    private String walkThrough(DOM.XMLNode node, String section) {
        String result = '';
        if (node.getNodeType() == DOM.XMLNodeType.ELEMENT) {
            
            if (node.getName() != section) {
                result += node.getName() + ' : ';
            }

            Dom.XmlNode[] childElements = node.getChildElements();
            if (childElements.size() != 0) {
                indent += '    ';
                result += '{\n' + indent;
                String comma = '';
                for (Dom.XMLNode child: node.getChildElements()) {
                  result += comma + walkThrough(child, null);
                  comma = ',\n' + indent;
                }
                indent = indent.substring(0, indent.length() - 4);
                result += '\n' + indent + '}';
            }
            else {
                String value = node.getText().trim();
                result += formatValue(value);
            }

            return result;
        }

        return '';  //should never reach here
    }

    private String formatValue(String value) {
        if (value == '') return 'null';
        if (value == 'true' || value == 'false') return value;
        if (value.isNumeric()) return value;
        return '\'' + value.replace('\'', '\\\'') + '\'';
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