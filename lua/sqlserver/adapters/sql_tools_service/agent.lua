local models = require("sqlserver.adapters.sql_tools_service.agent_models")
local utils = require("sqlserver.utils")

local M = {}

local function controlled_request(client, method, params, bufnr, control, timeout)
  local thread = assert(coroutine.running(), "SQL Agent requests require a coroutine")
  local timer
  local request_id
  local finished = false
  local function complete(result, err)
    if finished then
      return
    end
    finished = true
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    control.cancel = nil
    vim.schedule(function()
      if coroutine.status(thread) == "suspended" then
        local ok, resume_error = coroutine.resume(thread, result, err)
        if not ok then
          vim.schedule(function()
            error(resume_error, 0)
          end)
        end
      end
    end)
  end
  control.cancel = function(reason)
    if finished then
      return false
    end
    if request_id and client.cancel_request then
      pcall(client.cancel_request, client, request_id)
    end
    complete(nil, { code = reason or "agent_cancelled" })
    return true
  end
  if timeout then
    timer = (vim.uv or vim.loop).new_timer()
    timer:start(
      timeout,
      0,
      vim.schedule_wrap(function()
        control.cancel("request_timeout")
      end)
    )
  end
  local requested, sent, id = pcall(client.request, client, method, params, function(err, result)
    complete(result, err)
  end, bufnr)
  request_id = id
  if not requested or not sent then
    complete(nil, { code = "agent_request_failed" })
  end
  return coroutine.yield()
end

local function failure(code, message)
  return setmetatable({ code = code, message = message }, {
    __tostring = function(err)
      return err.message
    end,
  })
end

local function service_failure(message, label)
  local evidence = type(message) == "string" and message:lower() or ""
  if evidence:find("not supported on this edition", 1, true) then
    return failure("agent_unavailable", "SQL Agent is unavailable on this server")
  end
  if evidence:find("permission", 1, true) and evidence:find("denied", 1, true) then
    return failure("agent_permission_denied", "Insufficient permissions to inspect SQL Agent")
  end
  return failure("agent_request_failed", "Could not load SQL Agent " .. label)
end

local function normalize(fn, ...)
  local ok, value = pcall(fn, ...)
  if not ok then
    error(failure("agent_invalid_response", "SQL Agent returned an invalid response"), 0)
  end
  return value
end

local function is_empty_history(raw)
  local histories = raw.histories
  return raw.success == false
    and (raw.errorMessage == nil or raw.errorMessage == vim.NIL or raw.errorMessage == "")
    and (histories == nil or histories == vim.NIL or (type(histories) == "table" and next(histories) == nil))
    and type(raw.steps) == "table"
    and type(raw.schedules) == "table"
    and (next(raw.steps) ~= nil or next(raw.schedules) ~= nil)
end

---@param client vim.lsp.Client
---@param workspace SqlServerWorkspace
---@return table
function M.create(client, workspace)
  assert(client and workspace and type(workspace.owner_uri) == "string" and workspace.owner_uri ~= "")
  assert(type(workspace.get_connection) == "function", "A connected SQL Server workspace is required")

  local function request(method, params, label, control, timeout)
    if not workspace.get_connection() then
      error(failure("agent_not_connected", "Connect to SQL Server before inspecting SQL Agent"), 0)
    end
    params.ownerUri = workspace.owner_uri
    local result, err
    if control then
      result, err = controlled_request(client, method, params, workspace.bufnr, control, timeout)
    else
      result, err = utils.lsp_request_async(client, method, params, workspace.bufnr)
    end
    if err then
      if err.code == "agent_cancelled" then
        error(failure("agent_cancelled", "SQL Agent request cancelled"), 0)
      end
      local code = err.code == "request_timeout" and "agent_timeout" or "agent_request_failed"
      local message = code == "agent_timeout" and "SQL Agent request timed out" or "Could not load SQL Agent " .. label
      error(failure(code, message), 0)
    end
    if type(result) ~= "table" or type(result.success) ~= "boolean" then
      error(failure("agent_invalid_response", "SQL Agent returned an invalid response"), 0)
    end
    return result
  end

  return {
    list_jobs_async = function(control, timeout)
      local result = request("agent/jobs", {}, "jobs", control, timeout)
      if not result.success then
        error(service_failure(result.errorMessage, "jobs"), 0)
      end
      if type(result.jobs) ~= "table" then
        error(failure("agent_invalid_response", "SQL Agent returned an invalid response"), 0)
      end
      return normalize(models.jobs, result.jobs)
    end,

    get_job_details_async = function(job, control, timeout)
      if
        not (
          type(job) == "table"
          and type(job.id) == "string"
          and job.id ~= ""
          and type(job.name) == "string"
          and job.name ~= ""
        )
      then
        error(failure("agent_invalid_job", "Select a SQL Agent job before loading its details"), 0)
      end
      local result =
        request("agent/jobhistory", { jobId = job.id, jobName = job.name }, "job details", control, timeout)
      if not result.success and not is_empty_history(result) then
        error(service_failure(result.errorMessage, "job details"), 0)
      end
      return normalize(models.details, job, result)
    end,

    list_alerts_async = function(control, timeout)
      local result = request("agent/alerts", {}, "alerts", control, timeout)
      if not result.success then
        error(service_failure(result.errorMessage, "alerts"), 0)
      end
      if type(result.alerts) ~= "table" then
        error(failure("agent_invalid_response", "SQL Agent returned an invalid response"), 0)
      end
      return normalize(models.alerts, result.alerts)
    end,
  }
end

return M
