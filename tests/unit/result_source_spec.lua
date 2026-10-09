local view = require("sqlserver.results.ui.view")
local source_ui = require("sqlserver.results.ui.source")
local winbar = require("sqlserver.results.ui.winbar")
local result_set = require("sqlserver.results.result_set")
local cell = require("sqlserver.results.cell")
local T = MiniTest.new_set()

local function show_result(source, open_results_in)
  view.clear()
  assert(view.show({
    result_set.create({
      columns = { "Value" },
      rows = { { cell.create({ display_value = "retained" }) } },
      row_count = 1,
      ordinal = 1,
      locator = { resultSetIndex = 0 },
    }),
  }, {
    results = { max_cell_width = 100, history_limit = 2 },
    open_results_in = open_results_in or function(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
    end,
  }, source))
  return vim.api.nvim_get_current_buf()
end

T["Source label switches equal-width eye icons and escapes winbar filenames"] = function()
  assert(winbar.source_label("query%file.sql", true) == "query%%file.sql 󰈈")
  assert(winbar.source_label("query%file.sql", false) == "query%%file.sql 󰈉")
  assert(winbar.source_label("[No Name]", false) == "[No Name] 󰈉")
  assert(
    vim.fn.strdisplaywidth(winbar.source_label("query.sql", true))
      == vim.fn.strdisplaywidth(winbar.source_label("query.sql", false))
  )
end

T["Result indicator follows source window visibility without changing history"] = function()
  local source = vim.api.nvim_create_buf(false, true)
  local result = show_result(source)
  local result_window = vim.api.nvim_get_current_win()
  assert(view.render_winbar(result):find("󰈉", 1, true))
  vim.cmd("split")
  local source_window = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_buf(source)
  assert(not view.render_winbar(result):find("󰈉", 1, true))
  assert(view.render_winbar(result):find("󰈈", 1, true))
  vim.api.nvim_set_current_win(result_window)
  local windows = #vim.api.nvim_tabpage_list_wins(0)
  assert(view.show_query() and vim.api.nvim_get_current_win() == source_window)
  assert(#vim.api.nvim_tabpage_list_wins(0) == windows, "Visible source created another window")
  vim.api.nvim_win_close(source_window, true)
  assert(view.render_winbar(result):find("󰈉", 1, true))
  assert(view.render_winbar(result):find("Execution 1/1", 1, true))
  assert(vim.api.nvim_buf_is_valid(result))
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end

T["ShowQuery restores a hidden source opposite the preferred result split"] = function()
  local original_splitbelow = vim.o.splitbelow
  for _, below in ipairs({ false, true }) do
    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "SELECT N'unchanged';" })
    local result = show_result(source)
    local result_window = vim.api.nvim_get_current_win()
    local result_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    local other_window = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_set_current_win(result_window)
    assert(view.render_winbar(result):find("󰈉", 1, true), "Query in another tab appeared visible here")
    vim.o.splitbelow = below
    assert(view.show_query())
    assert(vim.api.nvim_get_current_tabpage() == result_tab)
    local source_window = vim.api.nvim_get_current_win()
    assert(vim.api.nvim_win_get_buf(source_window) == source)
    assert((vim.api.nvim_win_get_position(source_window)[1] > vim.api.nvim_win_get_position(result_window)[1]) ~= below)
    assert(vim.o.splitbelow == below, "Restoring the query changed the global split preference")
    assert(not view.render_winbar(result):find("󰈉", 1, true))
    assert(vim.api.nvim_buf_get_lines(source, 0, -1, false)[1] == "SELECT N'unchanged';")
    assert(vim.api.nvim_buf_is_valid(result) and view.has_results(source))
    vim.api.nvim_win_close(other_window, true)
    vim.api.nvim_win_close(source_window, true)
    view.clear()
    vim.api.nvim_buf_delete(source, { force = true })
  end
  vim.o.splitbelow = original_splitbelow
end

T["ShowQuery ignores unrelated buffers and invalid sources"] = function()
  view.clear()
  assert(not view.show_query())
  local source = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_delete(source, { force = true })
  assert(not source_ui.show(source))
end

T["ShowQuery restores a switched query in its original window"] = function()
  local source = vim.api.nvim_create_buf(false, true)
  local replacement = vim.api.nvim_create_buf(true, false)
  vim.bo[replacement].bufhidden = "hide"
  vim.api.nvim_buf_set_lines(replacement, 0, -1, false, { "unsaved replacement" })
  vim.api.nvim_set_current_buf(source)
  local original_window = vim.api.nvim_get_current_win()
  local result = show_result(source, function(bufnr)
    vim.cmd("split")
    vim.api.nvim_set_current_buf(bufnr)
  end)
  local result_window = vim.api.nvim_get_current_win()
  local original_position = vim.api.nvim_win_get_position(original_window)
  vim.api.nvim_win_set_buf(original_window, replacement)
  local windows = #vim.api.nvim_tabpage_list_wins(0)
  assert(view.render_winbar(result):find("󰈉", 1, true))
  assert(view.show_query())
  assert(vim.api.nvim_get_current_win() == original_window)
  assert(vim.api.nvim_get_current_buf() == source)
  assert(#vim.api.nvim_tabpage_list_wins(0) == windows, "Restoration created an extra split")
  assert(vim.deep_equal(vim.api.nvim_win_get_position(original_window), original_position))
  assert(vim.api.nvim_buf_is_valid(replacement) and vim.bo[replacement].modified)
  assert(vim.api.nvim_buf_get_lines(replacement, 0, -1, false)[1] == "unsaved replacement")
  assert(vim.api.nvim_win_get_buf(result_window) == result and view.has_results(source))
  assert(not view.render_winbar(result):find("󰈉", 1, true))
  vim.api.nvim_set_current_win(result_window)
  assert(view.show_query() and vim.api.nvim_get_current_win() == original_window)
  assert(#vim.api.nvim_tabpage_list_wins(0) == windows)
  vim.api.nvim_win_close(original_window, true)
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
  vim.api.nvim_buf_delete(replacement, { force = true })
end

T["ShowQuery remembers the replacement window after the original closes"] = function()
  local source = vim.api.nvim_create_buf(false, true)
  local replacement = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(source)
  local original_window = vim.api.nvim_get_current_win()
  local result = show_result(source, function(bufnr)
    vim.cmd("split")
    vim.api.nvim_set_current_buf(bufnr)
  end)
  local result_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_close(original_window, true)
  assert(#vim.api.nvim_tabpage_list_wins(0) == 1)
  assert(view.show_query())
  local restored_window = vim.api.nvim_get_current_win()
  assert(restored_window ~= original_window and vim.api.nvim_get_current_buf() == source)
  assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
  vim.api.nvim_win_set_buf(restored_window, replacement)
  vim.api.nvim_set_current_win(result_window)
  assert(view.show_query() and vim.api.nvim_get_current_win() == restored_window)
  assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
  assert(vim.api.nvim_win_get_buf(result_window) == result)
  vim.api.nvim_win_close(restored_window, true)
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
  vim.api.nvim_buf_delete(replacement, { force = true })
end

T["ShowQuery preserves unrelated query windows when restoring its source"] = function()
  local source = vim.api.nvim_create_buf(false, true)
  local unrelated = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(unrelated, 0, -1, false, { "SELECT N'other query';" })
  vim.bo[unrelated].filetype = "sql"
  local result = show_result(source)
  local result_window = vim.api.nvim_get_current_win()
  vim.cmd("split")
  local unrelated_window = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_buf(unrelated)
  vim.api.nvim_set_current_win(result_window)
  local windows = #vim.api.nvim_tabpage_list_wins(0)
  assert(view.show_query())
  local source_window = vim.api.nvim_get_current_win()
  assert(vim.api.nvim_get_current_buf() == source)
  assert(#vim.api.nvim_tabpage_list_wins(0) == windows + 1)
  assert(vim.api.nvim_win_get_buf(unrelated_window) == unrelated)
  assert(vim.api.nvim_win_get_buf(result_window) == result)
  assert(vim.api.nvim_buf_get_lines(unrelated, 0, -1, false)[1] == "SELECT N'other query';")
  vim.api.nvim_set_current_win(result_window)
  assert(view.show_query() and vim.api.nvim_get_current_win() == source_window)
  assert(#vim.api.nvim_tabpage_list_wins(0) == windows + 1, "Repeated restoration created another query window")
  vim.api.nvim_win_close(source_window, true)
  vim.api.nvim_win_close(unrelated_window, true)
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
  vim.api.nvim_buf_delete(unrelated, { force = true })
end

return T
