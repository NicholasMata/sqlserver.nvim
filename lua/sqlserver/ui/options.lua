local M = {}

---@param value boolean|table
---@return { enabled: boolean, layout: "split"|"compact", alignment: "left"|"center"|"right" }
function M.normalize_winbar(value)
  local winbar
  if value == true then
    winbar = { enabled = true, layout = "split", alignment = "right" }
  elseif value == false then
    winbar = { enabled = false, layout = "split", alignment = "right" }
  elseif type(value) == "table" then
    winbar = vim.tbl_deep_extend("keep", value, { enabled = true, layout = "split", alignment = "right" })
  else
    error("ui.winbar must be true, false, or a table", 0)
  end

  if not vim.tbl_contains({ "left", "center", "right" }, winbar.alignment) then
    error("ui.winbar.alignment must be 'left', 'center', or 'right'", 0)
  end
  if not vim.tbl_contains({ "split", "compact" }, winbar.layout) then
    error("ui.winbar.layout must be 'split' or 'compact'", 0)
  end
  return winbar
end

return M
