local M = {}

local defaults = {
  lsp_attach = 10000,
  connection = 10000,
  object_explorer = 10000,
  query = false,
}

---@param opts? table
---@return table
function M.normalize(opts)
  for name in pairs(opts or {}) do
    if defaults[name] == nil then
      error("Unknown timeout option: " .. name, 0)
    end
  end
  opts = vim.tbl_extend("force", defaults, opts or {})
  for name, value in pairs(opts) do
    if value ~= false and (type(value) ~= "number" or value <= 0) then
      error("timeouts." .. name .. " must be a positive number of milliseconds or false", 0)
    end
  end
  return opts
end

return M
