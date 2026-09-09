local export_view = require("sqlserver.results.ui.export")

local T = MiniTest.new_set()

T["Text result exports should open as modified normal buffers"] = function()
  local path = vim.fn.tempname() .. ".csv"
  vim.fn.writefile({ "ID,Name", '1,"Ada"' }, path)

  local bufnr = export_view.open(path, "csv", { execution_id = 7, result_ordinal = 2 })

  assert(vim.api.nvim_get_current_buf() == bufnr)
  assert(vim.api.nvim_buf_get_name(bufnr):match("results%-7%-2%.csv$"))
  assert(vim.bo[bufnr].buftype == "")
  assert(vim.bo[bufnr].filetype == "csv")
  assert(vim.bo[bufnr].modifiable and vim.bo[bufnr].modified)
  assert(vim.b[bufnr].sqlserver_export)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "ID,Name", '1,"Ada"', "" }))

  vim.api.nvim_buf_delete(bufnr, { force = true })
  vim.fn.delete(path)
end

return T
