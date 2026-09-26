local registry = require("sqlserver.workspace.registry")
local workspace_module = require("sqlserver.workspace")

local M = {}
local uv = vim.uv or vim.loop
local default_config = {
  layout = "split",
  alignment = "right",
  identity = { "username", "server", "database" },
}
local config = vim.deepcopy(default_config)

local state_details = {
  [workspace_module.states.starting] = {
    icon = "◐",
    label = "Starting SQL Tools Service",
    highlight = "SqlServerWorking",
  },
  [workspace_module.states.disconnected] = {
    icon = "○",
    label = "Disconnected",
    highlight = "SqlServerDisconnected",
  },
  [workspace_module.states.connecting] = { icon = "◐", label = "Connecting", highlight = "SqlServerWorking" },
  [workspace_module.states.connected] = { icon = "●", label = "Ready", highlight = "SqlServerReady" },
  [workspace_module.states.executing] = { icon = "◐", label = "Executing", highlight = "SqlServerWorking" },
  [workspace_module.states.cancelling] = { icon = "◌", label = "Cancelling", highlight = "SqlServerCancelling" },
}

local highlight_links = {
  SqlServerReady = "DiagnosticOk",
  SqlServerWorking = "DiagnosticInfo",
  SqlServerCancelling = "DiagnosticWarn",
  SqlServerDisconnected = "NonText",
}

local function define_highlights()
  for group, link in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = link })
  end
end

---@param opts? { layout?: "split"|"compact", alignment?: "left"|"center"|"right", identity?: string[] }
function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
  define_highlights()
  local group = vim.api.nvim_create_augroup("SqlServerHighlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlights })
end

local function truncate(value, max_width)
  if vim.fn.strdisplaywidth(value) <= max_width then
    return value
  end
  if max_width <= 0 then
    return ""
  end
  if max_width == 1 then
    return "…"
  end
  local result = value
  while result ~= "" and vim.fn.strdisplaywidth(result) > max_width - 1 do
    result = vim.fn.strcharpart(result, 0, vim.fn.strchars(result) - 1)
  end
  return result .. "…"
end

local function render_identity(connection, fields, max_width)
  if not connection then
    return ""
  end
  local values = {
    username = connection.username or connection.user,
    server = connection.server,
    database = connection.database,
  }
  local function render(server)
    local parts = {}
    local index = 1
    while index <= #fields do
      local field = fields[index]
      local value = field == "server" and server or values[field]
      if field == "username" and fields[index + 1] == "server" and value ~= nil and value ~= "" then
        local next_server = server
        if next_server ~= nil and next_server ~= "" then
          parts[#parts + 1] = value .. "@" .. next_server
          index = index + 2
        else
          parts[#parts + 1] = value
          index = index + 1
        end
      else
        if value ~= nil and value ~= "" then
          parts[#parts + 1] = value
        end
        index = index + 1
      end
    end
    return table.concat(parts, " / ")
  end

  local identity = render(values.server)
  if not max_width or identity == "" or vim.fn.strdisplaywidth(identity) <= max_width then
    return identity
  end
  if values.server == nil or values.server == "" or not vim.tbl_contains(fields, "server") then
    return identity
  end
  local overflow = vim.fn.strdisplaywidth(identity) - max_width
  local server_width = math.max(1, vim.fn.strdisplaywidth(values.server) - overflow)
  return render(truncate(values.server, server_width))
end

local function get_identity(workspace, max_width)
  return render_identity(workspace.get_connection(), config.identity, max_width)
end

local function get_state_details(workspace)
  local operation = workspace.get_active_operation()
  if operation then
    local label = operation.message
    if operation.started_at_ns then
      local elapsed = (uv.hrtime() - operation.started_at_ns) / 1e9
      label = string.format("%s %.1fs", label, elapsed)
    end
    return { icon = "◐", label = label, highlight = "SqlServerWorking" }
  end
  if workspace.is_refreshing() then
    return { icon = "◐", label = "Refreshing database objects", highlight = "SqlServerWorking" }
  end
  return state_details[workspace.get_state()]
    or { icon = "?", label = workspace.get_state(), highlight = "SqlServerDisconnected" }
end

---@param workspace SqlServerWorkspace
---@return string
function M.render(workspace)
  local identity = get_identity(workspace)
  local state = get_state_details(workspace)
  local prefix = identity ~= "" and (identity .. "  ") or "SQL Server  "
  return prefix .. state.label .. " " .. state.icon
end

---@param workspace SqlServerWorkspace
---@return string
function M.render_winbar(workspace)
  local state = get_state_details(workspace)
  local status_width = vim.fn.strdisplaywidth(state.label .. " " .. state.icon)
  local spacing = config.layout == "split" and 1 or 3
  local available = math.max(0, vim.api.nvim_win_get_width(0) - status_width - spacing)
  local identity = get_identity(workspace, available):gsub("%%", "%%%%")
  local workspace_label = identity ~= "" and identity or "SQL Server"
  local status = string.format("%s %%#%s#%s%%*", state.label:gsub("%%", "%%%%"), state.highlight, state.icon)
  if config.layout == "split" then
    return "%<" .. workspace_label .. "%=" .. status .. " "
  end
  local content = workspace_label .. "  " .. status
  if config.alignment == "right" then
    return "%=%<" .. content .. " "
  elseif config.alignment == "center" then
    return "%=%<" .. content .. "%="
  end
  return "%<" .. content
end

M.format_identity = render_identity

function M.winbar()
  local workspace = registry.get()
  return workspace and M.render_winbar(workspace) or ""
end

function M.component()
  local workspace = registry.get()
  return workspace and M.render(workspace) or nil
end

return M
