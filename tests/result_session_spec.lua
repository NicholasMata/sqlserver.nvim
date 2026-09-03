local query_result = require("sqlserver.core.query_result")
local result_cell = require("sqlserver.core.result_cell")
local view = require("sqlserver.ui.results.view")

local function result(value, ordinal)
  return query_result.create({
    columns = { "Value" },
    rows = { { result_cell.create({ display_value = value }) } },
    row_count = 1,
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

return {
  test_name = "Result sessions should retain execution history per source buffer",
  run_test_async = function()
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

    assert(view.show({ result("second", 1) }, options(2, opened), source_one))
    local second_execution = vim.api.nvim_get_current_buf()
    assert(vim.api.nvim_buf_is_valid(first_execution_second_result), "Previous execution was discarded")
    vim.api.nvim_set_current_buf(second_execution)
    assert(view.previous_execution(function() end))
    assert(vim.api.nvim_get_current_buf() == first_execution_second_result)
    assert(view.next_execution(function() end))
    assert(vim.api.nvim_get_current_buf() == second_execution)

    assert(view.show({ result("third", 1) }, options(2, opened), source_one))
    assert(not vim.api.nvim_buf_is_valid(first_execution), "Oldest execution exceeded the history limit")
    assert(not vim.api.nvim_buf_is_valid(first_execution_second_result))
    local winbar = view.render_winbar(vim.api.nvim_get_current_buf())
    assert(winbar:find("Run 2/2  Result 1/1", 1, true))
    assert(winbar:find("[No Name]", 1, true))
    assert(vim.api.nvim_get_hl(0, { name = "SqlServerResultPosition", link = true }).link == "Comment")
    assert(view.previous_execution(function() end))
    local removed_execution = vim.api.nvim_get_current_buf()
    assert(view.remove_result())
    assert(not vim.api.nvim_buf_is_valid(removed_execution), "Removing the final result retained its buffer")
    assert(contents(vim.api.nvim_get_current_buf()):find("third", 1, true), "The nearest execution was not selected")
    assert(view.render_winbar():find("Run 1/1", 1, true))

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
    assert(view.render_winbar():find("Run 1/1  Result 1/1", 1, true), "Removing a result removed its nonempty run")
    assert(view.remove_result())
    assert(vim.api.nvim_get_current_buf() == source_three)
    assert(not view.has_results(source_three))

    vim.api.nvim_buf_delete(source_one, { force = true })
    assert(not view.has_results(source_one), "Deleting the source should discard its result history")
    assert(not vim.api.nvim_buf_is_valid(other_source_result))

    vim.api.nvim_buf_delete(source_two, { force = true })
    vim.api.nvim_buf_delete(source_three, { force = true })
    view.clear()
  end,
}
