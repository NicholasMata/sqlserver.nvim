local M = {}

local next_export_id = 1

local function buffer_name(format, info)
  local execution = info and info.execution_id
  local result = info and info.result_ordinal
  local stem = execution and result and ("results-%d-%d"):format(execution, result)
    or ("results-%d"):format(next_export_id)
  local name = stem .. "." .. format
  local suffix = 2
  while vim.fn.bufnr(name) ~= -1 or vim.uv.fs_stat(name) do
    name = ("%s-%d.%s"):format(stem, suffix, format)
    suffix = suffix + 1
  end
  next_export_id = next_export_id + 1
  return name
end

---@param path string
---@param format "csv"|"json"|"xml"
---@param info? table
---@return integer
function M.open(path, format, info)
  local lines = vim.fn.readfile(path, "b")
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, buffer_name(format, info))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", format, { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
  vim.api.nvim_set_option_value("modified", true, { buf = bufnr })
  vim.b[bufnr].sqlserver_export = true
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

return M
