local M = {}

---@class SqlServerQuerySummary
---@field batch_count integer
---@field result_set_count integer
---@field row_count integer
---@field has_error boolean

---@param result table
---@return SqlServerQuerySummary
function M.create(result)
  local summary = {
    batch_count = 0,
    result_set_count = 0,
    row_count = 0,
    has_error = false,
  }

  for _, batch in ipairs(result.batchSummaries or {}) do
    summary.batch_count = summary.batch_count + 1
    summary.has_error = summary.has_error or batch.hasError == true
    for _, result_set in ipairs(batch.resultSetSummaries or {}) do
      summary.result_set_count = summary.result_set_count + 1
      summary.row_count = summary.row_count + (result_set.rowCount or 0)
    end
  end

  return summary
end

return M
