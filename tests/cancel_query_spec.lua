local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")
local workspace_registry = require("sqlserver.core.workspace_registry")

return {
  test_name = "Cancelling a query returns the workspace to connected",
  run_test_async = function()
    local query = "WAITFOR DELAY '00:00:30' SELECT 1 AS test"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { query })

    sqlserver.execute_query()
    sqlserver.cancel_query()
    test_utils.defer_async(1000)

    local workspace = workspace_registry.get()

    -- ensure we're still connected after cancelation
    local state = workspace.get_state()
    assert(state == "connected", "Query manager should be 'Connected' after cancellation, but was '" .. state .. "'")

    test_utils.defer_async(2000)
    vim.cmd("bdelete!")
  end,
}
