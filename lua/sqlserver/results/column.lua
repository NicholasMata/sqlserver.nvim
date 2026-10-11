local M = {}

---@class SqlServerResultColumnSource
---@field catalog? string
---@field schema? string
---@field table? string
---@field column? string

---@class SqlServerResultColumn
---@field name string
---@field type_name? string
---@field size? integer
---@field precision? integer
---@field scale? integer
---@field nullable? boolean
---@field is_long boolean
---@field is_xml? boolean
---@field is_json? boolean First-row content hint; not a native JSON type
---@field aggregate_format? "json"|"xml" Reliable single-column FOR document identity
---@field source? SqlServerResultColumnSource

---@param value table SQL Tools Service DbColumnWrapper
---@return SqlServerResultColumn
function M.from_protocol(value)
  local source
  local nullable
  if type(value.allowDBNull) == "boolean" then
    nullable = value.allowDBNull
  end
  if type(value.baseTableName) == "string" and value.baseTableName ~= "" then
    source = {
      catalog = value.baseCatalogName,
      schema = value.baseSchemaName,
      table = value.baseTableName,
      column = value.baseColumnName,
    }
  end
  return {
    name = value.columnName or "",
    type_name = value.dataTypeName or value.dataType,
    size = type(value.columnSize) == "number" and value.columnSize or nil,
    precision = type(value.numericPrecision) == "number" and value.numericPrecision or nil,
    scale = type(value.numericScale) == "number" and value.numericScale or nil,
    nullable = nullable,
    is_long = value.isLong == true,
    is_xml = value.isXml == true or nil,
    is_json = value.isJson == true or nil,
    source = source,
  }
end

---@param columns SqlServerResultColumn[]
---@return "json"|"xml"|nil
function M.aggregate_format(columns)
  if #columns ~= 1 then
    return nil
  end
  local column = columns[1]
  local kind = (column.type_name or ""):lower()
  if kind == "xml" or kind == "json" then
    return nil -- Native structured values retain scalar storage semantics.
  end
  if column.name == "JSON_F52E2B61-18A1-11d1-B105-00805F49916B" then
    return "json"
  elseif column.name == "XML_F52E2B61-18A1-11d1-B105-00805F49916B" then
    return "xml"
  end
end

return M
