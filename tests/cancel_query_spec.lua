local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")
local utils = require("sqlserver.utils")
local workspace_registry = require("sqlserver.core.workspace_registry")

return {
  test_name = "Cancelling a query returns the workspace to connected",
  run_test_async = function()
    local original_notify = vim.notify
    local errors = {}
    vim.notify = function(message, level, opts)
      if level == vim.log.levels.ERROR then
        table.insert(errors, message)
      end
      return original_notify(message, level, opts)
    end
    local query = "WAITFOR DELAY '00:00:30' SELECT 1 AS test"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { query })

    sqlserver.execute_query()
    sqlserver.cancel_query()

    local workspace = workspace_registry.get()

    local timeout = vim.uv.hrtime() + 30 * 1e9
    while workspace.get_state() ~= "connected" and vim.uv.hrtime() < timeout do
      test_utils.defer_async(100)
    end

    -- ensure we're still connected after cancelation
    local state = workspace.get_state()
    assert(state == "connected", "Query manager should be 'Connected' after cancellation, but was '" .. state .. "'")

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "SELECT 7 AS AfterCancellation" })
    sqlserver.execute_query()
    local query_buffer = vim.api.nvim_get_current_buf()
    local client = vim.lsp.get_clients({ name = "mssql_ls", bufnr = query_buffer })[1]
    local _, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
    assert(not err, err and err.message or "Query after cancellation timed out")
    test_utils.defer_async(2000)
    assert(workspace.get_state() == "connected", "Workspace did not recover after executing a second query")
    assert(workspace.get_activity()[#workspace.get_activity()].status == "success")
    vim.notify = original_notify
    assert(not vim.iter(errors):any(function(message)
      return message:find("batch is aborted", 1, true)
    end), "Expected cancellation abort messages to remain internal activity details")
    vim.cmd("bdelete!")
  end,
}
