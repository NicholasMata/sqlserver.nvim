local M = {}

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

return M
