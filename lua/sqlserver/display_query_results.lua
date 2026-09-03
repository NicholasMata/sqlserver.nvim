local result_view = require("sqlserver.ui.results.view")
local utils = require("sqlserver.utils")
local query_backend = require("sqlserver.adapters.sql_tools_service.query_backend")
local result_sets = require("sqlserver.core.result_sets")

local M = {}
local generations = {}

M.setup = result_view.setup

function M.display(opts, result, source_bufnr)
  source_bufnr = source_bufnr or vim.api.nvim_get_current_buf()
  generations[source_bufnr] = (generations[source_bufnr] or 0) + 1
  local requested_generation = generations[source_bufnr]
  local descriptors = result_sets.describe(result, opts.results.max_rows)
  if #descriptors == 0 then
    return
  end

  vim.schedule(function()
    utils.try_resume(coroutine.create(function()
      local collected = result_sets.collect_async(result, opts.results.max_rows, query_backend.get_result_rows_async)
      if requested_generation == generations[source_bufnr] then
        result_view.show(collected, opts, source_bufnr)
      end
    end))
  end)
end

function M.clear(source_bufnr)
  if source_bufnr then
    generations[source_bufnr] = (generations[source_bufnr] or 0) + 1
  else
    generations = {}
  end
  result_view.clear(source_bufnr)
end

function M.show(opts, collected, source_bufnr)
  result_view.show(collected, opts, source_bufnr)
end

M.next_result = result_view.next_result
M.previous_result = result_view.previous_result
M.next_execution = result_view.next_execution
M.previous_execution = result_view.previous_execution
M.can_remove_result = result_view.can_remove_result
M.remove_result = result_view.remove_result
M.has_results = result_view.has_results
M.show_results = result_view.show_results
M.is_result_buffer = result_view.is_result_buffer

return M
