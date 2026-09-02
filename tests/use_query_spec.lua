local sqlserver = require("sqlserver")
local utils = require("sqlserver.utils")
local test_utils = require("tests.utils")
local workspace_registry = require("sqlserver.core.workspace_registry")

return {
  test_name = "Executing a USE statement should switch database",
  run_test_async = function()
    local query = "USE TestDbB;"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { query })
    utils.wait_for_schedule_async()
    sqlserver.execute_query()
    local client = test_utils.get_sql_client(0)
    local buf = vim.api.nvim_get_current_buf()

    local _, err = utils.wait_for_notification_async(buf, client, "query/complete", 30000)
    if err then
      error(err.message)
    end

    utils.defer_async(1000)
    local db = workspace_registry.get(buf).get_connection().database
    assert(db == "TestDbB", "Expected database to be TestDbB but instead it's " .. db)

    vim.cmd("bdelete!")
  end,
}
