
package com.continuent.tungsten.replicator.ddlscan;

import java.io.File;
import java.util.ArrayList;
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
    private List<Index> suppressedIndices, additionalIndices;

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
                                ignoredTablesList.add(child.getAttributes().getNamedItem("name").getNodeValue());
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
                    if (nodeList.getLength() != 0){
                        NodeList childs = nodeList.item(0).getChildNodes();
                        for (int i=0; i<childs.getLength(); i++) {
                            Node child = childs.item(i);
                            if ("Index".equals(child.getNodeName())){
                                String name = child.getAttributes().getNamedItem("name").getNodeValue();
                                String table = child.getAttributes().getNamedItem("table").getNodeValue();
                                String cols = child.getAttributes().getNamedItem("cols").getNodeValue();
                                Index index = new Index(name, table);
                                index.setCols(cols);
                                if (child.getAttributes().getNamedItem("type") != null){
                                    index.setType(child.getAttributes().getNamedItem("type").getNodeValue());
                                }
                                additionalIndices.add(index);
                            }
                        }
                    }
                    
                    oneUtil.columnDataTypeOverrides = overrides;
                    oneUtil.ignoredTables = ignoredTablesList;
                    oneUtil.suppressedIndices = suppressedIndices;
                    oneUtil.additionalIndices = additionalIndices;
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
    
    public static class Index{
        private String name, table, cols, type="UNIQUE";

        
        public Index(String name, String table)
        {
            super();
            this.name = name.toUpperCase();
            this.table = table.toUpperCase();
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
