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

function M.show(bufnr, previous_window)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local winid = M.window(bufnr)
  if
    not winid
    and previous_window
    and vim.api.nvim_win_is_valid(previous_window)
    and vim.api.nvim_win_get_tabpage(previous_window) == vim.api.nvim_get_current_tabpage()
    and previous_window ~= vim.api.nvim_get_current_win()
    and vim.api.nvim_win_get_config(previous_window).relative == ""
  then
    winid = previous_window
    vim.api.nvim_win_set_buf(winid, bufnr)
  end
  if winid then
    vim.api.nvim_set_current_win(winid)
  else
    -- Results follow splitbelow when opened from a query. Restore the source
    -- on the opposite side without changing the user's global preference.
    vim.cmd(vim.o.splitbelow and "aboveleft split" or "belowright split")
    vim.api.nvim_set_current_buf(bufnr)
    winid = vim.api.nvim_get_current_win()
  end
  return true, winid
end

return M
