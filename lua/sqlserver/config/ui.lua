local M = {}

---@param value boolean|table
---@return { enabled: boolean, layout: "split"|"compact", alignment: "left"|"center"|"right", identity: string[] }
function M.normalize_winbar(value)
  local defaults = {
    enabled = true,
    layout = "split",
    alignment = "right",
    identity = { "username", "server", "database" },
  }
  local winbar
  if value == true then
    winbar = vim.deepcopy(defaults)
  elseif value == false then
    winbar = vim.tbl_extend("force", vim.deepcopy(defaults), { enabled = false })
  elseif type(value) == "table" then
    winbar = vim.tbl_deep_extend("keep", vim.deepcopy(value), defaults)
  else
    error("ui.winbar must be true, false, or a table", 0)
  end

  if not vim.tbl_contains({ "left", "center", "right" }, winbar.alignment) then
    error("ui.winbar.alignment must be 'left', 'center', or 'right'", 0)
  end
  if not vim.tbl_contains({ "split", "compact" }, winbar.layout) then
    error("ui.winbar.layout must be 'split' or 'compact'", 0)
  end
  if not vim.islist(winbar.identity) then
    error("ui.winbar.identity must be a list", 0)
  end
  local seen = {}
  for _, field in ipairs(winbar.identity) do
    if not vim.tbl_contains({ "username", "server", "database" }, field) then
      error("ui.winbar.identity values must be 'username', 'server', or 'database'", 0)
    end
    if seen[field] then
      error("ui.winbar.identity must not contain duplicate fields", 0)
    end
    seen[field] = true
  end
  return winbar
end

---@param value "auto"|"select"|"snacks"|function
---@return function
function M.normalize_object_picker(value)
  if type(value) == "function" then
    return value
  end
  if value == "select" then
    return require("sqlserver.objects.ui.select").select
  end
  if value == "auto" then
    local has_snacks = pcall(require, "snacks")
    return has_snacks and require("sqlserver.objects.ui.snacks").select or require("sqlserver.objects.ui.select").select
  end
  if value == "snacks" then
    return require("sqlserver.objects.ui.snacks").select
  end
  error("ui.object_picker must be 'auto', 'select', 'snacks', or a function", 0)
end

---@param value table
---@return table
function M.normalize_object_explorer(value)
  if type(value) ~= "table" then
    error("ui.object_explorer must be a table of Snacks picker options", 0)
  end
  return vim.deepcopy(value)
end

local function normalize_height(value, option, allow_auto)
  if allow_auto and value == "auto" then
    return value
  end
  if type(value) ~= "number" or value < 1 or value % 1 ~= 0 then
    local expected = allow_auto and "'auto' or a positive integer" or "a positive integer"
    error(option .. " must be " .. expected, 0)
  end
  return value
end

---@param value table
---@return { height: integer }
function M.normalize_activity(value)
  if type(value) ~= "table" then
    error("ui.activity must be a table", 0)
  end
  local options = vim.tbl_deep_extend("keep", vim.deepcopy(value), { height = 12 })
  options.height = normalize_height(options.height, "ui.activity.height", false)
  return options
end

---@param value table
---@return { height: "auto"|integer }
function M.normalize_connection_info(value)
  if type(value) ~= "table" then
    error("ui.connection_info must be a table", 0)
  end
  local options = vim.tbl_deep_extend("keep", vim.deepcopy(value), { height = "auto" })
  options.height = normalize_height(options.height, "ui.connection_info.height", true)
  return options
end

return M
