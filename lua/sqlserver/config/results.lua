local M = {}

M.default_column_icons = {
  text = "󰀬",
  number = "󰎠",
  boolean = "󰔡",
  temporal = "󰃭",
  json = "󰘦",
  uuid = "󰯮",
  binary = "󰈔",
  unknown = "󰠵",
  nullable = "ˀ",
}

---@param value boolean|table
---@return { enabled: boolean, wrap: boolean }
function M.normalize_cell_navigation(value)
  local options
  if value == true then
    options = { enabled = true, wrap = true }
  elseif value == false then
    options = { enabled = false, wrap = true }
  elseif type(value) == "table" then
    for name in pairs(value) do
      if name ~= "wrap" then
        error("Unknown results.cell_navigation option: " .. tostring(name), 0)
      end
    end
    options = vim.tbl_extend("keep", vim.deepcopy(value), { wrap = true })
    options.enabled = true
  else
    error("results.cell_navigation must be true, false, or a table", 0)
  end
  if type(options.wrap) ~= "boolean" then
    error("results.cell_navigation.wrap must be true or false", 0)
  end
  return options
end

---@param value boolean|table
---@return { enabled: boolean, icons: table<string, string> }
function M.normalize_column_icons(value)
  if value == false then
    return { enabled = false, icons = vim.deepcopy(M.default_column_icons) }
  end
  if value ~= true and type(value) ~= "table" then
    error("results.column_icons must be true, false, or a table", 0)
  end
  local icons = vim.deepcopy(M.default_column_icons)
  for name, icon in pairs(value == true and {} or value) do
    if icons[name] == nil then
      error("Unknown results.column_icons option: " .. tostring(name), 0)
    end
    if type(icon) ~= "string" then
      error("results.column_icons." .. name .. " must be a string", 0)
    end
    icons[name] = icon
  end
  return { enabled = true, icons = icons }
end

return M
