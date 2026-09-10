local query_result = require("sqlserver.results.result_set")
local result_column = require("sqlserver.results.column")
local query_summary = require("sqlserver.queries.summary")

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
        local column_metadata = vim.iter(result_set.columnInfo or {}):map(result_column.from_protocol):totable()
        table.insert(descriptors, {
          columns = vim
            .iter(column_metadata)
            :map(function(column)
              return column.name
            end)
            :totable(),
          column_metadata = column_metadata,
          row_count = result_set.rowCount,
          duration_ms = query_summary.parse_duration_ms(batch.executionElapsed),
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
        column_metadata = descriptor.column_metadata,
        rows = fetch_rows(descriptor.locator),
        row_count = descriptor.row_count,
        duration_ms = descriptor.duration_ms,
        locator = descriptor.locator,
        ordinal = descriptor.ordinal,
      })
    end)
    :totable()
end

return M
