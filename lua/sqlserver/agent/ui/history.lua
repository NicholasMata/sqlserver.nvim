local status = require("sqlserver.agent.ui.status")

local M = {}

function M.open(item, on_close)
  local lines = vim.split(item.detail, "\n", { plain = true })
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "sqlserver-job-history"
  local namespace = vim.api.nvim_create_namespace("sqlserver-agent-history")
  vim.api.nvim_set_hl(0, "SqlServerJobHistoryLabel", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "SqlServerJobHistoryHeading", { default = true, link = "Function" })
  for _, mark in ipairs(item.marks or {}) do
    vim.api.nvim_buf_set_extmark(bufnr, namespace, mark.line, 0, {
      end_col = mark.heading and (mark.outcome_start or #lines[mark.line + 1]) or mark.label_end,
      hl_group = mark.heading and "SqlServerJobHistoryHeading" or "SqlServerJobHistoryLabel",
    })
    local group = mark.outcome and status.outcome(mark.outcome)
    if group then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, mark.line, mark.outcome_start, {
        end_col = mark.outcome_end,
        hl_group = group,
      })
    end
  end

  local width = math.min(100, math.max(20, vim.o.columns - 8))
  local height = math.min(math.max(#lines, 8), math.max(4, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = "Job run · " .. item.run_at,
    title_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.cmd("stopinsert")

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = bufnr, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, silent = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if on_close then
        vim.schedule(on_close)
      end
    end,
  })
  return win
end

return M
