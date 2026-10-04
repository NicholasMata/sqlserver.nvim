local snapshot = require("sqlserver.plans.snapshot")
local M = {}

local function request_async(client, params, timeout, is_active)
  local thread = assert(coroutine.running())
  local finished = false
  local request_id
  local timer = vim.uv.new_timer()
  local started = vim.uv.hrtime()
  local function complete(response, err)
    if finished then
      return
    end
    finished = true
    timer:stop()
    timer:close()
    vim.schedule(function()
      if coroutine.status(thread) == "suspended" then
        require("sqlserver.utils").try_resume(thread, response, err)
      end
    end)
  end
  local function cancel(code, message)
    if request_id then
      pcall(client.cancel_request, client, request_id)
    end
    complete(nil, { code = code, message = message })
  end
  timer:start(
    0,
    10,
    vim.schedule_wrap(function()
      if finished then
        return
      end
      if is_active and not is_active() then
        cancel("plan_cancelled", "Execution-plan capture was cancelled")
      elseif timeout and (vim.uv.hrtime() - started) / 1e6 >= timeout then
        cancel("plan_timeout", "Execution-plan retrieval timed out")
      end
    end)
  )
  local requested, sent, id = pcall(client.request, client, "query/executionPlan", params, function(err, response)
    complete(response, err)
  end)
  request_id = id
  if not requested or not sent then
    complete(nil, { code = "plan_capture_failed", message = "Could not send execution-plan request" })
  end
  return coroutine.yield()
end

function M.is_plan(result)
  return type(result.specialAction) == "table" and result.specialAction.expectYukonXMLShowPlan == true
end

function M.collect_async(client, completed, kind, timeout, is_active)
  local plans = {}
  for bi, batch in ipairs(completed.batchSummaries or {}) do
    for ri, result in ipairs(batch.resultSetSummaries or {}) do
      if M.is_plan(result) then
        if is_active and not is_active() then
          error({ code = "plan_cancelled", message = "Execution-plan capture was cancelled" }, 0)
        end
        local response, err = request_async(client, {
          ownerUri = completed.ownerUri,
          batchIndex = bi - 1,
          resultSetIndex = ri - 1,
        }, timeout, is_active)
        if err then
          error({
            code = type(err.code) == "string" and err.code or "plan_capture_failed",
            message = "Could not retrieve execution plan: " .. err.message,
          }, 0)
        end
        local plan = response and response.executionPlan
        if type(plan) ~= "table" or plan.format ~= "xml" then
          error({ code = "plan_capture_failed", message = "SQL Tools Service returned no supported XML plan" }, 0)
        end
        plans[#plans + 1] = snapshot.validate({
          xml = plan.content,
          kind = kind,
          ordinal = #plans + 1,
          batch_index = bi - 1,
          result_index = ri - 1,
          batch_range = type(batch.selection) == "table" and {
            start_line = batch.selection.startLine,
            start_column = batch.selection.startColumn,
            end_line = batch.selection.endLine,
            end_column = batch.selection.endColumn,
          } or nil,
        })
      end
    end
  end
  return plans
end

return M
