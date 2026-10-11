local M = {}

---@class SqlServerResultCell
---@field display_value string
---@field invariant_value? string
---@field is_null boolean
---@field completeness "complete"|"possibly_truncated"|"unavailable"
---@field limit? integer Service storage threshold when completeness is uncertain

---@param opts { display_value?: string, invariant_value?: string, is_null?: boolean, completeness?: string, limit?: integer }
---@return SqlServerResultCell
function M.create(opts)
  return {
    display_value = opts.display_value or "",
    invariant_value = opts.invariant_value,
    is_null = opts.is_null == true,
    completeness = opts.completeness or "complete",
    limit = opts.limit,
  }
end

return M
