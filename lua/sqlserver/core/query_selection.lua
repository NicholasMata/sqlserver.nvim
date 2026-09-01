local M = {}

---@class SqlServerQueryRequest
---@field kind "statement"|"selection"|"buffer"
---@field position? { line: integer, column: integer }
---@field text? string

---@param bufnr? integer
---@return SqlServerQueryRequest
function M.statement(bufnr)
  bufnr = bufnr or 0
  local winid = bufnr == 0 and 0 or vim.fn.bufwinid(bufnr)
  assert(winid ~= -1, "Query buffer must be visible to select its current statement")
  local cursor = vim.api.nvim_win_get_cursor(winid)
  return {
    kind = "statement",
    position = { line = cursor[1] - 1, column = cursor[2] },
  }
end

---@param bufnr? integer
---@return SqlServerQueryRequest
function M.buffer(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return { kind = "buffer", text = table.concat(lines, "\n") }
end

---@param bufnr? integer
---@param visual_mode? string
---@return SqlServerQueryRequest
function M.visual(bufnr, visual_mode)
  bufnr = bufnr or 0
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getregion(start_pos, end_pos, { type = visual_mode or vim.fn.visualmode() })
  return { kind = "selection", text = table.concat(lines, "\n") }
end

---@param bufnr? integer
---@return SqlServerQueryRequest
function M.current(bufnr)
  local mode = vim.api.nvim_get_mode().mode
  if not (mode == "v" or mode == "V" or mode == "\22") then
    return M.statement(bufnr)
  end

  local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(escape, "x", false)
  return M.visual(bufnr, vim.fn.visualmode())
end

return M
