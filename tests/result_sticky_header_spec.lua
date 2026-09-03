local sticky_header = require("sqlserver.ui.results.sticky_header")

return {
  test_name = "Result headers should remain visible without replacing the real row",
  run_test_async = function()
    local original_buffer = vim.api.nvim_get_current_buf()
    local result_buffer = vim.api.nvim_create_buf(false, true)
    local lines = { "ID │ Name │ Age │ " .. string.rep("Additional column │ ", 8) }
    for index = 1, 40 do
      table.insert(lines, ("%02d │ Person %02d │ %d"):format(index, index, 20 + index))
    end
    vim.api.nvim_buf_set_lines(result_buffer, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(result_buffer)
    vim.api.nvim_set_option_value("wrap", false, { win = 0 })

    sticky_header.setup({ enabled = true })
    sticky_header.attach(result_buffer, lines[1], {})
    local parent = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(parent, { 20, 0 })
    vim.cmd("normal! zt")
    sticky_header.refresh()

    local float = sticky_header.get_window(parent)
    assert(float, "Scrolling the real header away did not create a sticky header")
    local config = vim.api.nvim_win_get_config(float)
    assert(config.focusable == false and config.mouse == false, "The sticky header should not intercept input")
    assert(vim.api.nvim_get_current_win() == parent, "The sticky header took focus from the result window")
    assert(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false)[1] == lines[1])
    vim.api.nvim_win_call(parent, function()
      vim.cmd("normal! 10zl")
    end)
    sticky_header.refresh()
    local parent_leftcol = vim.api.nvim_win_call(parent, function()
      return vim.fn.winsaveview().leftcol
    end)
    local float_leftcol = vim.api.nvim_win_call(float, function()
      return vim.fn.winsaveview().leftcol
    end)
    assert(
      parent_leftcol > 0 and float_leftcol == parent_leftcol,
      "The sticky header did not follow horizontal scrolling"
    )

    vim.api.nvim_win_set_cursor(parent, { 1, 0 })
    vim.cmd("normal! yy")
    assert(vim.fn.getreg('"'):find(lines[1], 1, true), "Normal-mode commands no longer operate on the real header")
    vim.cmd("normal! 0v$y")
    local visual_yank = vim.fn.getreg('"')
    assert(
      visual_yank:find("ID", 1, true) and visual_yank:find("Age", 1, true),
      "Visual-mode commands no longer operate on the real header"
    )
    sticky_header.refresh()
    assert(not sticky_header.get_window(parent), "The sticky copy remained while the real header was visible")

    local other_result = vim.api.nvim_create_buf(false, true)
    local other_lines = { "Code │ Description" }
    for index = 1, 40 do
      table.insert(other_lines, ("%02d │ Other result"):format(index))
    end
    vim.api.nvim_buf_set_lines(other_result, 0, -1, false, other_lines)
    sticky_header.attach(other_result, other_lines[1], {})
    vim.api.nvim_win_set_buf(parent, other_result)
    vim.api.nvim_win_set_cursor(parent, { 20, 0 })
    vim.cmd("normal! zt")
    sticky_header.refresh()
    float = sticky_header.get_window(parent)
    assert(float, "Switching result buffers did not restore the sticky header")
    assert(
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false)[1] == other_lines[1],
      "Switching result buffers retained the previous result header"
    )

    vim.api.nvim_set_current_buf(original_buffer)
    vim.api.nvim_buf_delete(result_buffer, { force = true })
    vim.api.nvim_buf_delete(other_result, { force = true })
    sticky_header.setup({ enabled = true })
  end,
}
