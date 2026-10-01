local integration = require("tests.helpers.integration")
local utils = require("sqlserver.utils")

local T = MiniTest.new_set()

local history_job_name = "sqlserver.nvim fixture history"
local no_history_job_name = "sqlserver.nvim fixture no history"
local linked_alert_name = "sqlserver.nvim fixture linked alert"
local independent_alert_name = "sqlserver.nvim fixture independent alert"

local function request(bufnr, method, params)
  local result, err = utils.lsp_request_async(integration.get_sql_client(bufnr), method, params, bufnr)
  assert(not err, method .. " failed at the transport layer")
  assert(result, method .. " returned no response")
  return result
end

local function find_named(items, name)
  return vim.iter(items or {}):find(function(item)
    return item.name == name
  end)
end

local function fixture_jobs(bufnr)
  local response = request(bufnr, "agent/jobs", { ownerUri = utils.lsp_file_uri(bufnr) })
  assert(response.success == true, "Agent fixture jobs could not be listed")
  assert(type(response.jobs) == "table", "Agent fixture jobs were not returned as a list")
  return response.jobs
end

local function job_history(bufnr, job)
  return request(bufnr, "agent/jobhistory", {
    ownerUri = utils.lsp_file_uri(bufnr),
    jobId = job.jobId,
    jobName = job.name,
  })
end

T["Seeded Agent jobs include history, steps, schedules, and linked alerts"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  local jobs = fixture_jobs(bufnr)
  local job = assert(find_named(jobs, history_job_name), "History fixture job was not listed")
  assert(job.enabled == true and job.hasStep == true and job.hasSchedule == true)
  assert(type(job.jobId) == "string" and job.jobId ~= "")

  local history = job_history(bufnr, job)
  assert(history.success == true, "History fixture job details failed")
  assert(type(history.histories) == "table" and #history.histories > 0)
  assert(type(history.steps) == "table" and #history.steps > 0)
  assert(type(history.schedules) == "table" and #history.schedules > 0)
  assert(find_named(history.alerts, linked_alert_name), "Job-linked alert was absent from job details")
end)

T["Never-run Agent job retains details when history reports failure"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  local job = assert(find_named(fixture_jobs(bufnr), no_history_job_name))
  assert(job.enabled == false and job.hasStep == true and job.hasSchedule == true)

  local history = job_history(bufnr, job)
  assert(history.success == false, "Pinned service no-history response changed")
  assert(history.errorMessage == nil or history.errorMessage == vim.NIL or history.errorMessage == "")
  assert(type(history.histories) ~= "table" or #history.histories == 0)
  assert(type(history.steps) == "table" and #history.steps > 0)
  assert(type(history.schedules) == "table" and #history.schedules > 0)
end)

T["Agent alerts include linked and independent alerts"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  local response = request(bufnr, "agent/alerts", { ownerUri = utils.lsp_file_uri(bufnr) })
  assert(response.success == true and type(response.alerts) == "table")
  local linked = assert(find_named(response.alerts, linked_alert_name))
  local independent = assert(find_named(response.alerts, independent_alert_name))
  assert(linked.jobName == history_job_name)
  assert(independent.jobName == "" and independent.jobId == "00000000-0000-0000-0000-000000000000")
end)

T["Agent role member with no owned jobs receives an empty list"] = require("tests.helpers").async(function()
  local bufnr = integration.new_query_buffer()
  integration.connect_with(bufnr, {
    database = "master",
    user = "sqlserver_nvim_agent_empty",
    password = "Test_Agent_Empty_123",
  })
  local response = request(bufnr, "agent/jobs", { ownerUri = utils.lsp_file_uri(bufnr) })
  assert(response.success == true and type(response.jobs) == "table" and #response.jobs == 0)
end)

T["Agent requests preserve restricted-login permission failures"] = require("tests.helpers").async(function()
  local admin_bufnr = vim.api.nvim_get_current_buf()
  local job = assert(find_named(fixture_jobs(admin_bufnr), history_job_name))
  local bufnr = integration.new_query_buffer()
  integration.connect_with(bufnr, {
    database = "master",
    user = "sqlserver_nvim_agent_limited",
    password = "Test_Agent_Limited_123",
  })
  local owner_uri = utils.lsp_file_uri(bufnr)
  for _, request_case in ipairs({
    { method = "agent/jobs", params = { ownerUri = owner_uri } },
    { method = "agent/jobhistory", params = { ownerUri = owner_uri, jobId = job.jobId, jobName = job.name } },
    { method = "agent/alerts", params = { ownerUri = owner_uri } },
  }) do
    local response = request(bufnr, request_case.method, request_case.params)
    assert(response.success == false, request_case.method .. " did not report a permission failure")
    assert(type(response.errorMessage) == "string")
    assert(
      response.errorMessage:lower():find("permission", 1, true),
      request_case.method .. " lacked permission evidence"
    )
  end
end)

return T
