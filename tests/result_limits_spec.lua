local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")
local utils = require("sqlserver.utils")

local function find_result_buffer()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr):match("/results%.sqlresult$") then
      return bufnr
    end
  end
end

return {
  test_name = "Query result limits should be visible and consistent",
  run_test_async = function()
    local query_buffer = vim.api.nvim_get_current_buf()
    local query = [[
WITH Numbers AS (
  SELECT 1 AS Value
  UNION ALL
  SELECT Value + 1 FROM Numbers WHERE Value < 150
)
SELECT Value, REPLICATE(N'x', 120) AS WideValue
FROM Numbers
OPTION (MAXRECURSION 150);
]]
    vim.api.nvim_buf_set_lines(query_buffer, 0, -1, false, vim.split(query, "\n"))
    utils.wait_for_schedule_async()
    sqlserver.execute_buffer()

    local client = test_utils.get_sql_client(query_buffer)
    local _, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
    assert(not err, err and err.message or "Query completion timed out")
    test_utils.defer_async(2000)

    local result_buffer = find_result_buffer()
    assert(result_buffer, "The limited query result was not displayed")
    local rendered = table.concat(vim.api.nvim_buf_get_lines(result_buffer, 0, -1, false), "\n")
    assert(rendered:find("Showing 100 of 150 rows", 1, true), "The configured row limit was not reported")
    assert(rendered:find("…", 1, true), "The configured cell-width limit was not indicated")

    vim.api.nvim_buf_delete(result_buffer, { force = true })
  end,
}
