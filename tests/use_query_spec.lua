local sqlserver = require("sqlserver")
local utils = require("sqlserver.utils")
local workspace_registry = require("sqlserver.core.workspace_registry")

local function execute(text)
  local co = coroutine.running()
  local completed = false
  local failure
  sqlserver.execute({ bufnr = 0, text = text }, function(_, err)
    completed = true
    failure = err
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co)
    end
  end)
  if not completed then
    coroutine.yield()
  end
  assert(not failure, failure and (failure.diagnostic or failure.message))
end

return {
  test_name = "Executing a USE statement should switch database",
  run_test_async = function()
    local query = "USE TestDbB;"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { query })
    utils.wait_for_schedule_async()
    local buf = vim.api.nvim_get_current_buf()
    execute(query)
    vim.wait(5000, function()
      return workspace_registry.get(buf).get_connection().database == "TestDbB"
    end, 10)
    local db = workspace_registry.get(buf).get_connection().database
    assert(db == "TestDbB", "Expected database to be TestDbB but instead it's " .. db)

    vim.cmd("bdelete!")
  end,
}
