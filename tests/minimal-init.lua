local root = vim.fn.getcwd()

vim.opt.runtimepath:prepend(vim.fs.joinpath(root, ".tests", "deps", "mini.nvim"))
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.completeopt = { "menu", "menuone", "noselect", "noinsert" }
vim.lsp.log.set_level("debug")

require("mini.test").setup({
  execute = {
    reporter = require("mini.test").gen_reporter.stdout(),
    stop_on_error = true,
  },
})
