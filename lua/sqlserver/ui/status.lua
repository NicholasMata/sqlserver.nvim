local registry = require("sqlserver.core.workspace_registry")
local workspace_module = require("sqlserver.core.workspace")

local M = {}
local uv = vim.uv or vim.loop
local config = { layout = "split", alignment = "right" }

local state_details = {
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

---@param opts? { layout?: "split"|"compact", alignment?: "left"|"center"|"right" }
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  define_highlights()
  local group = vim.api.nvim_create_augroup("SqlServerHighlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlights })
end

local function get_identity(workspace)
  local connection = workspace.get_connection()
  if not connection then
    return ""
  end
  local parts = vim.tbl_filter(function(value)
    return value ~= nil and value ~= ""
  end, { connection.server, connection.database })
  return table.concat(parts, " / ")
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
  local identity = get_identity(workspace):gsub("%%", "%%%%")
  local state = get_state_details(workspace)
  local workspace_label = identity ~= "" and identity or "SQL Server"
  local status = string.format("%s %%#%s#%s%%*", state.label:gsub("%%", "%%%%"), state.highlight, state.icon)
  if config.layout == "split" then
    return workspace_label .. "%=" .. status .. " "
  end
  local content = workspace_label .. "  " .. status
  if config.alignment == "right" then
    return "%=" .. content .. " "
  elseif config.alignment == "center" then
    return "%=" .. content .. "%="
  end
  return content
end

function M.winbar()
  local workspace = registry.get()
  return workspace and M.render_winbar(workspace) or ""
end

function M.component()
  local workspace = registry.get()
  return workspace and M.render(workspace) or nil
end

return M
