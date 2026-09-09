local M = {}

local length_types = {
  binary = true,
  char = true,
  nchar = true,
  nvarchar = true,
  varbinary = true,
  varchar = true,
}

local precision_types = { decimal = true, numeric = true }
local scale_types = { datetime2 = true, datetimeoffset = true, time = true }

local function number(value)
  return type(value) == "number" and value or nil
end

local function sized_type(type_name, metadata)
  local size = number(metadata.size)
  if not size or size <= 0 then
    return type_name
  end
  local ordinary_limit = type_name:sub(1, 1) == "n" and 4000 or 8000
  local size_label = (metadata.is_long or size > ordinary_limit) and "max" or tostring(size)
  return ("%s(%s)"):format(type_name, size_label)
end

function M.format_type(metadata)
  local type_name = metadata.type_name
  if type(type_name) ~= "string" or type_name == "" then
    return "Unknown"
  end
  if type_name:find("(", 1, true) then
    return type_name
  end

  local normalized = type_name:lower()
  if length_types[normalized] then
    return sized_type(type_name, metadata)
  end
  if precision_types[normalized] then
    local precision = number(metadata.precision)
    local scale = number(metadata.scale)
    if precision and scale then
      return ("%s(%d, %d)"):format(type_name, precision, scale)
    end
  elseif scale_types[normalized] then
    local scale = number(metadata.scale)
    if scale then
      return ("%s(%d)"):format(type_name, scale)
    end
  end
  return type_name
end

function M.lines(metadata)
  local declaration = M.format_type(metadata)
  if type(metadata.nullable) == "boolean" then
    declaration = declaration .. (metadata.nullable and " NULL" or " NOT NULL")
  end
  local lines = { declaration }

  if metadata.source and type(metadata.source.table) == "string" and metadata.source.table ~= "" then
    local source = {}
    local function append_source(value)
      if type(value) == "string" and value ~= "" then
        table.insert(source, value)
      end
    end
    append_source(metadata.source.schema)
    append_source(metadata.source.table)
    append_source(metadata.source.column)
    table.insert(lines, "-- Source: " .. table.concat(source, "."))
  end
  return lines
end

return M
