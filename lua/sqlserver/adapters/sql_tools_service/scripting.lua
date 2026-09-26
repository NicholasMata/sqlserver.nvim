local utils = require("sqlserver.utils")

local M = {}

---@param client vim.lsp.Client
---@param params table
---@param timeout integer|false
---@param control? { on_operation?: fun(operation_id: string, cancel: fun(): boolean), on_progress?: fun(progress: table) }
---@return table
function M.script_async(client, params, timeout, control)
  control = control or {}
  local completions = {}
  local progress_events = {}
  local waiting
  local waiting_operation_id
  local completed = false
  local cancel_requested = false
  local completion_handler
  local progress_handler
  local plan_handler

  local function unregister()
    utils.unregister_lsp_handler(client, "scripting/scriptComplete", completion_handler)
    utils.unregister_lsp_handler(client, "scripting/scriptProgressNotification", progress_handler)
    utils.unregister_lsp_handler(client, "scripting/scriptPlanNotification", plan_handler)
  end

  local function publish_progress(result)
    if not (result and result.operationId) then
      return
    end
    if result.operationId ~= waiting_operation_id then
      progress_events[result.operationId] = progress_events[result.operationId] or {}
      progress_events[result.operationId][#progress_events[result.operationId] + 1] = result
      return
    end
    if control.on_progress then
      control.on_progress(result)
    end
  end

  completion_handler = function(err, result)
    if result and result.operationId then
      completions[result.operationId] = { result = result, error = err }
      if waiting and result.operationId == waiting_operation_id and coroutine.status(waiting) == "suspended" then
        utils.try_resume(waiting)
      end
    end
    return result, err
  end
  progress_handler = function(err, result)
    publish_progress(result)
    return result, err
  end
  plan_handler = function(err, result)
    publish_progress(result)
    return result, err
  end
  utils.register_lsp_handler(client, "scripting/scriptComplete", completion_handler)
  utils.register_lsp_handler(client, "scripting/scriptProgressNotification", progress_handler)
  utils.register_lsp_handler(client, "scripting/scriptPlanNotification", plan_handler)

  local response, request_error = utils.lsp_request_async(client, "scripting/script", params)
  if request_error then
    unregister()
    error("SQL Tools Service could not script the selected object: " .. request_error.message, 0)
  end
  if not (response and response.operationId) then
    unregister()
    error("SQL Tools Service returned an invalid scripting response", 0)
  end

  waiting_operation_id = response.operationId
  for _, progress in ipairs(progress_events[response.operationId] or {}) do
    if control.on_progress then
      control.on_progress(progress)
    end
  end
  progress_events[response.operationId] = nil
  local function cancel()
    if completed then
      return false
    end
    cancel_requested = true
    local requested = client:request("scripting/scriptCancel", { operationId = response.operationId }, function() end)
    return requested ~= false
  end
  if control.on_operation then
    control.on_operation(response.operationId, cancel)
  end

  local completion = completions[response.operationId]
  if not completion then
    waiting = coroutine.running()
    if timeout then
      vim.defer_fn(function()
        if not completions[waiting_operation_id] and waiting and coroutine.status(waiting) == "suspended" then
          cancel()
          utils.try_resume(waiting)
        end
      end, timeout)
    end
    coroutine.yield()
    completion = completions[response.operationId]
  end
  completed = true
  unregister()

  if not completion then
    error("SQL Tools Service did not complete the scripting operation", 0)
  end
  if completion.error then
    error("SQL Tools Service could not script the selected object: " .. completion.error.message, 0)
  end
  if cancel_requested or completion.result.canceled then
    error({ code = "cancelled", message = "Object scripting cancelled" }, 0)
  end
  if completion.result.hasError or completion.result.success == false then
    local message = completion.result.errorMessage or "The scripting operation failed"
    error("SQL Tools Service could not script the selected object: " .. message, 0)
  end
  return response
end

return M
