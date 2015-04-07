
package com.continuent.tungsten.replicator.ddlscan;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.List;
import java.util.Map;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Document;
import org.w3c.dom.NamedNodeMap;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import com.continuent.tungsten.replicator.database.Column;
import com.continuent.tungsten.replicator.database.Key;
import com.continuent.tungsten.replicator.database.Table;

public class OneUtil
{

    private Map<String, String> columnDataTypeOverrides;
    private List<String> ignoredTables;
    private List<Index> suppressedIndices, additionalIndices, commonIndices;

    static void populateAnalyticsOptions(
            Hashtable<String, Object> templateOptions)
    {
            OneUtil oneUtil = new OneUtil();
            templateOptions.put("OneUtil", oneUtil);
            String cfgFilePath = (String) templateOptions.get("analytics_cfg");
            File cfgFile = new File(cfgFilePath);
            if (cfgFile.exists())
            {
                DocumentBuilder builder;
                try
                {
                    builder = DocumentBuilderFactory.newInstance()
                            .newDocumentBuilder();
                    Document document = builder.parse(cfgFile);
                    NodeList nodeList = document
                            .getElementsByTagName("ColumnDataTypeOverride");
                    Map<String, String> overrides = new HashMap<String, String>();
                    for (int i = 0; i < nodeList.getLength(); i++)
                    {
                        Node node = nodeList.item(i);
                        NamedNodeMap attrs = node.getAttributes();
                        String column = attrs.getNamedItem("column")
                                .getNodeValue();
                        String dataType = attrs.getNamedItem("datatype")
                                .getNodeValue();
                        if (column != null && dataType != null)
                        {
                            overrides.put(column, dataType);
                        }
                    }
                    nodeList = document.getElementsByTagName("IgnoreTables");
                    List<String> ignoredTablesList= new ArrayList<String>();
                    if (nodeList.getLength() != 0) {
                        NodeList childs = nodeList.item(0).getChildNodes();
                        for (int i=0; i<childs.getLength(); i++) {
                            Node child = childs.item(i);
                            if ("Table".equals(child.getNodeName())){
                                ignoredTablesList.add(child.getAttributes().getNamedItem("name").getNodeValue().toUpperCase());
                            }
                        }
                    }
                    
                    nodeList = document.getElementsByTagName("SuppressIndices");
                    List<Index> suppressedIndices = new ArrayList<Index>();
                    if (nodeList.getLength() != 0){
                        NodeList childs = nodeList.item(0).getChildNodes();
                        for (int i=0; i<childs.getLength(); i++) {
                            Node child = childs.item(i);
                            if ("Index".equals(child.getNodeName())){
                                String name = child.getAttributes().getNamedItem("name").getNodeValue();
                                String table = child.getAttributes().getNamedItem("table").getNodeValue();
                                suppressedIndices.add(new Index(name, table));
                            }
                        }
                    }
                    
                    nodeList = document.getElementsByTagName("AdditionalIndices");
                    List<Index> additionalIndices = new ArrayList<Index>();
                    List<Index> commonIndices = new ArrayList<Index>();
                    if (nodeList.getLength() != 0){
                        NodeList childs = nodeList.item(0).getChildNodes();
                        for (int i=0; i<childs.getLength(); i++) {
                            Node child = childs.item(i);
                            if ("Index".equals(child.getNodeName())){
                                Node nameAttr = child.getAttributes().getNamedItem("name");
                                Node nameSuffixAttr = child.getAttributes().getNamedItem("nameSuffix");
                                String cols = child.getAttributes().getNamedItem("cols").getNodeValue();
                                if (nameAttr != null){
                                    String name = nameAttr.getNodeValue();
                                    String table = child.getAttributes().getNamedItem("table").getNodeValue();
                                    Index index = new Index(name, table);
                                    index.setCols(cols);
                                    if (child.getAttributes().getNamedItem("type") != null){
                                        index.setType(child.getAttributes().getNamedItem("type").getNodeValue());
                                    }
                                    additionalIndices.add(index);
                                }
                                else if (nameSuffixAttr != null){
                                    String name = nameSuffixAttr.getNodeValue();
                                    String[] colTypes = child.getAttributes().getNamedItem("colTypes").getNodeValue().toUpperCase().split(",");
                                    String[] colNames = cols.toUpperCase().split(",");
                                    
                                    Index index = new Index(name, colNames, colTypes);
                                    if (child.getAttributes().getNamedItem("type") != null){
                                        index.setType(child.getAttributes().getNamedItem("type").getNodeValue());
                                    }
                                    commonIndices.add(index);
                                }
                                
                            }
                        }
                    }
                    
                    oneUtil.columnDataTypeOverrides = overrides;
                    oneUtil.ignoredTables = ignoredTablesList;
                    oneUtil.suppressedIndices = suppressedIndices;
                    oneUtil.additionalIndices = additionalIndices;
                    oneUtil.commonIndices = commonIndices;
                }
                catch (Exception e)
                {
                    DDLScanCtrl
                            .println("Exception while populating analystics options : "
                                    + e.getMessage());
                    DDLScanCtrl.println("Ignored option analytics_cfg");
                }

            }
    }

    public boolean isIgnored(String tableName) {
        return ignoredTables != null ? ignoredTables.contains(tableName) : false;
    }
    
    public boolean isColumnOverridden(String tableName, String columnName)
    {
        return columnDataTypeOverrides != null ? (columnDataTypeOverrides
                .containsKey(tableName + "." + columnName)
                || columnDataTypeOverrides.containsKey(columnName)) : false;
    }

    public String getColumnDataType(String tableName, String columnName)
    {
        if (isColumnOverridden(tableName, columnName))
        {
            String fullColumnName = tableName + "." + columnName;
            if (columnDataTypeOverrides.get(fullColumnName) != null)
            {
                return columnDataTypeOverrides.get(fullColumnName);
            }
            return columnDataTypeOverrides.get(columnName);
        }
        return null;
    }
    
    public static boolean isPrimaryKey(Table table, Key key){
        if (table.getPrimaryKey() != null){
            if (table.getPrimaryKey().getName()!= null && table.getPrimaryKey().getName().equals(key.getName()))
                return true;
            List<Column> pkCols = table.getPrimaryKey().getColumns();
            List<Column> keyCols = key.getColumns();
            if (pkCols.size() == keyCols.size()){
                for (Column col1 : pkCols){
                    boolean found = false;
                    for (Column col2 : keyCols){
                        if (col1.getName().equals(col2.getName())){
                            found = true;
                        }
                    }
                    if (!found){
                        return false;
                    }
                }
                return true;
            }
        }
        return false;
    }
    
    public boolean isSuppressed(Table table, Key key){
        Index candidate = new Index(key.getName(), table.getName());
        return suppressedIndices != null && suppressedIndices.contains(candidate);
    }
    
    public List<Index> getAdditionalIndices(){
        return additionalIndices;
    }
    
    public List<Key> getIndices(Table table){
       List<Key> keys = new ArrayList<Key>(table.getUniqueIndexes());
       List<String> allColNames = new ArrayList<String>();
       for (Column col : table.getAllColumns()){
           allColNames.add(col.getName().toUpperCase());
       }
       for (Index index : commonIndices){
           List<String> indexColNames = new ArrayList<String>(Arrays.asList(index.getColNames()));
           indexColNames.retainAll(allColNames);
           if (index.getColNames().length == indexColNames.size()){
               Key key = new Key(index.getType().equals("NONUNIQUE") ? Key.NonUnique : Key.Unique);
               key.setName(table.getName().toUpperCase()+"_"+index.getName());
               String[] colTypes = index.getColTypes();
               for (int i=0; i<indexColNames.size(); i++){
                   key.AddColumn(new Column(indexColNames.get(i), JDBCType.valueOf(colTypes[i]).getType()));
               }
               keys.add(key);
           }
       }
       return keys;
    }

    public static class Index{
        private String name, table, cols, type="UNIQUE";
        private String[] colNames, colTypes;
        
        public Index(String name, String table)
        {
            super();
            this.name = name.toUpperCase();
            this.table = table.toUpperCase();
        }

        Index(String name, String[] colNames, String[] colTypes){
            super();
            this.name = name.toUpperCase();
            this.colNames = colNames;
            this.colTypes = colTypes;
            if (colNames.length != colTypes.length){
                throw new RuntimeException("Please check length of cols and colTypes");
            }
        }
        
        String[] getColTypes(){
            return colTypes;
        }
        
        String[] getColNames(){
            return colNames;
        }
        
        public String getName()
        {
            return name;
        }

        public void setName(String name)
        {
            this.name = name.toUpperCase();
        }

        public String getTable()
        {
            return table;
        }

        public void setTable(String table)
        {
            this.table = table.toUpperCase();
        }

        public String getCols()
        {
            return cols;
        }

        public void setCols(String cols)
        {
            this.cols = cols;
        }

        public String getType()
        {
            return type;
        }

        public void setType(String type)
        {
            this.type = type.toUpperCase();
        }

        @Override
        public boolean equals(Object obj)
        {
            if (this == obj) return true;
            if (obj instanceof Index){
                Index iObj = (Index) obj;
                return name.equals(iObj.name) && table.equals(iObj.table);
            }
            return false;
        }
    }
}
