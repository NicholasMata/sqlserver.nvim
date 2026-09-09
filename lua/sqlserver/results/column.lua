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
    source = source,
  }
end

return M
