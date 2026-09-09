local M = {}

---@class SqlServerResultCell
---@field display_value string
---@field invariant_value? string
---@field is_null boolean

---@param opts { display_value?: string, invariant_value?: string, is_null?: boolean }
---@return SqlServerResultCell
function M.create(opts)
  return {
    display_value = opts.display_value or "",
    invariant_value = opts.invariant_value,
    is_null = opts.is_null == true,
  }
end

return M
