local sqlserver = require("sqlserver")
local utils = require("sqlserver.utils")
local test_utils = require("tests.utils")

return {
  test_name = "Execute query should run the statement under the cursor",
  run_test_async = function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "SELECT * FROM TestDbA.dbo.Person WHERE ID = 1;",
      "SELECT * FROM TestDbA.dbo.Person WHERE ID = 2;",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    utils.wait_for_schedule_async()
    sqlserver.execute_query()
    local client = vim.lsp.get_clients({ name = "mssql_ls", bufnr = 0 })[1]
    local buf = vim.api.nvim_get_current_buf()

    local _, err = utils.wait_for_notification_async(buf, client, "query/complete", 30000)
    if err then
      error(err.message)
    end

    test_utils.defer_async(2000)

    local results = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(results:find("Amy"), "SQL query results do not contain the selected statement's row")
    assert(not results:find("Bob"), "SQL query executed more than the statement under the cursor")
    vim.cmd("bdelete")
  end,
}
