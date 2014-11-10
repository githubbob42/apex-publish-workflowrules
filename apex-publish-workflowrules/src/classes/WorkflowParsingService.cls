public with sharing class WorkflowParsingService {

    public String parseWorkflowRuleXml(String toParse) {
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
                results += String.format('{0}{1} : [{2}]', new string[]{ comma, key, String.join(sections.get(key), ',\n') });
                comma = ',\n';
            }
            return '{\n    ' + results.replace('\n', '\n    ') + '\n}';


        } catch (System.XMLException e) {  // invalid XML
            return e.getMessage() + ' it broke';
        }
    }
    
    private String indent = '';
    private String walkThrough(DOM.XMLNode node, String section) {
        String result = '';
        List<String> criteriaItems = new List<String>();
        List<String> actions = new List<String>();
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
                    if (child.getName() == 'criteriaItems') {
                        criteriaItems.add(buildCriteriaItem(child));
                    }
                    else if (child.getName() == 'actions') {
                        actions.add(walkThrough(child, 'actions'));
                    }
                    else {
                        result += comma + walkThrough(child, null);
                        comma = ',\n' + indent;
                    }
                }
                if (actions.size() > 0) {
                    result += String.format('{0}{1} : [{2}]', new string[]{comma, 'actions', String.join(actions, ', ') });
                }
                
                if (criteriaItems.size() > 0) {
                    // result += String.format('{0}{1} : [{2}]', new string[]{comma, 'criteriaItems', String.join(criteriaItems, ' AND ') });
                    result += String.format('{0}{1} : ["{2}"]', new string[]{comma, 'criteriaItems', String.join(criteriaItems, '",\n"') });
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

    private String buildCriteriaItem(DOM.XMLNode criteriaItem){
        String field = '';
        String operation = '';
        String value = '';
        
        for (Dom.XMLNode node: criteriaItem.getChildElements()) {
            if (node.getName() == 'field') {
                field = node.getText().trim();
            }
            if (node.getName() == 'operation'){
                operation = node.getText().trim();
            }
            if (node.getName() == 'value'){
                value = node.getText().trim();
            }
        }
        return formatCriteriaForOperator(field, operation, value);
    }

    private String formatValue(String value) {
        if (value == '') return 'null';
        if (value.toLowerCase() == 'true' || value.toLowerCase() == 'false') return value.toLowerCase();
        if (value.isNumeric()) return value;
        return '\'' + value.replace('\'', '\\\'') + '\'';
    }

    private String formatCriteriaForOperator(String field, String operator, String value) {
        /*
        Valid values for "operator" are as follows - we'll need to come up with the equivalent javascript operators/functions
        https://help.salesforce.com/apex/HTViewHelpDoc?id=filter_operators.htm
        ----------------------------------------------------------------------
        equals
            ==
        not equal to
            !=
        starts with
            BEGINS(test1, "unit")
        contains
            CONTAINS(test1, "unit")
        does not contain
            NOT(CONTAINS(test1, "unit"))
            !CONTAINS(test1, "unit") (??????)
        less than
            <
        greater than
            >
        less or equal
            <=
        greater or equal
            >=
        includes
            INCLUDES( Multi_Picklist_1__c , "A")  <-- note that this is for multi picklists
        excludes
            NOT(INCLUDES( Multi_Picklist_1__c , "A"))   <-- ?????
        within (??? not supported for rule criteria???)
            ??? 
        */

        String formula = '';
        // until salesforce adds switch/case we need to blunt force it...
        if (operator == 'equals') {
            formula = String.format('({0} {1} {2})', new string[]{field, '==', formatValue(value)}); 
        }
        else if (operator == 'notEqual') {
            formula = String.format('({0} {1} {2})', new string[]{field, '!=', formatValue(value)}); 
        }
        else if (operator == 'startsWith') {
            formula = String.format('({1}({0}, {2})', new string[]{field, 'BEGINS', formatValue(value)}); 
        }
        else if (operator == 'contains') {
            formula = String.format('({1}({0}, {2})', new string[]{field, 'CONTAINS', formatValue(value)}); 
        }
        else if (operator == 'notContain') {
            formula = String.format('(NOT({1}({0}, {2}))', new string[]{field, 'CONTAINS', formatValue(value)}); 
        }
        else if (operator == 'lessThan') {
            formula = String.format('({0} {1} {2})', new string[]{field, '<', formatValue(value)}); 
        }
        else if (operator == 'greaterThan') {
            formula = String.format('({0} {1} {2})', new string[]{field, '>', formatValue(value)}); 
        }
        else if (operator == 'lessOrEqual') {
            formula = String.format('({0} {1} {2})', new string[]{field, '<=', formatValue(value)}); 
        }
        else if (operator == 'greaterOrEqual') {
            formula = String.format('({0} {1} {2})', new string[]{field, '>=', formatValue(value)}); 
        }
        else if (operator == 'includes') {
            formula = String.format('({1}({0}, {2})', new string[]{field, 'INCLUDES', formatValue(value)}); 
        }
        else if (operator == 'excludes') {
            formula = String.format('(NOT({1}({0}, {2}))', new string[]{field, 'INCLUDES', formatValue(value)}); 
        }
        else {
            // Yes - I know this will not work, but it's the only I can think of keeping the data...
            // Maybe we can send a message to the screen too...
            // Of course we shouldn't ever get here unless SF adds new operators
            formula = String.format('({0} {1} {2})', new string[]{field, operator, formatValue(value)}); 
        }

        return formula.replace('"', '\\"');
    }}