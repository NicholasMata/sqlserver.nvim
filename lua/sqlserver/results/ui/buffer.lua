local M = {}

local function configure_window(winid)
  vim.api.nvim_set_option_value("wrap", false, { win = winid })
  vim.api.nvim_set_option_value("cursorline", true, { win = winid })
  vim.api.nvim_set_option_value("list", false, { win = winid })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = winid })
end

function M.setup(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    configure_window(winid)
  end

  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = bufnr,
    callback = function(args)
      for _, winid in ipairs(vim.fn.win_findbuf(args.buf)) do
        configure_window(winid)
      end
    end,
  })

  require("sqlserver.results.ui.keymaps").attach(bufnr)
  vim.b[bufnr].undo_ftplugin = table.concat({
    "setlocal wrap< cursorline< list< number< relativenumber< signcolumn<",
    "silent! nunmap <buffer> ]r",
    "silent! nunmap <buffer> [r",
    "silent! nunmap <buffer> ]c",
    "silent! nunmap <buffer> [c",
    "silent! nunmap <buffer> K",
    "silent! nunmap <buffer> yic",
    "silent! nunmap <buffer> h",
    "silent! nunmap <buffer> j",
    "silent! nunmap <buffer> k",
    "silent! nunmap <buffer> l",
    "silent! xunmap <buffer> ]c",
    "silent! xunmap <buffer> [c",
    "silent! xunmap <buffer> ic",
  }, " | ")
end

return M
