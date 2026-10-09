local M = {}

-- Visibility is local to the active tab: a query in another tab is still
-- separated from the results the user is inspecting here.
function M.window(bufnr)
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
end

function M.visible(bufnr)
  return M.window(bufnr) ~= nil
end

function M.show(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local winid = M.window(bufnr)
  if winid then
    vim.api.nvim_set_current_win(winid)
  else
    vim.cmd("split")
    vim.api.nvim_set_current_buf(bufnr)
  end
  return true
end

return M
