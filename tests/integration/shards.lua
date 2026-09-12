local M = {}

M.environment = {
  core = {
    "saved_file_completion_spec",
    "edit_connections_spec",
    "new_query_completion_spec",
    "connect_spec",
    "unnamed_query_buffer_spec",
  },
  objects = {},
}

M.connected = {
  core = {
    "public_api_integration_spec",
    "execution_scope_integration_spec",
    "error_line_numbers_integration_spec",
    "execute_query_spec",
    "multiple_result_sets_spec",
    "result_history_integration_spec",
    "mixed_query_results_spec",
    "failed_statement_results_spec",
    "result_value_fidelity_spec",
    "result_limits_spec",
    "query_error_presentation_spec",
    "query_zero_rows_spec",
    "file_with_space_spec",
    "non_ascii_spec",
    "cancel_query_spec",
  },
  objects = {
    "dbo_completion_spec",
    "switch_database_spec",
    "language_intelligence_spec",
    "finder_spec",
    "object_scripting_spec",
    "object_refresh_spec",
    "use_query_spec",
  },
}

M.names = { "core", "objects" }

function M.modules(group, shard)
  local groups = assert(M[group], "Unknown integration test group: " .. tostring(group))
  if shard and shard ~= "" then
    return assert(groups[shard], "Unknown integration test shard: " .. shard)
  end

  local modules = {}
  for _, name in ipairs(M.names) do
    vim.list_extend(modules, groups[name])
  end
  return modules
end

return M
