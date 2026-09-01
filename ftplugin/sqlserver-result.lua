local function configure_window(winid)
  vim.api.nvim_set_option_value("wrap", false, { win = winid })
  vim.api.nvim_set_option_value("cursorline", true, { win = winid })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = winid })
end

for _, winid in ipairs(vim.fn.win_findbuf(vim.api.nvim_get_current_buf())) do
  configure_window(winid)
end

vim.api.nvim_create_autocmd("BufWinEnter", {
  buffer = 0,
  callback = function(args)
    for _, winid in ipairs(vim.fn.win_findbuf(args.buf)) do
      configure_window(winid)
    end
  end,
})

vim.keymap.set("n", "]r", function()
  require("sqlserver.ui.results.view").next_result()
end, { buffer = true, desc = "Next SQL result" })

vim.keymap.set("n", "[r", function()
  require("sqlserver.ui.results.view").previous_result()
end, { buffer = true, desc = "Previous SQL result" })

vim.b.undo_ftplugin = table.concat({
  "setlocal wrap< cursorline< number< relativenumber< signcolumn<",
  "silent! nunmap <buffer> ]r",
  "silent! nunmap <buffer> [r",
}, " | ")
