local status = require("sqlserver.ui.status")

local M = {}
local uv = vim.uv or vim.loop

local activity_buffer
local activity_window
local target_workspace
local progress_messages = {}
local active_operations = {}
local redraw_timer
local unsubscribe
local enabled = false
local config = { height = 12, native_progress = true }

local event_icons = {
  running = "◐",
  success = "✓",
  warning = "!",
  error = "✕",
  cancelled = "○",
  info = "·",
}

local native_progress_status = {
  running = "running",
  success = "success",
  warning = "failed",
  error = "failed",
  cancelled = "failed",
}

local function ensure_redraw_timer()
  if redraw_timer then
    return
  end
  redraw_timer = uv.new_timer()
  local timer = redraw_timer
  timer:start(
    0,
    250,
    vim.schedule_wrap(function()
      if redraw_timer ~= timer or timer:is_closing() then
        return
      end
      vim.cmd("redrawstatus!")
      if not next(active_operations) then
        timer:stop()
        timer:close()
        redraw_timer = nil
        return
      end
      if activity_window and vim.api.nvim_win_is_valid(activity_window) then
        M.render()
      end
    end)
  )
end

local function present_progress(workspace, event)
  if not config.native_progress or not event.operation_id then
    return
  end

  local key = workspace.bufnr .. ":" .. event.operation_id
  local progress = progress_messages[key]
    or {
      kind = "progress",
      source = "sqlserver.nvim",
      title = event.title,
      status = "running",
    }
  if event.status ~= "running" then
    progress.status = native_progress_status[event.status]
  end

  local chunks = { { event.message } }
  if event.status == "warning" then
    progress.title = nil
    chunks = {
      { event.title .. ":", "WarningMsg" },
      { " " .. event.message },
    }
  end
  local ok, id = pcall(vim.api.nvim_echo, chunks, false, progress)
  if ok and not progress.id then
    progress.id = id
  end

  if event.status == "running" then
    progress_messages[key] = progress
    ensure_redraw_timer()
  else
    progress_messages[key] = nil
  end
end

local function format_event(event)
  local icon = event_icons[event.status] or "·"
  local message = tostring(event.message):gsub("\r?\n", "  ")
  local line = string.format("%s  %s  %s", event.time, icon, message)
  if event.duration_ms then
    if event.server_duration_ms then
      line = line .. string.format("  server %.0f ms · total %.0f ms", event.server_duration_ms, event.duration_ms)
    else
      line = line .. string.format("  %.0f ms", event.duration_ms)
    end
  end
  return line
end

function M.render()
  if not (activity_buffer and vim.api.nvim_buf_is_valid(activity_buffer) and target_workspace) then
    return
  end

  local connection = target_workspace.get_connection() or {}
  local lines = {
    "SQL Server Activity",
    "",
    "Status    " .. status.render(target_workspace),
    "Server    " .. (connection.server or "—"),
    "Database  " .. (connection.database or "—"),
    "",
    "Recent activity",
  }

  local events = target_workspace.get_activity()
  for index = #events, 1, -1 do
    table.insert(lines, format_event(events[index]))
  end
  if #events == 0 then
    table.insert(lines, "No activity yet")
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = activity_buffer })
  vim.api.nvim_buf_set_lines(activity_buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = activity_buffer })
end

---@param workspace SqlServerWorkspace
function M.toggle(workspace)
  if activity_window and vim.api.nvim_win_is_valid(activity_window) then
    vim.api.nvim_win_close(activity_window, true)
    activity_window = nil
    return
  end

  target_workspace = workspace
  if not (activity_buffer and vim.api.nvim_buf_is_valid(activity_buffer)) then
    activity_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(activity_buffer, "sqlserver://activity")
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = activity_buffer })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = activity_buffer })
    vim.api.nvim_set_option_value("swapfile", false, { buf = activity_buffer })
    vim.api.nvim_set_option_value("filetype", "sqlserver-activity", { buf = activity_buffer })
    vim.keymap.set("n", "q", function()
      if activity_window and vim.api.nvim_win_is_valid(activity_window) then
        vim.api.nvim_win_close(activity_window, true)
        activity_window = nil
      end
    end, { buffer = activity_buffer, desc = "Close SQL Server activity" })
  end

  activity_window = vim.api.nvim_open_win(activity_buffer, true, { split = "below", win = 0 })
  vim.api.nvim_win_set_height(activity_window, config.height)
  M.render()
end

---@param opts? table
---@param activity_stream? SqlServerActivityStream
function M.setup(opts, activity_stream)
  config = vim.tbl_deep_extend("force", config, opts or {})
  enabled = activity_stream ~= nil
  if unsubscribe then
    unsubscribe()
    unsubscribe = nil
  end
  if activity_stream then
    unsubscribe = activity_stream.subscribe(M.on_event)
  end
end

function M.is_enabled()
  return enabled
end

---@param workspace SqlServerWorkspace
---@param event table
function M.on_event(workspace, event)
  if event.operation_id then
    local key = workspace.bufnr .. ":" .. event.operation_id
    active_operations[key] = event.status == "running" and true or nil
    if event.status == "running" then
      ensure_redraw_timer()
    end
  end
  present_progress(workspace, event)
  vim.cmd("redrawstatus!")
  if target_workspace == workspace and activity_window and vim.api.nvim_win_is_valid(activity_window) then
    M.render()
  end
end

return M
