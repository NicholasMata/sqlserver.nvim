local models = require("sqlserver.adapters.sql_tools_service.agent_models")
local utils = require("sqlserver.utils")

local M = {}

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

  local function request(method, params, label)
    if not workspace.get_connection() then
      error(failure("agent_not_connected", "Connect to SQL Server before inspecting SQL Agent"), 0)
    end
    params.ownerUri = workspace.owner_uri
    local result, err = utils.lsp_request_async(client, method, params, workspace.bufnr)
    if err then
      local code = err.code == "request_timeout" and "agent_timeout" or "agent_request_failed"
      error(failure(code, "Could not load SQL Agent " .. label), 0)
    end
    if type(result) ~= "table" or type(result.success) ~= "boolean" then
      error(failure("agent_invalid_response", "SQL Agent returned an invalid response"), 0)
    end
    return result
  end

  return {
    list_jobs_async = function()
      local result = request("agent/jobs", {}, "jobs")
      if not result.success then
        error(service_failure(result.errorMessage, "jobs"), 0)
      end
      if type(result.jobs) ~= "table" then
        error(failure("agent_invalid_response", "SQL Agent returned an invalid response"), 0)
      end
      return normalize(models.jobs, result.jobs)
    end,

    get_job_details_async = function(job)
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
      local result = request("agent/jobhistory", { jobId = job.id, jobName = job.name }, "job details")
      if not result.success and not is_empty_history(result) then
        error(service_failure(result.errorMessage, "job details"), 0)
      end
      return normalize(models.details, job, result)
    end,

    list_alerts_async = function()
      local result = request("agent/alerts", {}, "alerts")
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
