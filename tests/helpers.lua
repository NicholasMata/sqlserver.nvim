local M = {}

---@param action function
---@param timeout? integer
---@return function
function M.async(action, timeout)
  return function()
    local done = false
    local failure
    local thread = coroutine.create(function()
      local ok, err = xpcall(action, debug.traceback)
      failure = ok and nil or err
      done = true
    end)

    local started, start_error = coroutine.resume(thread)
    if not started then
      error(start_error, 0)
    end
    if not vim.wait(timeout or 180000, function()
      return done
    end, 10) then
      error("Test timed out", 0)
    end
    if failure then
      error(failure, 0)
    end
  end
end

return M
