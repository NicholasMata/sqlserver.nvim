local root = vim.fn.getcwd()

vim.opt.runtimepath:prepend(vim.fs.joinpath(root, ".tests", "deps", "mini.nvim"))
vim.opt.runtimepath:prepend(root)

if vim.env.SQLSERVER_COVERAGE == "1" then
  jit.off()
  local luacov_src = vim.fs.joinpath(root, ".tests", "deps", "luacov", "src")
  package.path = table.concat({
    vim.fs.joinpath(luacov_src, "?.lua"),
    vim.fs.joinpath(luacov_src, "?", "init.lua"),
    package.path,
  }, ";")
  local luacov = require("luacov")
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      luacov.save_stats()
    end,
  })
end

vim.opt.swapfile = false
vim.opt.completeopt = { "menu", "menuone", "noselect", "noinsert" }
vim.lsp.log.set_level("debug")

require("mini.test").setup({
  execute = {
    reporter = require("mini.test").gen_reporter.stdout(),
    stop_on_error = true,
  },
})
