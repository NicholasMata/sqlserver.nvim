local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")
local utils = require("sqlserver.utils")
local workspace_registry = require("sqlserver.core.workspace_registry")

local function result_buffers()
  return vim
    .iter(vim.api.nvim_list_bufs())
    :filter(function(bufnr)
      return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr):match("/results.*%.sqlresult$")
    end)
    :totable()
end

local function execute_buffer_async(query_buffer, query)
  local query_window = vim.fn.win_findbuf(query_buffer)[1]
  if query_window then
    vim.api.nvim_set_current_win(query_window)
  else
    vim.api.nvim_win_set_buf(0, query_buffer)
  end
  vim.api.nvim_buf_set_lines(query_buffer, 0, -1, false, vim.split(query, "\n"))
  utils.wait_for_schedule_async()
  sqlserver.execute_buffer()
  local client = vim.lsp.get_clients({ name = "mssql_ls", bufnr = query_buffer })[1]
  local completed, err = utils.wait_for_notification_async(query_buffer, client, "query/complete", 30000)
  assert(not err, err and err.message or "Query completion timed out")
  test_utils.defer_async(2000)
  return completed
end

return {
  test_name = "Each query error should notify without hiding successful results",
  run_test_async = function()
    local query_buffer = vim.api.nvim_get_current_buf()
    local original_notify = vim.notify
    local errors = {}
    vim.notify = function(message, level, opts)
      if level == vim.log.levels.ERROR then
        table.insert(errors, message)
      end
      return original_notify(message, level, opts)
    end

    local completed = execute_buffer_async(
      query_buffer,
      [[
SELECT 1 AS FirstResult;
GO
THROW 50000, 'First expected error', 1;
GO
SELECT 2 AS SecondResult;
GO
THROW 50000, 'Second expected error', 1;
]]
    )
    assert(#completed.batchSummaries == 4, "Expected four independently executed batches")
    assert(#result_buffers() == 2, "Successful batches did not create two result buffers")
    assert(
      vim.iter(errors):any(function(message)
        return message:find("First expected error", 1, true)
      end),
      "The first SQL error did not produce a notification"
    )
    assert(
      vim.iter(errors):any(function(message)
        return message:find("Second expected error", 1, true)
      end),
      "The second SQL error did not produce a notification"
    )

    execute_buffer_async(query_buffer, "THROW 50000, 'Only expected error', 1;")
    vim.notify = original_notify
    assert(#result_buffers() == 0, "An error-only execution left stale result buffers")
    local activity = workspace_registry.get(query_buffer).get_activity()
    local execution = activity[#activity]
    assert(execution.status == "error" and execution.message == "Query failed")
    assert(
      vim.iter(errors):any(function(message)
        return message:find("Only expected error", 1, true)
      end),
      "The error-only execution did not produce a notification"
    )
  end,
}
