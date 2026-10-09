local view = require("sqlserver.results.ui.view")
local source_ui = require("sqlserver.results.ui.source")
local winbar = require("sqlserver.results.ui.winbar")
local result_set = require("sqlserver.results.result_set")
local cell = require("sqlserver.results.cell")
local T = MiniTest.new_set()

local function show_result(source)
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
    open_results_in = function(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
    end,
  }, source))
  return vim.api.nvim_get_current_buf()
end

T["Source label only marks hidden queries and escapes winbar filenames"] = function()
  assert(winbar.source_label("query%file.sql", true) == "query%%file.sql")
  assert(winbar.source_label("query%file.sql", false) == "query%%file.sql 󰈉")
  assert(winbar.source_label("[No Name]", false) == "[No Name] 󰈉")
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

T["ShowQuery reopens a source in this tab and respects split preferences"] = function()
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
    assert((vim.api.nvim_win_get_position(source_window)[1] > vim.api.nvim_win_get_position(result_window)[1]) == below)
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

return T
