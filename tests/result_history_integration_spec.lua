local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")
local utils = require("sqlserver.utils")

local function execute_async(query_buffer, value)
  local query_window = vim.fn.win_findbuf(query_buffer)[1]
  if query_window then
    vim.api.nvim_set_current_win(query_window)
  else
    vim.api.nvim_win_set_buf(0, query_buffer)
  end
  vim.api.nvim_buf_set_lines(query_buffer, 0, -1, false, { ("SELECT %d AS Value;"):format(value) })
  utils.wait_for_schedule_async()
  sqlserver.execute_buffer()
  local client = test_utils.get_sql_client(query_buffer)
  local _, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
  assert(not err, err and err.message or "Query completion timed out")
  test_utils.defer_async(1000)
  return test_utils.result_buffers(query_buffer)[1]
end

local function contents(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

return {
  test_name = "Repeated queries should retain navigable execution results",
  run_test_async = function()
    local query_buffer = vim.api.nvim_get_current_buf()
    local first_result = execute_async(query_buffer, 101)
    assert(first_result and contents(first_result):find("101", 1, true))

    local second_result = execute_async(query_buffer, 202)
    assert(second_result and second_result ~= first_result)
    assert(contents(second_result):find("202", 1, true))
    assert(vim.api.nvim_buf_is_valid(first_result), "The second execution discarded the first result")

    sqlserver.previous_execution()
    assert(vim.api.nvim_get_current_buf() == first_result)
    sqlserver.next_execution()
    assert(vim.api.nvim_get_current_buf() == second_result)

    vim.api.nvim_buf_delete(first_result, { force = true })
    vim.api.nvim_buf_delete(second_result, { force = true })
  end,
}
