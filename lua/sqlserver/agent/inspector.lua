local M = {}

local function display(value)
  if value == nil or value == "" then
    return "Unknown"
  end
  if type(value) == "boolean" then
    return value and "Yes" or "No"
  end
  return tostring(value)
end

local function lines(fields)
  local result, marks = {}, {}
  for _, field in ipairs(fields) do
    local value = display(field[2])
    local parts = vim.split(value, "\n", { plain = true })
    local line = field[1] .. ": " .. parts[1]
    marks[#marks + 1] = {
      line = #result,
      label_end = #field[1] + 1,
      outcome = field[3],
      outcome_start = field[3] and #line - #display(field[3]) or nil,
      outcome_end = field[3] and #line or nil,
      heading = field[4],
    }
    result[#result + 1] = line
    for index = 2, #parts do
      result[#result + 1] = parts[index]
    end
  end
  return table.concat(result, "\n"), marks
end

local function property_lines(fields)
  local result, marks = {}, {}
  for _, field in ipairs(fields) do
    if field[2] ~= nil and field[2] ~= "" then
      local value = display(field[2])
      local line = #result
      if value:find("\n", 1, true) then
        result[#result + 1] = field[1] .. ":"
        vim.list_extend(result, vim.split(value, "\n", { plain = true }))
      else
        result[#result + 1] = field[1] .. ": " .. value
      end
      marks[#marks + 1] = { line = line, label = field[1], value = value, label_end = #field[1] + 1 }
    end
  end
  return result, marks
end

local function entry(label, fields)
  local result, marks = property_lines(fields)
  return { label = label, lines = result, marks = marks }
end

function M.properties(job, data)
  local overview = {
    entry("Overview", {
      { "Job", job.name },
      { "Description", job.description },
      { "Owner", job.owner },
      { "Category", job.category },
      { "Enabled", job.enabled },
      { "Execution", job.execution_status },
      { "Current step", job.current_step },
      { "Last outcome", job.last_run_outcome },
      { "Last run", job.last_run_at },
      { "Next run", job.next_run_at },
    }),
  }
  local steps = {}
  for index, step in ipairs(data.steps or {}) do
    steps[#steps + 1] = entry(("Step %d · %s"):format(step.id or index, display(step.name)), {
      { "Name", step.name },
      { "Subsystem", step.subsystem },
      { "Database", step.database },
      { "Server", step.server },
      { "Proxy", step.proxy },
      { "Retry attempts", step.retry_attempts },
      { "Retry interval", step.retry_interval },
      { "Command", step.command },
    })
  end
  local schedules = {}
  for _, schedule in ipairs(data.schedules or {}) do
    schedules[#schedules + 1] = entry("Schedule · " .. display(schedule.name), {
      { "Name", schedule.name },
      { "Enabled", schedule.enabled },
      { "Frequency", schedule.frequency },
      { "Start time", schedule.active_start_time },
      { "End time", schedule.active_end_time },
      { "Start date", schedule.active_start_date },
      { "End date", schedule.active_end_date },
    })
  end
  local alerts = {}
  for _, alert in ipairs(data.linked_alerts or {}) do
    alerts[#alerts + 1] = entry("Linked alert · " .. display(alert.name), {
      { "Name", alert.name },
      { "Type", alert.type },
      { "Enabled", alert.enabled },
      { "Description", alert.event_description_keyword },
    })
  end
  return {
    { label = "Overview", entries = overview },
    { label = "Steps", entries = steps },
    { label = "Schedules", entries = schedules },
    { label = "Linked alerts", entries = alerts },
  }
end

function M.history(data)
  local result = {}
  for index, run in ipairs(data.histories or {}) do
    local fields = {
      { "Run", run.run_at },
      { "Outcome", run.outcome, run.outcome },
      { "Duration", run.duration },
      { "Message", run.message },
    }
    for step_index, step in ipairs(run.steps or {}) do
      fields[#fields + 1] = {
        ("Step %d"):format(step.id or step_index),
        ("%s · %s"):format(display(step.name), display(step.outcome)),
        step.outcome,
        true,
      }
      if step.message then
        fields[#fields + 1] = { ("Step %d message"):format(step.id or step_index), step.message }
      end
    end
    local detail, marks = lines(fields)
    result[#result + 1] = {
      text = ("%s · %s · %s"):format(display(run.run_at), display(run.outcome), display(run.duration)),
      label = ("%s · %s · %s"):format(display(run.run_at), display(run.outcome), display(run.duration)),
      run_at = display(run.run_at),
      detail = detail,
      marks = marks,
    }
  end
  return result
end

return M
