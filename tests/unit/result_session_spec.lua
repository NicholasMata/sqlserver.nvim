local query_result = require("sqlserver.results.result_set")
local result_cell = require("sqlserver.results.cell")
local view = require("sqlserver.results.ui.view")

local function result(value, ordinal, duration_ms, row_count)
  return query_result.create({
    columns = { "Value" },
    rows = { { result_cell.create({ display_value = value }) } },
    row_count = row_count or 1,
    duration_ms = duration_ms,
    locator = { resultSetIndex = ordinal - 1 },
    ordinal = ordinal,
  })
end

local function options(history_limit, opened)
  return {
    results = { max_cell_width = 100, history_limit = history_limit },
    open_results_in = function(bufnr)
      opened.bufnr = bufnr
      vim.api.nvim_set_current_buf(bufnr)
    end,
  }
end

local function contents(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

local T = MiniTest.new_set()

T["Result sessions should retain execution history per source buffer"] = require("tests.helpers").async(function()
  view.clear()
  local source_one = vim.api.nvim_create_buf(false, true)
  local source_two = vim.api.nvim_create_buf(false, true)
  local source_three = vim.api.nvim_create_buf(false, true)
  local opened = {}

  assert(view.show({ result("first-a", 1), result("first-b", 2) }, options(2, opened), source_one))
  local first_execution = opened.bufnr
  vim.api.nvim_set_current_buf(first_execution)
  assert(view.next_result())
  local first_execution_second_result = vim.api.nvim_get_current_buf()
  assert(contents(first_execution_second_result):find("first-b", 1, true))

  assert(view.show({ result("second", 1, nil, 10000) }, options(2, opened), source_one))
  local second_execution = vim.api.nvim_get_current_buf()
  assert(view.render_winbar(second_execution):find("1 of 10,000 rows", 1, true))
  assert(vim.api.nvim_buf_is_valid(first_execution_second_result), "Previous execution was discarded")
  vim.api.nvim_set_current_buf(second_execution)
  assert(view.previous_execution(function() end))
  assert(vim.api.nvim_get_current_buf() == first_execution_second_result)
  assert(view.next_execution(function() end))
  assert(vim.api.nvim_get_current_buf() == second_execution)

  assert(view.show({ result("third", 1, 1250) }, options(2, opened), source_one))
  assert(not vim.api.nvim_buf_is_valid(first_execution), "Oldest execution exceeded the history limit")
  assert(not vim.api.nvim_buf_is_valid(first_execution_second_result))
  local winbar = view.render_winbar(vim.api.nvim_get_current_buf())
  assert(winbar:find("[No Name]  1 row  1.25 s%=", 1, true))
  assert(winbar:find("Execution 2/2  Result 1/1", 1, true))
  assert(winbar:find("[No Name]", 1, true))
  assert(view.previous_execution(function() end))
  local removed_execution = vim.api.nvim_get_current_buf()
  assert(view.remove_result())
  assert(not vim.api.nvim_buf_is_valid(removed_execution), "Removing the final result retained its buffer")
  assert(contents(vim.api.nvim_get_current_buf()):find("third", 1, true), "The nearest execution was not selected")
  assert(view.render_winbar():find("Execution 1/1", 1, true))

  assert(view.show({ result("other-source", 1) }, options(2, opened), source_two))
  local other_source_result = opened.bufnr
  opened.bufnr = nil
  assert(view.show_results(function(bufnr)
    opened.bufnr = bufnr
    vim.api.nvim_set_current_buf(bufnr)
  end, source_one))
  local reopened = vim.api.nvim_get_current_buf()
  assert(contents(reopened):find("third", 1, true), "Source buffer did not reopen its own results")
  assert(reopened ~= other_source_result)

  vim.api.nvim_set_current_buf(other_source_result)
  assert(view.remove_result())
  assert(vim.api.nvim_get_current_buf() == source_two, "Removing the final execution did not restore its source")
  assert(not view.has_results(source_two))

  assert(view.show({ result("remove-a", 1), result("remove-b", 2) }, options(2, opened), source_three))
  local removed_result = vim.api.nvim_get_current_buf()
  assert(view.remove_result())
  assert(not vim.api.nvim_buf_is_valid(removed_result))
  assert(contents(vim.api.nvim_get_current_buf()):find("remove%-b"), "The next result set was not selected")
  assert(
    view.render_winbar():find("Execution 1/1  Result 1/1", 1, true),
    "Removing a result removed its nonempty execution"
  )
  assert(view.remove_result())
  assert(vim.api.nvim_get_current_buf() == source_three)
  assert(not view.has_results(source_three))

  vim.api.nvim_buf_delete(source_one, { force = true })
  assert(not view.has_results(source_one), "Deleting the source should discard its result history")
  assert(not vim.api.nvim_buf_is_valid(other_source_result))

  vim.api.nvim_buf_delete(source_two, { force = true })
  vim.api.nvim_buf_delete(source_three, { force = true })
  view.clear()
end)

T["Result sessions should dispose released query storage"] = require("tests.helpers").async(function()
  view.clear()
  local source = vim.api.nvim_create_buf(false, true)
  local opened = {}
  local disposed = {}
  local function disposal(name)
    return function()
      disposed[name] = (disposed[name] or 0) + 1
      return true
    end
  end

  assert(view.show({ result("first", 1) }, options(1, opened), source, disposal("first")))
  local first_buffer = opened.bufnr
  assert(view.show({ result("second", 1) }, options(1, opened), source, disposal("second")))
  assert(disposed.first == 1, "History eviction should dispose its query")
  assert(not vim.api.nvim_buf_is_valid(first_buffer))

  assert(view.remove_result(opened.bufnr))
  assert(disposed.second == 1, "Removing the final result should dispose its query")
  view.clear(source)
  assert(disposed.second == 1, "Clearing an empty source should not dispose twice")

  assert(view.show({ result("deleted", 1) }, options(1, opened), source, disposal("deleted")))
  vim.api.nvim_buf_delete(opened.bufnr, { force = true })
  vim.wait(100, function()
    return disposed.deleted == 1
  end)
  assert(disposed.deleted == 1, "Deleting a result buffer should dispose its empty execution")

  assert(view.show({ result("source", 1) }, options(1, opened), source, disposal("source")))
  vim.api.nvim_buf_delete(source, { force = true })
  assert(disposed.source == 1, "Deleting the source should dispose its query")
  view.clear()
end)

T["Result sessions should render completely before presentation"] = require("tests.helpers").async(function()
  view.clear()
  local source = vim.api.nvim_create_buf(false, true)
  local opened = {}
  local renderer = require("sqlserver.results.ui.renderer")
  local original_render = renderer.render
  local render_count = 0
  renderer.render = function(result_set, opts)
    render_count = render_count + 1
    if render_count == 2 then
      error("render failed")
    end
    return original_render(result_set, opts)
  end

  local ok, err = pcall(view.show, { result("first", 1), result("second", 2) }, options(2, opened), source)
  renderer.render = original_render

  assert(not ok and tostring(err):find("render failed", 1, true))
  assert(opened.bufnr == nil, "Incomplete results must not be presented")
  assert(not view.has_results(source), "Incomplete results must not enter execution history")
  vim.api.nvim_buf_delete(source, { force = true })
  view.clear()
end)

return T
