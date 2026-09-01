local result_view = require("sqlserver.ui.results.view")
local utils = require("sqlserver.utils")
local query_backend = require("sqlserver.adapters.sql_tools_service.query_backend")
local result_sets = require("sqlserver.core.result_sets")

local M = {}
local generation = 0

function M.display(opts, result)
  generation = generation + 1
  local requested_generation = generation
  local descriptors = result_sets.describe(result, opts.results.max_rows)
  if #descriptors == 0 then
    return
  end

  vim.schedule(function()
    utils.try_resume(coroutine.create(function()
      local collected = result_sets.collect_async(result, opts.results.max_rows, query_backend.get_result_rows_async)
      if requested_generation == generation then
        result_view.show(collected, opts)
      end
    end))
  end)
end

function M.clear()
  generation = generation + 1
  result_view.clear()
end

function M.show(opts, collected)
  result_view.show(collected, opts)
end

M.next_result = result_view.next_result
M.previous_result = result_view.previous_result

return M
