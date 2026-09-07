local helpers = require("tests.helpers")
local integration = require("tests.helpers.integration")

local T = MiniTest.new_set({
  hooks = {
    pre_once = helpers.async(function()
      for _, name in ipairs({ "DbServer", "DbDatabase", "DbUser", "DbPassword" }) do
        assert(vim.env[name] and vim.env[name] ~= "", name .. " is required for integration tests")
      end
      integration.setup()
    end),
    post_once = function()
      require("sqlserver.adapters.sql_tools_service").stop()
    end,
  },
})

T["environment"] = MiniTest.new_set({
  hooks = { post_case = helpers.async(integration.cleanup) },
})
for _, module in ipairs({
  "download_spec",
  "saved_file_completion_spec",
  "edit_connections_spec",
  "new_query_completion_spec",
  "connect_spec",
}) do
  T["environment"][module] = require("tests.integration.specs." .. module)
end

T["connected workspace"] = MiniTest.new_set({ hooks = integration.connected_hooks() })
for _, module in ipairs({
  "dbo_completion_spec",
  "public_api_integration_spec",
  "execution_scope_integration_spec",
  "error_line_numbers_integration_spec",
  "execute_query_spec",
  "multiple_result_sets_spec",
  "result_history_integration_spec",
  "mixed_query_results_spec",
  "failed_statement_results_spec",
  "switch_database_spec",
  "language_intelligence_spec",
  "result_value_fidelity_spec",
  "result_limits_spec",
  "query_error_presentation_spec",
  "finder_spec",
  "object_scripting_spec",
  "query_zero_rows_spec",
  "file_with_space_spec",
  "non_ascii_spec",
  "cancel_query_spec",
  "use_query_spec",
}) do
  T["connected workspace"][module] = require("tests.integration.specs." .. module)
end

return T
