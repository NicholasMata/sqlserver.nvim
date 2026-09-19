local M = {}

local query_labels = {
  Table = "Select rows",
  View = "Select rows",
  StoredProcedure = "Create execution script",
  ScalarValuedFunction = "Create query script",
  TableValuedFunction = "Create query script",
}

local function quote_identifier(value)
  return "[" .. tostring(value):gsub("]", "]]") .. "]"
end

---@param object table
---@return string
function M.qualified_name(object)
  local name = quote_identifier(object.name)
  if object.schema and object.schema ~= "" then
    return quote_identifier(object.schema) .. "." .. name
  end
  return name
end

---@param object table
---@return table[]
function M.for_object(object)
  local actions = {}
  if query_labels[object.type] then
    actions[#actions + 1] = { id = "query", label = query_labels[object.type], icon = "󰐊" }
  end
  actions[#actions + 1] = { id = "definition", label = "Show definition", icon = "󰈙" }
  actions[#actions + 1] = { id = "copy_name", label = "Copy name", icon = "󰆏" }
  actions[#actions + 1] = { id = "copy_qualified_name", label = "Copy qualified name", icon = "󰆏" }
  actions[#actions + 1] = { id = "refresh", label = "Refresh details", icon = "󰑐" }
  return actions
end

return M
