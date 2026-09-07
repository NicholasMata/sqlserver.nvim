local M = {}

---@class SqlServerQueryRequest
---@field kind "statement"|"selection"|"buffer"
---@field position? { line: integer, column: integer }
---@field range? { startLine: integer, startColumn: integer, endLine: integer, endColumn: integer }
---@field text? string

---@param text string
---@return integer
local function utf16_length(text)
  return vim.str_utfindex(text, "utf-16")
end

local function last_utf16_column(text)
  return math.max(utf16_length(text) - 1, 0)
end

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
  return {
    kind = "buffer",
    text = table.concat(lines, "\n"),
    range = {
      startLine = 0,
      startColumn = 0,
      endLine = #lines - 1,
      endColumn = last_utf16_column(lines[#lines]),
    },
  }
end

---@param bufnr? integer
---@param visual_mode? string
---@return SqlServerQueryRequest
function M.visual(bufnr, visual_mode)
  bufnr = bufnr or 0
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  visual_mode = visual_mode or vim.fn.visualmode()
  local lines = vim.fn.getregion(start_pos, end_pos, { type = visual_mode })
  local request = { kind = "selection", text = table.concat(lines, "\n") }

  -- SQL Tools Service selections are contiguous document ranges. Preserve the
  -- existing execute-string behavior for Neovim's non-contiguous block mode.
  if visual_mode ~= "\22" then
    local start_column = visual_mode == "V" and 0
      or utf16_length(
        vim.api.nvim_buf_get_lines(bufnr, start_pos[2] - 1, start_pos[2], false)[1]:sub(1, start_pos[3] - 1)
      )
    request.range = {
      startLine = start_pos[2] - 1,
      startColumn = start_column,
      endLine = end_pos[2] - 1,
      endColumn = start_pos[2] == end_pos[2] and start_column + last_utf16_column(lines[1])
        or last_utf16_column(lines[#lines]),
    }
  end

  return request
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
