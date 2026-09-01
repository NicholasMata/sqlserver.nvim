local query_result = require("sqlserver.core.query_result")

local M = {}

---@param result table
---@param max_rows integer
---@return table[]
function M.describe(result, max_rows)
  local descriptors = {}
  local ordinal = 0
  for batch_index, batch in ipairs(result.batchSummaries or {}) do
    for result_set_index, result_set in ipairs(batch.resultSetSummaries or {}) do
      ordinal = ordinal + 1
      if not (batch.hasError and result_set.rowCount == 0) then
        table.insert(descriptors, {
          columns = vim
            .iter(result_set.columnInfo or {})
            :map(function(column)
              return column.columnName
            end)
            :totable(),
          row_count = result_set.rowCount,
          ordinal = ordinal,
          locator = {
            ownerUri = result.ownerUri,
            batchIndex = batch_index - 1,
            resultSetIndex = result_set_index - 1,
            rowsStartIndex = 0,
            rowsCount = math.min(result_set.rowCount, max_rows),
          },
        })
      end
    end
  end
  return descriptors
end

---@param result table
---@param max_rows integer
---@param fetch_rows fun(locator: table): SqlServerResultCell[][]
---@return SqlServerResultSet[]
function M.collect_async(result, max_rows, fetch_rows)
  return vim
    .iter(M.describe(result, max_rows))
    :map(function(descriptor)
      return query_result.create({
        columns = descriptor.columns,
        rows = fetch_rows(descriptor.locator),
        row_count = descriptor.row_count,
        locator = descriptor.locator,
        ordinal = descriptor.ordinal,
      })
    end)
    :totable()
end

return M
