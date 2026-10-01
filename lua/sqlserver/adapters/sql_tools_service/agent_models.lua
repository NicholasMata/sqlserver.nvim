local bit = require("bit")

local M = {}

local execution_status = {
  [1] = "executing",
  [2] = "waiting_for_worker",
  [3] = "between_retries",
  [4] = "idle",
  [5] = "suspended",
  [6] = "waiting_for_step",
  [7] = "completing",
  [8] = "queued",
}

local completion_result = {
  [0] = "failed",
  [1] = "succeeded",
  [2] = "retry",
  [3] = "cancelled",
  [4] = "in_progress",
  [5] = "unknown",
}

local completion_action = {
  [0] = "never",
  [1] = "on_success",
  [2] = "on_failure",
  [3] = "always",
}

local step_action = {
  [1] = "quit_success",
  [2] = "quit_failure",
  [3] = "next_step",
  [4] = "go_to_step",
}

local subsystem = {
  [1] = "transact_sql",
  [2] = "active_scripting",
  [3] = "cmd_exec",
  [4] = "snapshot",
  [5] = "log_reader",
  [6] = "distribution",
  [7] = "merge",
  [8] = "queue_reader",
  [9] = "analysis_query",
  [10] = "analysis_command",
  [11] = "ssis",
  [12] = "powershell",
}

local frequency = {
  [1] = "once",
  [4] = "daily",
  [8] = "weekly",
  [16] = "monthly",
  [32] = "monthly_relative",
  [64] = "on_agent_start",
  [128] = "on_idle",
}

local subday_frequency = {
  [1] = "once",
  [2] = "seconds",
  [4] = "minutes",
  [8] = "hours",
}

local relative_interval = {
  [1] = "first",
  [2] = "second",
  [4] = "third",
  [8] = "fourth",
  [16] = "last",
}

local alert_type = {
  [1] = "sql_server_event",
  [2] = "performance_condition",
  [3] = "non_sql_server_event",
  [4] = "wmi_event",
}

local function optional(value)
  if value == vim.NIL or value == "" then
    return nil
  end
  return value
end

local function required_text(value)
  value = optional(value)
  assert(type(value) == "string" and value ~= "", "SQL Agent response lacks an identity")
  return value
end

local function enum(value, names)
  value = optional(value)
  return value and names[tonumber(value)] or nil
end

local function date(value)
  value = optional(value)
  if type(value) == "string" and (value:match("^0?1/0?1/0001") or value:match("^0001[-/]")) then
    return nil
  end
  return value
end

local function fields(raw, mapping)
  local result = {}
  for name, source in pairs(mapping) do
    result[name] = optional(raw[source])
  end
  return result
end

local function list(raw, normalize)
  if raw == nil or raw == vim.NIL then
    return {}
  end
  assert(type(raw) == "table" and vim.islist(raw), "SQL Agent response has an invalid list")
  return vim.iter(raw):map(normalize):totable()
end

local function flags(value)
  value = optional(value)
  if value == nil then
    return nil
  end
  value = tonumber(value)
  if not value or value < 0 or bit.band(value, 7) ~= value then
    return nil
  end
  local names = {}
  for _, item in ipairs({ { 1, "email" }, { 2, "pager" }, { 4, "net_send" } }) do
    if bit.band(value, item[1]) ~= 0 then
      names[#names + 1] = item[2]
    end
  end
  return names
end

function M.job(raw)
  assert(type(raw) == "table", "SQL Agent returned an invalid job")
  local result = fields(raw, {
    name = "name",
    owner = "owner",
    description = "description",
    category = "category",
    enabled = "enabled",
    runnable = "runnable",
    has_target = "hasTarget",
    has_steps = "hasStep",
    has_schedules = "hasSchedule",
    current_step = "currentExecutionStep",
    operator_to_email = "operatorToEmail",
    operator_to_page = "operatorToPage",
    start_step_id = "startStepId",
  })
  result.id = required_text(raw.jobId):lower()
  result.name = required_text(raw.name)
  result.execution_status = enum(raw.currentExecutionStatus, execution_status)
  result.last_run_at = date(raw.lastRun)
  result.last_run_outcome = enum(raw.lastRunOutcome, completion_result)
  if not result.last_run_at and result.last_run_outcome == "unknown" then
    result.last_run_outcome = nil
  end
  result.next_run_at = date(raw.nextRun)
  result.email_level = enum(raw.emailLevel, completion_action)
  result.page_level = enum(raw.pageLevel, completion_action)
  result.event_log_level = enum(raw.eventLogLevel, completion_action)
  result.delete_level = enum(raw.deleteLevel, completion_action)
  return result
end

function M.step(raw)
  assert(type(raw) == "table", "SQL Agent returned an invalid step")
  local result = fields(raw, {
    id = "id",
    name = "stepName",
    command = "command",
    database = "databaseName",
    database_user = "databaseUserName",
    server = "server",
    proxy = "proxyName",
    retry_attempts = "retryAttempts",
    retry_interval = "retryInterval",
    success_step_id = "successStepId",
    failure_step_id = "failStepId",
    command_success_code = "commandExecutionSuccessCode",
    output_file = "outputFileName",
    append_to_log_file = "appendToLogFile",
    append_to_step_history = "appendToStepHist",
    write_log_to_table = "writeLogToTable",
    append_log_to_table = "appendLogToTable",
  })
  result.subsystem = enum(raw.subSystem, subsystem)
  result.success_action = enum(raw.successAction, step_action)
  result.failure_action = enum(raw.failureAction, step_action)
  return result
end

function M.schedule(raw)
  assert(type(raw) == "table", "SQL Agent returned an invalid schedule")
  local result = fields(raw, {
    id = "id",
    uid = "scheduleUid",
    name = "name",
    enabled = "isEnabled",
    description = "description",
    job_count = "jobCount",
    frequency_interval = "frequencyInterval",
    recurrence_factor = "frequencyRecurrenceFactor",
    subday_interval = "frequencySubDayInterval",
    active_start_time = "activeStartTimeOfDay",
    active_end_time = "activeEndTimeOfDay",
  })
  result.frequency = enum(raw.frequencyTypes, frequency)
  result.subday_frequency = enum(raw.frequencySubDayTypes, subday_frequency)
  result.relative_interval = enum(raw.frequencyRelativeIntervals, relative_interval)
  result.active_start_date = date(raw.activeStartDate)
  result.active_end_date = date(raw.activeEndDate)
  result.created_at = date(raw.dateCreated)
  return result
end

function M.alert(raw)
  assert(type(raw) == "table", "SQL Agent returned an invalid alert")
  local result = fields(raw, {
    id = "id",
    name = "name",
    enabled = "isEnabled",
    category = "categoryName",
    database = "databaseName",
    event_source = "eventSource",
    event_description_keyword = "eventDescriptionKeyword",
    severity = "severity",
    message_id = "messageId",
    performance_condition = "performanceCondition",
    wmi_event_namespace = "wmiEventNamespace",
    wmi_event_query = "wmiEventQuery",
    notification_message = "notificationMessage",
    delay_between_responses = "delayBetweenResponses",
    occurrence_count = "occurrenceCount",
    job_name = "jobName",
  })
  result.name = required_text(raw.name)
  result.type = enum(raw.alertType, alert_type)
  local job_id = optional(raw.jobId)
  result.job_id = job_id and job_id ~= "00000000-0000-0000-0000-000000000000" and job_id:lower() or nil
  result.last_occurrence_at = date(raw.lastOccurrenceDate)
  result.last_response_at = date(raw.lastResponseDate)
  result.count_reset_at = date(raw.countResetDate)
  result.include_event_description = flags(raw.includeEventDescription)
  local has_notification = tonumber(optional(raw.hasNotification))
  if has_notification ~= nil then
    result.has_notification = has_notification ~= 0
  end
  return result
end

local function history_step(raw)
  assert(type(raw) == "table", "SQL Agent returned an invalid history step")
  local result = fields(raw, {
    id = "stepId",
    name = "stepName",
    message = "message",
  })
  result.outcome = enum(raw.runStatus, completion_result)
  result.run_at = date(raw.runDate)
  if optional(raw.stepDetails) then
    result.details = M.step(raw.stepDetails)
  end
  return result
end

function M.history(raw)
  assert(type(raw) == "table", "SQL Agent returned invalid history")
  local result = fields(raw, {
    id = "instanceId",
    message = "message",
    duration = "runDuration",
    sql_message_id = "sqlMessageId",
    sql_severity = "sqlSeverity",
    server = "server",
    step_id = "stepId",
    step_name = "stepName",
    retries_attempted = "retriesAttempted",
    operator_emailed = "operatorEmailed",
    operator_paged = "operatorPaged",
    operator_netsent = "operatorNetsent",
  })
  result.outcome = enum(raw.runStatus, completion_result)
  result.run_at = date(raw.runDate)
  result.steps = list(raw.steps, history_step)
  return result
end

function M.jobs(raw)
  return list(raw, M.job)
end

function M.alerts(raw)
  return list(raw, M.alert)
end

function M.details(job, raw)
  local histories = list(raw.histories, M.history)
  return {
    job_id = job.id,
    job_name = job.name,
    history_state = #histories > 0 and "available" or "empty",
    histories = histories,
    steps = list(raw.steps, M.step),
    schedules = list(raw.schedules, M.schedule),
    linked_alerts = list(raw.alerts, M.alert),
  }
end

return M
