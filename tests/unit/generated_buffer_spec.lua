local generated_buffer = require("sqlserver.ui.generated_buffer")

local T = MiniTest.new_set()

T["Generated buffers remain hidden until committed"] = function()
  local source = vim.api.nvim_get_current_buf()
  local transaction = generated_buffer.create({ listed = true, name = vim.fn.tempname() .. ".sql" })
  transaction.set_lines({ "SELECT 1" })

  assert(vim.api.nvim_get_current_buf() == source)
  assert(#vim.fn.win_findbuf(transaction.bufnr) == 0)
  assert(transaction.commit())
  assert(vim.api.nvim_get_current_buf() == transaction.bufnr)
  assert(vim.api.nvim_buf_get_lines(transaction.bufnr, 0, -1, false)[1] == "SELECT 1")

  vim.api.nvim_buf_delete(transaction.bufnr, { force = true })
end

T["Failed generated buffers can be rolled back"] = function()
  local source = vim.api.nvim_get_current_buf()
  local transaction = generated_buffer.create({ listed = true, name = vim.fn.tempname() .. ".sql" })
  transaction.set_lines({ "partial content" })

  assert(transaction.rollback())
  assert(not vim.api.nvim_buf_is_valid(transaction.bufnr))
  assert(vim.api.nvim_get_current_buf() == source)
  assert(not transaction.rollback())
  assert(not transaction.commit())
end

return T
