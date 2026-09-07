local sqlserver = require("sqlserver")
local utils = require("sqlserver.utils")
local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

T["Queries returning zero rows should work"] = require("tests.helpers").async(function()
  local query = "SELECT * from TestDbB.dbo.Car WHERE 1=0"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { query })
  utils.wait_for_schedule_async()
  sqlserver.execute_query()
  local client = test_utils.get_sql_client(0)
  local buf = vim.api.nvim_get_current_buf()

  local _, err = utils.wait_for_notification_async(buf, client, "query/complete", 30000)
  if err then
    error(err.message)
  end

  test_utils.defer_async(2000)

  local results = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(results:find("Make"), "Sql query results with zero rows are not showing the column headings")
end)

return T
