local sqlserver = require("sqlserver")
local utils = require("sqlserver.utils")
local test_utils = require("tests.utils")

local function find_results_buffers(source_bufnr)
  local buffers = test_utils.result_buffers(source_bufnr)
  table.sort(buffers, function(left, right)
    return vim.api.nvim_buf_get_name(left) < vim.api.nvim_buf_get_name(right)
  end)
  return buffers
end

return {
  test_name = "Multiple result sets should be independently navigable",
  run_test_async = function()
    local query = [[
SELECT * FROM TestDbA.dbo.Person WHERE ID = 1;
SELECT * FROM TestDbA.dbo.Person WHERE ID = 2;
]]
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(query, "\n"))
    utils.wait_for_schedule_async()
    sqlserver.execute_buffer()
    local query_buffer = vim.api.nvim_get_current_buf()
    local client = test_utils.get_sql_client(query_buffer)

    local _, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
    if err then
      error(err.message)
    end
    test_utils.defer_async(2000)

    local buffers = find_results_buffers(query_buffer)
    assert(#buffers == 2, "Expected two result buffers")
    assert(vim.bo[buffers[1]].filetype == "sqlserver-result")
    local first = table.concat(vim.api.nvim_buf_get_lines(buffers[1], 0, -1, false), "\n")
    local second = table.concat(vim.api.nvim_buf_get_lines(buffers[2], 0, -1, false), "\n")
    assert(first:find("Bob", 1, true) and not first:find("Amy", 1, true))
    assert(second:find("Amy", 1, true) and not second:find("Bob", 1, true))
    assert(#vim.fn.win_findbuf(buffers[1]) == 1)
    assert(#vim.fn.win_findbuf(buffers[2]) == 0)

    local results_window = vim.fn.win_findbuf(buffers[1])[1]
    vim.api.nvim_set_current_win(results_window)
    sqlserver.next_result()
    assert(vim.api.nvim_get_current_buf() == buffers[2])
    sqlserver.previous_result()
    assert(vim.api.nvim_get_current_buf() == buffers[1])
    sqlserver.next_result()
    if #vim.api.nvim_tabpage_list_wins(0) == 1 then
      vim.cmd("split")
      vim.api.nvim_win_set_buf(0, query_buffer)
    end
    vim.api.nvim_win_close(results_window, true)
    assert(#vim.fn.win_findbuf(buffers[2]) == 0)
    sqlserver.show_results()
    assert(#vim.fn.win_findbuf(buffers[2]) == 1, "ShowResults did not reopen the last viewed result")
    for _, bufnr in ipairs(buffers) do
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end,
}
