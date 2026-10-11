local agent = require("sqlserver.adapters.sql_tools_service.agent")
local utils = require("sqlserver.utils")

local T = MiniTest.new_set()

local function backend(responses, connected)
  local requests = {}
  local original = utils.lsp_request_async
  utils.lsp_request_async = function(_, method, params, bufnr)
    requests[#requests + 1] = { method = method, params = params, bufnr = bufnr }
    local item = responses[method]
    return item and item.result, item and item.error
  end
  local adapter = agent.create({}, {
    owner_uri = "file:///current-query.sql",
    bufnr = 17,
    get_connection = function()
      return connected ~= false and { id = "connection" } or nil
    end,
  })
  return adapter, requests, function()
    utils.lsp_request_async = original
  end
end

T["Agent jobs keep identity and normalize status without protocol fields"] = function()
  local adapter, requests, restore = backend({
    ["agent/jobs"] = {
      result = {
        success = true,
        jobs = {
          {
            jobId = "ABCDEF12-1234-1234-1234-123456789ABC",
            name = "Nightly backup",
            enabled = false,
            currentExecutionStatus = 4,
            lastRunOutcome = 1,
            lastRun = "2026-09-29T02:00:00",
            nextRun = "2026-09-30T02:00:00",
            hasStep = true,
            hasSchedule = true,
            owner = "sa",
            jobSteps = { { command = "private" } },
          },
        },
      },
    },
  })
  local ok, jobs = pcall(adapter.list_jobs_async)
  restore()
  assert(ok, jobs)
  assert(#jobs == 1)
  assert(jobs[1].id == "abcdef12-1234-1234-1234-123456789abc")
  assert(jobs[1].name == "Nightly backup" and jobs[1].enabled == false)
  assert(jobs[1].execution_status == "idle" and jobs[1].last_run_outcome == "succeeded")
  assert(jobs[1].last_run_at == "2026-09-29T02:00:00" and jobs[1].next_run_at == "2026-09-30T02:00:00")
  assert(jobs[1].has_steps == true and jobs[1].has_schedules == true)
  assert(jobs[1].jobId == nil and jobs[1].jobSteps == nil and jobs[1].currentExecutionStatus == nil)
  assert(requests[1].method == "agent/jobs")
  assert(requests[1].params.ownerUri == "file:///current-query.sql" and requests[1].bufnr == 17)
end

T["Agent jobs preserve empty lists and omit missing or sentinel values"] = function()
  local adapter, _, restore = backend({
    ["agent/jobs"] = {
      result = {
        success = true,
        jobs = {
          {
            jobId = "Job-1",
            name = "Never run",
            lastRun = "1/1/0001 12:00:00 AM",
            lastRunOutcome = 5,
            nextRun = vim.NIL,
            currentExecutionStatus = 99,
            description = vim.NIL,
          },
        },
      },
    },
  })
  local ok, jobs = pcall(adapter.list_jobs_async)
  restore()
  assert(ok, jobs)
  assert(jobs[1].last_run_at == nil and jobs[1].last_run_outcome == nil)
  assert(jobs[1].next_run_at == nil and jobs[1].execution_status == nil)
  assert(jobs[1].description == nil)

  adapter, _, restore = backend({ ["agent/jobs"] = { result = { success = true, jobs = {} } } })
  ok, jobs = pcall(adapter.list_jobs_async)
  restore()
  assert(ok and vim.deep_equal(jobs, {}))
end

T["No-history details retain steps and schedules as normalized models"] = function()
  local adapter, requests, restore = backend({
    ["agent/jobhistory"] = {
      result = {
        success = false,
        errorMessage = vim.NIL,
        histories = vim.NIL,
        steps = {
          {
            id = 1,
            stepName = "Run query",
            subSystem = 1,
            successAction = 1,
            failureAction = 2,
            command = "SELECT 1;",
            databaseName = "master",
          },
        },
        schedules = {
          {
            id = 7,
            scheduleUid = "SCHEDULE-UID",
            name = "Daily",
            isEnabled = false,
            frequencyTypes = 4,
            frequencySubDayTypes = 1,
            frequencyRelativeIntervals = 0,
            activeStartTimeOfDay = "01:00:00",
          },
        },
        alerts = {},
      },
    },
  })
  local ok, details = pcall(adapter.get_job_details_async, { id = "job-id", name = "Never run" })
  restore()
  assert(ok, details)
  assert(details.job_id == "job-id" and details.job_name == "Never run")
  assert(details.history_state == "empty" and #details.histories == 0)
  assert(details.steps[1].subsystem == "transact_sql")
  assert(details.steps[1].success_action == "quit_success")
  assert(details.steps[1].failure_action == "quit_failure")
  assert(details.steps[1].database == "master" and details.steps[1].stepName == nil)
  assert(details.schedules[1].frequency == "daily" and details.schedules[1].enabled == false)
  assert(details.schedules[1].subday_frequency == "once")
  assert(details.schedules[1].relative_interval == nil)
  assert(requests[1].params.jobId == "job-id" and requests[1].params.jobName == "Never run")
  assert(requests[1].params.ownerUri == "file:///current-query.sql")
end

T["History and linked alerts remain separate from the server-wide alert list"] = function()
  local linked = {
    id = 4,
    name = "Job alert",
    jobId = "JOB-ID",
    jobName = "Job",
    alertType = 1,
    isEnabled = true,
    severity = 16,
    includeEventDescription = 5,
    hasNotification = 0,
  }
  local independent = {
    id = 5,
    name = "Server alert",
    jobId = "00000000-0000-0000-0000-000000000000",
    jobName = "",
    alertType = 2,
    performanceCondition = "CPU > 90",
    isEnabled = false,
    occurrenceCount = 2,
    lastOccurrenceDate = "2026-09-29T03:00:00",
  }
  local adapter, _, restore = backend({
    ["agent/jobhistory"] = {
      result = {
        success = true,
        histories = {
          {
            instanceId = 12,
            runStatus = 1,
            runDate = "2026-09-29T02:00:00",
            steps = { { stepId = "1", runStatus = 1, stepDetails = { id = 1, stepName = "Run query" } } },
          },
        },
        steps = {},
        schedules = {},
        alerts = { linked },
      },
    },
    ["agent/alerts"] = { result = { success = true, alerts = { linked, independent } } },
  })
  local ok, details = pcall(adapter.get_job_details_async, { id = "job-id", name = "Job" })
  local alerts_ok, alerts = pcall(adapter.list_alerts_async)
  restore()
  assert(ok, details)
  assert(alerts_ok, alerts)
  assert(details.history_state == "available" and details.histories[1].outcome == "succeeded")
  assert(details.histories[1].steps[1].details.name == "Run query")
  assert(#details.linked_alerts == 1 and details.linked_alerts[1].name == "Job alert")
  assert(#alerts == 2 and alerts[2].name == "Server alert")
  assert(alerts[1].job_id == "job-id" and alerts[2].job_id == nil and alerts[2].job_name == nil)
  assert(alerts[1].type == "sql_server_event" and alerts[2].type == "performance_condition")
  assert(vim.deep_equal(alerts[1].include_event_description, { "email", "net_send" }))
  assert(alerts[1].has_notification == false and alerts[2].occurrence_count == 2)
  assert(alerts[2].performance_condition == "CPU > 90" and alerts[2].last_occurrence_at == "2026-09-29T03:00:00")
  assert(alerts[1].alertType == nil and alerts[1].isEnabled == nil)
end

T["Agent failures have stable codes and never expose server errors"] = function()
  local cases = {
    {
      response = { success = false, errorMessage = "SQL Server Agent is not supported on this edition of SQL Server" },
      code = "agent_unavailable",
    },
    {
      response = { success = false, errorMessage = "permission was denied; secret stack trace" },
      code = "agent_permission_denied",
    },
    {
      response = { success = false, errorMessage = "server failure; secret stack trace" },
      code = "agent_request_failed",
    },
    { response = { success = true, jobs = vim.NIL }, code = "agent_invalid_response" },
  }
  for _, case in ipairs(cases) do
    local adapter, _, restore = backend({ ["agent/jobs"] = { result = case.response } })
    local ok, err = pcall(adapter.list_jobs_async)
    restore()
    assert(not ok and err.code == case.code)
    assert(not tostring(err):find("secret", 1, true))
    assert(err.diagnostic == nil and err.method == nil)
  end
end

T["Unproven no-history and disconnected requests fail safely"] = function()
  for _, missing in ipairs({ vim.NIL, {} }) do
    local adapter, _, restore = backend({
      ["agent/jobhistory"] = {
        result = {
          success = false,
          errorMessage = vim.NIL,
          histories = vim.NIL,
          steps = missing,
          schedules = missing,
        },
      },
    })
    local ok, err = pcall(adapter.get_job_details_async, { id = "job-id", name = "Job" })
    restore()
    assert(not ok and err.code == "agent_request_failed")
  end

  local adapter, _, restore = backend({}, false)
  local ok, err = pcall(adapter.list_alerts_async)
  restore()
  assert(not ok and err.code == "agent_not_connected")
end

T["Agent request timeout cancels LSP request and ignores a late reply"] = require("tests.helpers").async(function()
  local reply
  local cancelled
  local client = {
    request = function(_, method, _, callback)
      assert(method == "agent/jobs")
      reply = callback
      return true, 42
    end,
    cancel_request = function(_, id)
      cancelled = id
    end,
  }
  local adapter = agent.create(client, {
    owner_uri = "file:///agent.sql",
    bufnr = 17,
    get_connection = function()
      return {}
    end,
  })
  local control = {}
  local ok, err = pcall(adapter.list_jobs_async, control, 10)
  assert(not ok and err.code == "agent_timeout")
  assert(cancelled == 42 and control.cancel == nil)
  reply(nil, { success = true, jobs = {} })
end)

return T
