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

return T
