local query_result = require("sqlserver.core.query_result")
local result_view = require("sqlserver.ui.results.view")
local utils = require("sqlserver.utils")
local query_backend = require("sqlserver.adapters.sql_tools_service.query_backend")

local M = {}
local generation = 0

local function describe_result_sets(result, opts)
  local descriptors = {}
  local ordinal = 0
  for batch_index, batch in ipairs(result.batchSummaries or {}) do
    for result_set_index, result_set in ipairs(batch.resultSetSummaries or {}) do
      ordinal = ordinal + 1
      local failed_without_rows = batch.hasError and result_set.rowCount == 0
      if not failed_without_rows then
        local columns = vim
          .iter(result_set.columnInfo or {})
          :map(function(column)
            return column.columnName
          end)
          :totable()
        table.insert(descriptors, {
          columns = columns,
          row_count = result_set.rowCount,
          ordinal = ordinal,
          locator = {
            ownerUri = result.ownerUri,
            batchIndex = batch_index - 1,
            resultSetIndex = result_set_index - 1,
            rowsStartIndex = 0,
            rowsCount = math.min(result_set.rowCount, opts.results.max_rows),
          },
        })
      end
    end
  end
  return descriptors
end

function M.display(opts, result)
  generation = generation + 1
  local requested_generation = generation
  local descriptors = describe_result_sets(result, opts)
  if #descriptors == 0 then
    return
  end

  vim.schedule(function()
    utils.try_resume(coroutine.create(function()
      local result_sets = {}
      for _, descriptor in ipairs(descriptors) do
        table.insert(
          result_sets,
          query_result.create({
            columns = descriptor.columns,
            rows = query_backend.get_result_rows_async(descriptor.locator),
            row_count = descriptor.row_count,
            locator = descriptor.locator,
            ordinal = descriptor.ordinal,
          })
        )
      end
      if requested_generation == generation then
        result_view.show(result_sets, opts)
      end
    end))
  end)
end

function M.clear()
  generation = generation + 1
  result_view.clear()
end

M.next_result = result_view.next_result
M.previous_result = result_view.previous_result

return M
