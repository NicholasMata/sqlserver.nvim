local utils = require("sqlserver.utils")

local M = {}
local timeout = 10000

local function wait_for_notification_async(client, method, session_id, owner)
  local coroutine_handle = coroutine.running()
  local completed = false
  local handler
  local disconnected

  local function unregister()
    utils.unregister_lsp_handler(client, method, handler)
    utils.unregister_lsp_handler(client, "objectexplorer/sessionDisconnected", disconnected)
  end

  local function complete(result, err)
    if completed then
      return
    end
    completed = true
    unregister()
    if owner then
      owner.cancel_active = nil
    end
    utils.try_resume(coroutine_handle, result, err)
  end

  handler = function(err, result)
    if completed or (session_id and result and result.sessionId and result.sessionId ~= session_id) then
      return result, err
    end
    complete(result, err)
    return result, err
  end
  disconnected = function(err, result)
    if completed or (session_id and result and result.sessionId and result.sessionId ~= session_id) then
      return result, err
    end
    local message = err and err.message
      or result and (result.errorMessage or result.message)
      or "The SQL Tools Service Object Explorer session disconnected"
    complete(nil, { message = message })
    return result, err
  end
  utils.register_lsp_handler(client, method, handler)
  utils.register_lsp_handler(client, "objectexplorer/sessionDisconnected", disconnected)
  if timeout then
    vim.defer_fn(function()
      if completed then
        return
      end
      complete(nil, { message = "SQL Server Object Explorer request timed out" })
    end, timeout)
  end
  if owner then
    owner.cancel_active = function(message)
      complete(nil, { message = message or "Object Explorer session closed" })
    end
  end
  return coroutine.yield()
end

local function request_async(client, method, params, notification, session_id, owner)
  local _, request_error = utils.lsp_request_async(client, method, params)
  if request_error then
    return nil, request_error
  end
  return wait_for_notification_async(client, notification, session_id, owner)
end

function M.open_async(client, connection_options)
  local options = vim.deepcopy(connection_options)
  options.ServerName = options.server
  options.DatabaseName = options.database
  options.UserName = options.user
  options.EnclaveAttestationProtocol = options.attestationProtocol
  options.DatabaseDisplayName = options.DatabaseDisplayName or options.database

  local result, err = request_async(client, "objectexplorer/createsession", options, "objectexplorer/sessioncreated")
  if err then
    error(err.message or tostring(err), 0)
  end
  if not (result and result.sessionId and result.rootNode and result.rootNode.nodePath) then
    error("SQL Tools Service returned an invalid Object Explorer session", 0)
  end

  local session = {
    id = result.sessionId,
    root = result.rootNode,
    closed = false,
    queue = {},
    processing = false,
  }

  local function resume_job(job, nodes, err)
    if coroutine.status(job.coroutine) == "suspended" then
      utils.try_resume(job.coroutine, nodes, err)
    end
  end

  local function process_queue()
    if session.processing or session.closed then
      return
    end
    session.processing = true
    utils.try_resume(coroutine.create(function()
      while not session.closed and #session.queue > 0 do
        local job = table.remove(session.queue, 1)
        local method = job.refresh and "objectexplorer/refresh" or "objectexplorer/expand"
        local expanded, expand_error = request_async(client, method, {
          sessionId = session.id,
          nodePath = job.node_path,
        }, "objectexplorer/expandCompleted", session.id, session)
        if expand_error then
          resume_job(job, nil, expand_error.message or tostring(expand_error))
        elseif expanded and type(expanded.errorMessage) == "string" and expanded.errorMessage ~= "" then
          resume_job(job, nil, expanded.errorMessage)
        elseif not (expanded and type(expanded.nodes) == "table") then
          resume_job(job, nil, "SQL Tools Service returned an invalid Object Explorer expansion")
        else
          resume_job(job, expanded.nodes)
        end
      end
      if session.closed then
        for _, job in ipairs(session.queue) do
          resume_job(job, nil, "Object Explorer session is closed")
        end
        session.queue = {}
      end
      session.processing = false
    end))
  end

  function session.expand_async(node_path, refresh)
    if session.closed then
      error("Object Explorer session is closed", 0)
    end
    local job = { node_path = node_path, refresh = refresh, coroutine = coroutine.running() }
    session.queue[#session.queue + 1] = job
    process_queue()
    local nodes, expand_error = coroutine.yield()
    if expand_error then
      error(expand_error, 0)
    end
    return nodes
  end

  function session.close()
    if session.closed then
      return false
    end
    session.closed = true
    if session.cancel_active then
      session.cancel_active("Object Explorer session is closed")
    end
    for _, job in ipairs(session.queue) do
      resume_job(job, nil, "Object Explorer session is closed")
    end
    session.queue = {}
    client:request("objectexplorer/closesession", { sessionId = session.id }, function() end)
    return true
  end

  return session
end

function M.setup(timeouts)
  timeout = timeouts.object_explorer
end

return M
