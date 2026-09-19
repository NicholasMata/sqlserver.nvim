local M = {}

local config = { height = "auto" }
local views = {}

local function value_or_dash(value)
  if value == nil or value == "" or value == vim.NIL then
    return "—"
  end
  if type(value) == "boolean" then
    return value and "Yes" or "No"
  end
  if type(value) == "table" then
    return vim.inspect(value, { newline = " ", indent = "" })
  end
  return tostring(value)
end

local function add_field(lines, label, value)
  table.insert(lines, string.format("%-17s %s", label, value_or_dash(value)))
end

local function format_lines(workspace)
  local info = workspace.get_connection_info() or {}
  local server = info.server_info or {}
  local lines = { "SQL Server Connection", "", "Connection" }
  add_field(lines, "Username", info.username)
  add_field(lines, "Server", info.server)
  add_field(lines, "Database", info.database)
  add_field(lines, "Session ID", info.server_connection_id)
  add_field(lines, "Connection ID", info.connection_id)
  add_field(lines, "Supported", info.is_supported_version)

  table.insert(lines, "")
  table.insert(lines, "Server")
  add_field(lines, "Version", server.version)
  add_field(lines, "Edition", server.edition)
  add_field(lines, "Level", server.level)
  add_field(lines, "Engine edition", server.engine_edition_id)
  add_field(lines, "Cloud", server.is_cloud)
  add_field(lines, "Azure version", server.azure_version)
  add_field(lines, "Machine", server.machine_name)
  add_field(lines, "Operating system", server.os_version)
  add_field(lines, "CPU count", server.cpu_count)
  add_field(lines, "Physical memory", server.physical_memory_mb and (server.physical_memory_mb .. " MB"))
  add_field(lines, "Options", server.options)
  return lines
end

local function close_view(source_bufnr)
  local view = views[source_bufnr]
  if not view then
    return
  end
  if view.window and vim.api.nvim_win_is_valid(view.window) then
    pcall(vim.api.nvim_win_close, view.window, true)
  end
  view.window = nil
end

local function dispose_view(source_bufnr)
  local view = views[source_bufnr]
  if not view then
    return
  end
  close_view(source_bufnr)
  if vim.api.nvim_buf_is_valid(view.buffer) then
    vim.api.nvim_buf_delete(view.buffer, { force = true })
  end
  views[source_bufnr] = nil
end

local function show_help()
  vim.lsp.util.open_floating_preview({ "r  Refresh", "q  Close", "?  Show mappings" }, "plaintext", {
    border = "single",
    title = " Connection Information ",
  })
end

---@param source_bufnr integer
function M.render(source_bufnr)
  local view = views[source_bufnr]
  if not (view and vim.api.nvim_buf_is_valid(view.buffer)) then
    return false
  end
  vim.api.nvim_set_option_value("readonly", false, { buf = view.buffer })
  vim.api.nvim_set_option_value("modifiable", true, { buf = view.buffer })
  vim.api.nvim_buf_set_lines(view.buffer, 0, -1, false, format_lines(view.workspace))
  vim.api.nvim_set_option_value("modifiable", false, { buf = view.buffer })
  vim.api.nvim_set_option_value("readonly", true, { buf = view.buffer })
  return true
end

---@param workspace SqlServerWorkspace
function M.show(workspace)
  local source_bufnr = workspace.bufnr
  local source_height = vim.api.nvim_win_get_height(0)
  local view = views[source_bufnr]
  if not (view and vim.api.nvim_buf_is_valid(view.buffer)) then
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buffer, "sqlserver://connection/" .. source_bufnr)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buffer })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buffer })
    vim.api.nvim_set_option_value("swapfile", false, { buf = buffer })
    vim.api.nvim_set_option_value("filetype", "sqlserver-connection", { buf = buffer })
    vim.api.nvim_set_option_value("readonly", true, { buf = buffer })
    vim.api.nvim_set_option_value("modifiable", false, { buf = buffer })
    view = { buffer = buffer, workspace = workspace }
    views[source_bufnr] = view
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = source_bufnr,
      once = true,
      callback = function()
        dispose_view(source_bufnr)
      end,
    })
    vim.keymap.set("n", "r", function()
      M.render(source_bufnr)
    end, { buffer = buffer, desc = "Refresh SQL Server connection information" })
    vim.keymap.set("n", "q", function()
      close_view(source_bufnr)
    end, { buffer = buffer, desc = "Close SQL Server connection information" })
    vim.keymap.set("n", "?", show_help, { buffer = buffer, desc = "Show connection information mappings" })
  else
    view.workspace = workspace
  end

  if view.window and vim.api.nvim_win_is_valid(view.window) then
    vim.api.nvim_set_current_win(view.window)
  else
    view.window = vim.api.nvim_open_win(view.buffer, true, { split = "below", win = 0 })
    local height = config.height
    if height == "auto" then
      height = math.min(#format_lines(workspace), math.max(1, math.floor(source_height * 0.5)))
    end
    vim.api.nvim_win_set_height(view.window, height)
  end
  M.render(source_bufnr)
  return view.buffer
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", { height = "auto" }, opts or {})
end

M.format_lines = format_lines
M.dispose = dispose_view

return M
