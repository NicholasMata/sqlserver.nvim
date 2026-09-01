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
  test_name = "Query results should preserve SQL value semantics",
  run_test_async = function()
    local query_buffer = vim.api.nvim_get_current_buf()
    local query = [[
SELECT
  CAST(NULL AS NVARCHAR(10)) AS ActualNull,
  N'NULL' AS LiteralNull,
  N'Grüße 😀' AS UnicodeText,
  CAST(12345.6789 AS DECIMAL(10,4)) AS DecimalValue,
  CAST('2026-09-01T12:34:56.1234567' AS DATETIME2(7)) AS DateValue,
  0x00FF AS BinaryValue;
]]
    vim.api.nvim_buf_set_lines(query_buffer, 0, -1, false, vim.split(query, "\n"))
    utils.wait_for_schedule_async()
    sqlserver.execute_buffer()

    local client = vim.lsp.get_clients({ name = "mssql_ls", bufnr = query_buffer })[1]
    local _, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
    assert(not err, err and err.message or "Query completion timed out")
    test_utils.defer_async(2000)

    local result_buffer = find_result_buffer()
    assert(result_buffer, "The typed query result was not displayed")
    local rendered = table.concat(vim.api.nvim_buf_get_lines(result_buffer, 0, -1, false), "\n")
    for _, expected in ipairs({ "ActualNull", "LiteralNull", "Grüße 😀", "12345.6789", "2026-09-01", "0x00FF" }) do
      assert(rendered:find(expected, 1, true), "The result does not contain " .. expected)
    end

    local namespace = vim.api.nvim_get_namespaces()["sqlserver-results"]
    local marks = vim.api.nvim_buf_get_extmarks(result_buffer, namespace, 0, -1, { details = true })
    local null_highlights = vim
      .iter(marks)
      :filter(function(mark)
        return mark[4].hl_group == "SqlServerResultNull"
      end)
      :totable()
    assert(#null_highlights == 1, "Only the database NULL should be highlighted as null")

    vim.api.nvim_buf_delete(result_buffer, { force = true })
  end,
}
