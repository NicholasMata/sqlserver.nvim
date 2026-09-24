local M = {}

local families = {
  text = {
    char = true,
    nchar = true,
    ntext = true,
    nvarchar = true,
    sysname = true,
    text = true,
    varchar = true,
  },
  number = {
    bigint = true,
    decimal = true,
    float = true,
    int = true,
    money = true,
    numeric = true,
    real = true,
    smallint = true,
    smallmoney = true,
    tinyint = true,
  },
  temporal = {
    date = true,
    datetime = true,
    datetime2 = true,
    datetimeoffset = true,
    smalldatetime = true,
    time = true,
  },
  binary = {
    binary = true,
    image = true,
    rowversion = true,
    timestamp = true,
    varbinary = true,
  },
}

local exact_families = {
  bit = "boolean",
  json = "json",
  uniqueidentifier = "uuid",
}

local highlights = {
  text = "SqlServerResultTypeText",
  number = "SqlServerResultTypeNumber",
  boolean = "SqlServerResultTypeBoolean",
  temporal = "SqlServerResultTypeTemporal",
  json = "SqlServerResultTypeJson",
  uuid = "SqlServerResultTypeUuid",
  binary = "SqlServerResultTypeBinary",
  unknown = "SqlServerResultTypeUnknown",
}

---@param type_name? string
---@return string
function M.family(type_name)
  if type(type_name) ~= "string" or type_name == "" then
    return "unknown"
  end
  local normalized = type_name:lower()
  if exact_families[normalized] then
    return exact_families[normalized]
  end
  for family, types in pairs(families) do
    if types[normalized] then
      return family
    end
  end
  return "unknown"
end

---@param metadata? SqlServerResultColumn
---@param icons table<string, string>
---@return { text: string, highlight: string, family: string }
function M.resolve(metadata, icons)
  local family = M.family(metadata and metadata.type_name)
  return {
    text = icons[family],
    highlight = highlights[family],
    family = family,
  }
end

return M
