local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")
local utils = require("sqlserver.utils")

local function result_buffers()
  return vim
    .iter(vim.api.nvim_list_bufs())
    :filter(function(bufnr)
      return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr):match("/results.*%.sqlresult$")
    end)
    :totable()
end

return {
  test_name = "Failed statements should not create empty result buffers",
  run_test_async = function()
    local query_buffer = vim.api.nvim_get_current_buf()
    local query = [[
USE TestDbA;
SELECT *
FROM TestDbA.dbo.Person
WHERE TestDbA.dbo.Person.Name = 1;
GO

SELECT *
FROM Person
WHERE Person.ID = 2;
]]
    vim.api.nvim_buf_set_lines(query_buffer, 0, -1, false, vim.split(query, "\n"))
    utils.wait_for_schedule_async()
    sqlserver.execute_buffer()

    local client = test_utils.get_sql_client(query_buffer)
    local completed, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
    assert(not err, err and err.message or "Query completion timed out")
    assert(#completed.batchSummaries == 2, "Expected GO to create two batches")
    local summaries = {
      completed.batchSummaries[1].resultSetSummaries[1],
      completed.batchSummaries[2].resultSetSummaries[1],
    }
    assert(
      #summaries == 2,
      "Expected SQL Tools Service to report both result-set positions: " .. vim.inspect(summaries)
    )
    assert(completed.batchSummaries[1].hasError, "The first batch did not report its conversion error")
    assert(not completed.batchSummaries[2].hasError, "The second batch should have succeeded")
    assert(summaries[1].rowCount == 0, "The failed result set unexpectedly returned rows")
    assert(summaries[2].rowCount == 1, "The successful result set did not return Amy")

    local buffers
    local timeout = vim.uv.hrtime() + 10 * 1e9
    repeat
      test_utils.defer_async(100)
      buffers = result_buffers()
    until #buffers == 1 or vim.uv.hrtime() >= timeout

    assert(#buffers == 1, "Expected exactly one successful result buffer")
    assert(
      vim.api.nvim_buf_get_name(buffers[1]):match("/results 2%.sqlresult$"),
      "The result ordinal was not preserved"
    )
    local rendered = table.concat(vim.api.nvim_buf_get_lines(buffers[1], 0, -1, false), "\n")
    assert(rendered:find("Amy", 1, true), "The successful second result was not rendered")
    assert(not rendered:find("Bob", 1, true), "The failed first result leaked into the successful result buffer")

    vim.api.nvim_buf_delete(buffers[1], { force = true })
  end,
}
