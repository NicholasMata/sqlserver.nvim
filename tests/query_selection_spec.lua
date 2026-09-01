local query_selection = require("sqlserver.core.query_selection")

return {
  test_name = "Query selection should describe statement and buffer scopes",
  run_test_async = function()
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

    vim.fn.setpos("'<", { bufnr, 1, 1, 0 })
    vim.fn.setpos("'>", { bufnr, 1, 6, 0 })
    local visual = query_selection.visual(bufnr, "v")
    assert(visual.kind == "selection")
    assert(visual.text == "SELECT")
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end,
}
