local M = {}
local generated_buffer = require("sqlserver.ui.generated_buffer")

local next_export_id = 1
local function pack(...)
  return { n = select("#", ...), ... }
end

---@param format string
---@param action fun(path: string): any
---@return any
function M.with_temporary_file(format, action)
  local path = vim.fn.tempname() .. "." .. format
  local result = pack(pcall(action, path))
  vim.fn.delete(path)
  if not result[1] then
    error(result[2], 0)
  end
  return unpack(result, 2, result.n)
end

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
  local transaction = generated_buffer.create({ listed = true, name = buffer_name(format, info) })
  local bufnr = transaction.bufnr
  local prepared, prepare_error = pcall(function()
    transaction.set_lines(lines)
    vim.api.nvim_set_option_value("filetype", format, { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
    vim.api.nvim_set_option_value("modified", true, { buf = bufnr })
    vim.b[bufnr].sqlserver_export = true
  end)
  if not prepared then
    transaction.rollback()
    error(prepare_error, 0)
  end
  transaction.commit()
  return transaction.bufnr
end

return M
