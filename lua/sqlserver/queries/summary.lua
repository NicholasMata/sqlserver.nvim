local M = {}

---@class SqlServerQuerySummary
---@field batch_count integer
---@field result_set_count integer
---@field row_count integer
---@field has_error boolean
---@field server_duration_ms? number

---@param value? string
---@return number?
local function parse_duration_ms(value)
  if type(value) ~= "string" then
    return nil
  end

  local days, hours, minutes, seconds, fraction = value:match("^(%d+)%.(%d+):(%d+):(%d+)%.?(%d*)$")
  if not days then
    hours, minutes, seconds, fraction = value:match("^(%d+):(%d+):(%d+)%.?(%d*)$")
    days = "0"
  end
  if not hours then
    return nil
  end

  local milliseconds = (((tonumber(days) * 24 + tonumber(hours)) * 60 + tonumber(minutes)) * 60 + tonumber(seconds))
    * 1000
  if fraction ~= "" then
    milliseconds = milliseconds + tonumber("0." .. fraction) * 1000
  end
  return milliseconds
end

---@param result table
---@return SqlServerQuerySummary
function M.create(result)
  local summary = {
    batch_count = 0,
    result_set_count = 0,
    row_count = 0,
    has_error = false,
    server_duration_ms = nil,
  }

  for _, batch in ipairs(result.batchSummaries or {}) do
    summary.batch_count = summary.batch_count + 1
    summary.has_error = summary.has_error or batch.hasError == true
    local batch_duration_ms = parse_duration_ms(batch.executionElapsed)
    if batch_duration_ms then
      summary.server_duration_ms = (summary.server_duration_ms or 0) + batch_duration_ms
    end
    for _, result_set in ipairs(batch.resultSetSummaries or {}) do
      summary.result_set_count = summary.result_set_count + 1
      summary.row_count = summary.row_count + (result_set.rowCount or 0)
    end
  end

  return summary
end

return M
