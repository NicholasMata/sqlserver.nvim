local agent = require("sqlserver.adapters.sql_tools_service.agent")
local integration = require("tests.helpers.integration")
local registry = require("sqlserver.workspace.registry")

local T = MiniTest.new_set()

local function adapter(bufnr)
  return agent.create(integration.get_sql_client(bufnr), assert(registry.get(bufnr)))
end

local function find_named(items, name)
  return vim.iter(items):find(function(item)
    return item.name == name
  end)
end

T["Agent adapter normalizes seeded jobs and populated job details"] = require("tests.helpers").async(function()
  local backend = adapter(vim.api.nvim_get_current_buf())
  local job = assert(find_named(backend.list_jobs_async(), "sqlserver.nvim fixture history"))
  assert(type(job.id) == "string" and job.id ~= "")
  assert(job.enabled == true and job.execution_status == "idle")
  assert(job.last_run_outcome == "succeeded" and type(job.last_run_at) == "string")
  assert(job.jobId == nil and job.currentExecutionStatus == nil)

  local details = backend.get_job_details_async(job)
  assert(details.history_state == "available" and #details.histories > 0)
  assert(details.histories[1].outcome == "succeeded")
  assert(details.steps[1].name == "Record success" and details.steps[1].subsystem == "transact_sql")
  assert(#details.schedules > 0 and details.schedules[1].frequency == "daily")
  assert(find_named(details.linked_alerts, "sqlserver.nvim fixture linked alert"))
end)

T["Agent adapter retains no-history steps and schedules"] = require("tests.helpers").async(function()
  local backend = adapter(vim.api.nvim_get_current_buf())
  local job = assert(find_named(backend.list_jobs_async(), "sqlserver.nvim fixture no history"))
  assert(job.enabled == false and job.last_run_at == nil and job.last_run_outcome == nil)

  local details = backend.get_job_details_async(job)
  assert(details.history_state == "empty" and #details.histories == 0)
  assert(details.steps[1].name == "Never run")
  assert(#details.schedules > 0 and details.schedules[1].enabled == false)
end)

T["Agent adapter returns linked and independent server alerts"] = require("tests.helpers").async(function()
  local backend = adapter(vim.api.nvim_get_current_buf())
  local alerts = backend.list_alerts_async()
  local linked = assert(find_named(alerts, "sqlserver.nvim fixture linked alert"))
  local independent = assert(find_named(alerts, "sqlserver.nvim fixture independent alert"))
  assert(linked.type == "sql_server_event" and linked.job_id ~= nil)
  assert(independent.job_id == nil and independent.job_name == nil)
  assert(independent.severity == 17 and independent.alertType == nil)
end)

T["Agent adapter hides restricted-login error details"] = require("tests.helpers").async(function()
  local bufnr = integration.new_query_buffer()
  integration.connect_with(bufnr, {
    database = "master",
    user = "sqlserver_nvim_agent_limited",
    password = "Test_Agent_Limited_123",
  })
  local ok, err = pcall(adapter(bufnr).list_alerts_async)
  assert(not ok and err.code == "agent_permission_denied")
  assert(err.message == "Insufficient permissions to inspect SQL Agent")
  assert(err.diagnostic == nil)
end)

T["Workspace tracks Agent loads and preserves a failed refresh"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  local workspace = assert(registry.get(bufnr))
  local jobs = assert(workspace.list_agent_jobs_async())
  local job = assert(find_named(jobs, "sqlserver.nvim fixture history"))
  assert(workspace.get_agent_state("jobs").status == "ready")
  local details = assert(workspace.get_agent_job_details_async(job))
  assert(details.job_id == job.id and workspace.get_agent_state("details").job.id == job.id)
  local alerts = assert(workspace.list_agent_alerts_async())
  assert(find_named(alerts, "sqlserver.nvim fixture independent alert"))
  assert(workspace.get_active_operation() == nil)

  workspace.set_agent_backend({
    list_jobs_async = function()
      error({ code = "agent_request_failed", message = "Could not load SQL Agent jobs" }, 0)
    end,
  })
  local refreshed, err = workspace.list_agent_jobs_async()
  assert(refreshed == nil and err.code == "agent_request_failed")
  assert(workspace.get_agent_state("jobs").data[1].id == jobs[1].id)
  assert(workspace.get_active_operation() == nil)
  workspace.set_agent_backend(adapter(bufnr))
end)

T["Disconnect cancels a pending Agent request on a live workspace"] = require("tests.helpers").async(function()
  local bufnr = integration.new_query_buffer()
  integration.connect(bufnr)
  local workspace = assert(registry.get(bufnr))
  local reply
  local cancelled
  workspace.set_agent_backend(agent.create({
    request = function(_, _, _, callback)
      reply = callback
      return true, 91
    end,
    cancel_request = function(_, id)
      cancelled = id
    end,
  }, workspace))
  local done = false
  local thread = coroutine.create(function()
    assert(workspace.list_agent_jobs_async() == nil)
    done = true
  end)
  assert(coroutine.resume(thread))
  assert(workspace.get_agent_state("jobs").loading)
  workspace.disconnect_async()
  assert(vim.wait(1000, function()
    return done
  end, 10))
  reply(nil, { success = true, jobs = {} })
  assert(cancelled == 91 and workspace.get_agent_state("jobs").data == nil)
  assert(workspace.get_active_operation() == nil)
end)

T["Agent timeout ends its workspace operation and releases the request"] = require("tests.helpers").async(function()
  local bufnr = integration.new_query_buffer()
  integration.connect(bufnr)
  local workspace = assert(registry.get(bufnr))
  local cancelled
  workspace.set_agent_backend(
    agent.create({
      request = function()
        return true, 92
      end,
      cancel_request = function(_, id)
        cancelled = id
      end,
    }, workspace),
    10
  )
  local jobs, err = workspace.list_agent_jobs_async()
  assert(jobs == nil and err.code == "agent_timeout")
  assert(cancelled == 92 and workspace.get_agent_state("jobs").status == "error")
  assert(workspace.get_active_operation() == nil)
  workspace.disconnect_async()
end)

return T
