local query_selection = require("sqlserver.queries.selection")

local T = MiniTest.new_set()

T["Query selection should describe statement and buffer scopes"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT 1;", "SELECT 2;" })
  vim.api.nvim_win_set_cursor(0, { 2, 4 })

  local statement = query_selection.statement(bufnr)
  assert(statement.kind == "statement")
  assert(statement.position.line == 1 and statement.position.column == 4)

  local buffer = query_selection.buffer(bufnr)
  assert(buffer.kind == "buffer")
  assert(buffer.text == "SELECT 1;\nSELECT 2;")
  assert(buffer.range.startLine == 0 and buffer.range.startColumn == 0)
  assert(buffer.range.endLine == 1 and buffer.range.endColumn == 8)

  vim.fn.setpos("'<", { bufnr, 1, 1, 0 })
  vim.fn.setpos("'>", { bufnr, 1, 6, 0 })
  local visual = query_selection.visual(bufnr, "v")
  assert(visual.kind == "selection")
  assert(visual.text == "SELECT")
  assert(visual.range.startLine == 0 and visual.range.startColumn == 0)
  assert(visual.range.endLine == 0 and visual.range.endColumn == 5)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "😀SELECT", "  FROM dbo.Person;" })
  vim.fn.setpos("'<", { bufnr, 1, 5, 0 })
  vim.fn.setpos("'>", { bufnr, 1, 10, 0 })
  local utf16_visual = query_selection.visual(bufnr, "v")
  assert(utf16_visual.text == "SELECT")
  assert(utf16_visual.range.startColumn == 2 and utf16_visual.range.endColumn == 7)

  vim.fn.setpos("'<", { bufnr, 1, 1, 0 })
  vim.fn.setpos("'>", { bufnr, 2, 1, 0 })
  local line_visual = query_selection.visual(bufnr, "V")
  assert(line_visual.text == "😀SELECT\n  FROM dbo.Person;")
  assert(line_visual.range.startLine == 0 and line_visual.range.startColumn == 0)
  assert(line_visual.range.endLine == 1 and line_visual.range.endColumn == 17)

  local block_visual = query_selection.visual(bufnr, "\22")
  assert(block_visual.range == nil, "Block selections cannot be represented as a contiguous document range")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

return T
