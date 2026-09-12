local utils = require("sqlserver.utils")

local M = {}

---@param client vim.lsp.Client
---@param params table
---@param timeout integer|false
---@return table
function M.script_async(client, params, timeout)
  local completions = {}
  local waiting
  local waiting_operation_id
  local handler
  handler = function(err, result)
    if result and result.operationId then
      completions[result.operationId] = { result = result, error = err }
      if waiting and result.operationId == waiting_operation_id and coroutine.status(waiting) == "suspended" then
        utils.try_resume(waiting)
      end
    end
    return result, err
  end
  utils.register_lsp_handler(client, "scripting/scriptComplete", handler)

  local response, request_error = utils.lsp_request_async(client, "scripting/script", params)
  if request_error then
    utils.unregister_lsp_handler(client, "scripting/scriptComplete", handler)
    error("SQL Tools Service could not script the selected object: " .. request_error.message, 0)
  end
  if not (response and response.operationId) then
    utils.unregister_lsp_handler(client, "scripting/scriptComplete", handler)
    error("SQL Tools Service returned an invalid scripting response", 0)
  end

  local completion = completions[response.operationId]
  if not completion then
    waiting = coroutine.running()
    waiting_operation_id = response.operationId
    if timeout then
      vim.defer_fn(function()
        if not completions[waiting_operation_id] and waiting and coroutine.status(waiting) == "suspended" then
          utils.try_resume(waiting)
        end
      end, timeout)
    end
    coroutine.yield()
    completion = completions[response.operationId]
  end
  utils.unregister_lsp_handler(client, "scripting/scriptComplete", handler)

  if not completion then
    error("SQL Tools Service did not complete the scripting operation", 0)
  end
  if completion.error then
    error("SQL Tools Service could not script the selected object: " .. completion.error.message, 0)
  end
  if completion.result.hasError or completion.result.success == false then
    local message = completion.result.errorMessage or "The scripting operation failed"
    error("SQL Tools Service could not script the selected object: " .. message, 0)
  end
  return response
end

return M
