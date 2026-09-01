local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")
local utils = require("sqlserver.utils")
local workspace_registry = require("sqlserver.core.workspace_registry")

local function find_result_buffer()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr):match("/results%.sqlresult$") then
      return bufnr
    end
  end
end

return {
  test_name = "Query errors should preserve preceding results",
  run_test_async = function()
    local query_buffer = vim.api.nvim_get_current_buf()
    local query = [[
SELECT 42 AS ValueBeforeError;
THROW 50000, 'Expected integration error', 1;
]]
    vim.api.nvim_buf_set_lines(query_buffer, 0, -1, false, vim.split(query, "\n"))
    utils.wait_for_schedule_async()
    sqlserver.execute_buffer()

    local client = vim.lsp.get_clients({ name = "mssql_ls", bufnr = query_buffer })[1]
    local completed, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
    assert(not err, err and err.message or "Query completion timed out")
    assert(completed.batchSummaries[1].hasError, "SQL Tools Service did not report the expected query error")
    assert(
      completed.batchSummaries[1].resultSetSummaries[1],
      "SQL Tools Service did not preserve the result returned before the error"
    )

    test_utils.defer_async(2000)
    local result_buffer = find_result_buffer()
    assert(result_buffer, "The result returned before the error was not displayed")
    local rendered = table.concat(vim.api.nvim_buf_get_lines(result_buffer, 0, -1, false), "\n")
    assert(rendered:find("42", 1, true), "The preserved result does not contain its returned value")

    local workspace = workspace_registry.get(query_buffer)
    local activity = workspace.get_activity()
    local execution = activity[#activity]
    assert(execution.kind == "query" and execution.status == "error")
    assert(execution.message:find("1 rows", 1, true))
    assert(
      vim.iter(activity):any(function(event)
        return event.kind == "message" and event.status == "error" and event.message:find("Expected integration error")
      end),
      "The SQL error message was not retained in workspace activity"
    )

    vim.api.nvim_buf_delete(result_buffer, { force = true })
  end,
}
