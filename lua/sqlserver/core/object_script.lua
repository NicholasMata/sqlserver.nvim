local M = {}

local query_specs = {
  ScalarValuedFunction = { script_create_drop = "ScriptSelect", operation = 0 },
  StoredProcedure = { script_create_drop = "ScriptCreate", operation = 5 },
  TableValuedFunction = { script_create_drop = "ScriptSelect", operation = 0 },
  Table = { script_create_drop = "ScriptSelect", operation = 0, execute_immediately = true },
  View = { script_create_drop = "ScriptSelect", operation = 0, execute_immediately = true },
}

local definition_specs = {
  ScalarValuedFunction = { script_create_drop = "ScriptCreate", operation = 1 },
  StoredProcedure = { script_create_drop = "ScriptCreate", operation = 1 },
  TableValuedFunction = { script_create_drop = "ScriptCreate", operation = 1 },
  Table = { script_create_drop = "ScriptCreate", operation = 1 },
  View = { script_create_drop = "ScriptCreate", operation = 1 },
}

---@param object_type string
---@param intent "query"|"definition"
---@return { script_create_drop: string, operation: integer, execute_immediately?: boolean }
function M.for_intent(object_type, intent)
  local specs = intent == "query" and query_specs or intent == "definition" and definition_specs or nil
  assert(specs, "Object scripting intent must be 'query' or 'definition'")
  assert(specs[object_type], "Unsupported SQL Server object type: " .. tostring(object_type))
  return vim.deepcopy(specs[object_type])
end

function M.supported_types()
  return vim.tbl_keys(definition_specs)
end

return M
