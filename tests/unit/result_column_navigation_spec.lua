local query_result = require("sqlserver.results.result_set")
local result_cell = require("sqlserver.results.cell")
local view = require("sqlserver.results.ui.view")
local column_info = require("sqlserver.results.ui.column_info")

local T = MiniTest.new_set()

T["Column information uses SQL type declarations"] = function()
  assert(column_info.format_type({ type_name = "int", size = 4 }) == "int")
  assert(column_info.format_type({ type_name = "varchar", size = 100 }) == "varchar(100)")
  assert(column_info.format_type({ type_name = "nvarchar", size = 1073741823 }) == "nvarchar(max)")
  assert(column_info.format_type({ type_name = "decimal", precision = 12, scale = 2 }) == "decimal(12, 2)")
  assert(column_info.format_type({ type_name = "datetime2", scale = 7 }) == "datetime2(7)")
  assert(column_info.format_type({ type_name = "varchar(max)", size = 2147483647 }) == "varchar(max)")
  assert(vim.deep_equal(
    column_info.lines({
      type_name = "decimal",
      precision = 12,
      scale = 2,
      nullable = false,
      source = { schema = "dbo", table = "Product", column = "Price" },
    }),
    { "decimal(12, 2) NOT NULL", "-- Source: dbo.Product.Price" }
  ))
  assert(vim.deep_equal(
    column_info.lines({
      type_name = "money",
      nullable = true,
      isExpression = true,
    }),
    { "money NULL" }
  ))
end

T["Result column navigation follows rendered cell boundaries"] = require("tests.helpers").async(function()
  view.clear()
  view.setup({
    cell_navigation = { enabled = true, wrap = true },
    highlight_current_cell = true,
    sticky_header = true,
  })
  local source = vim.api.nvim_create_buf(false, true)
  local model = query_result.create({
    columns = { "ID", "X", "Payload" },
    column_metadata = {
      { name = "ID", type_name = "int", size = 4, nullable = false },
      { name = "X", type_name = "nvarchar", size = 20, nullable = true },
      { name = "Payload", type_name = "varchar(max)", nullable = true },
    },
    rows = {
      {
        result_cell.create({ display_value = "1" }),
        result_cell.create({ display_value = "😀" }),
        result_cell.create({ display_value = "long\nvalue" }),
      },
      {
        result_cell.create({ display_value = "2" }),
        result_cell.create({ display_value = "β" }),
        result_cell.create({ display_value = "second" }),
      },
      {
        result_cell.create({ display_value = "3" }),
        result_cell.create({ display_value = "終" }),
        result_cell.create({ display_value = "third" }),
      },
    },
    row_count = 4,
    locator = { resultSetIndex = 0 },
    ordinal = 1,
  })

  assert(view.show({ model }, {
    results = { max_cell_width = 4, history_limit = 1 },
    open_results_in = function(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
    end,
  }, source))

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  assert(view.next_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 7)
  assert(view.next_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 14)
  assert(view.next_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 0, "Next navigation should wrap to the first column")
  assert(view.previous_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 14, "Previous navigation should wrap to the final column")

  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  assert(view.refresh_current_cell())
  assert(vim.api.nvim_get_hl(0, { name = "SqlServerResultCurrentCell", link = true }).link == "Search")
  local highlight_namespace = vim.api.nvim_create_namespace("sqlserver-result-current-cell")
  local highlights = vim.api.nvim_buf_get_extmarks(0, highlight_namespace, 0, -1, { details = true })
  assert(#highlights == 1, "The current result cell was not highlighted")
  assert(highlights[1][2] == 2 and highlights[1][3] == 0)
  assert(highlights[1][4].end_col == 3, "The first cell highlight should include separator padding")
  assert(highlights[1][4].hl_group == "SqlServerResultCurrentCell")

  assert(view.next_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 7)
  highlights = vim.api.nvim_buf_get_extmarks(0, highlight_namespace, 0, -1, { details = true })
  assert(
    #highlights == 1 and highlights[1][3] == 6 and highlights[1][4].end_col == 12,
    "Interior cell highlighting should include padding without covering separators"
  )
  assert(view.next_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 16, "Unicode rows require their own byte boundaries")
  assert(view.previous_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 7)

  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  assert(view.next_cell(2))
  assert(vim.api.nvim_win_get_cursor(0)[2] == 16, "Horizontal counts should move across semantic cells")
  assert(view.previous_cell(2))
  assert(vim.api.nvim_win_get_cursor(0)[2] == 0)

  vim.cmd("normal 2l")
  assert(vim.api.nvim_win_get_cursor(0)[2] == 16, "The l mapping should pass its Vim count to cell navigation")

  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  assert(view.next_row(), "Moving down from the header should skip the divider")
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 3, 7 }))
  assert(view.next_row(2))
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 5, 7 }))
  assert(not view.next_row(), "Vertical movement should stop at the final data row")
  assert(view.previous_row(3))
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 7 }))
  assert(not view.previous_row(), "Vertical movement should stop at the header")

  vim.api.nvim_win_set_cursor(0, { 3, 16 })
  assert(view.copy_cell())
  assert(vim.fn.getreg('"') == "long\nvalue", "Cell copying should preserve the untruncated multiline value")

  vim.api.nvim_win_set_cursor(0, { 3, 7 })

  local hover_lines
  local original_preview = vim.lsp.util.open_floating_preview
  vim.lsp.util.open_floating_preview = function(lines)
    hover_lines = lines
  end
  local shown = view.show_column_info()
  vim.lsp.util.open_floating_preview = original_preview
  assert(shown)
  assert(vim.deep_equal(hover_lines, { "nvarchar(20) NULL" }))

  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.cmd("normal! v")
  assert(not view.refresh_current_cell(), "Visual mode should not retain the current-cell highlight")
  assert(#vim.api.nvim_buf_get_extmarks(0, highlight_namespace, 0, -1, {}) == 0)
  assert(view.next_cell())
  assert(view.next_row())
  local selected = assert(view.visual_selection())
  vim.cmd("normal! \27")
  assert(vim.deep_equal(selected, { row_start = 0, row_end = 1, column_start = 0, column_end = 1 }))

  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  assert(not view.refresh_current_cell(), "The rendered divider should not be highlighted as a cell")
  assert(#vim.api.nvim_buf_get_extmarks(0, highlight_namespace, 0, -1, {}) == 0)

  view.setup({
    cell_navigation = { enabled = true, wrap = false },
    highlight_current_cell = false,
    sticky_header = true,
  })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  assert(not view.refresh_current_cell(), "Disabled current-cell highlighting still created an extmark")
  assert(#vim.api.nvim_buf_get_extmarks(0, highlight_namespace, 0, -1, {}) == 0)
  assert(not view.previous_cell(), "Clamped navigation should stop at the first column")
  assert(view.next_cell(99))
  assert(vim.api.nvim_win_get_cursor(0)[2] == 16, "Clamped navigation should stop at the final column")
  assert(not view.next_cell(), "Clamped navigation should stop at the final column")
  view.setup({
    cell_navigation = { enabled = true, wrap = true },
    highlight_current_cell = false,
    sticky_header = true,
  })

  vim.api.nvim_win_set_cursor(0, { 7, 0 })
  assert(not view.next_column(), "Summary lines should not be treated as result cells")
  assert(not view.next_row(), "Summary lines should not be treated as result rows")
  assert(not view.copy_cell(), "Summary lines should not be copied as result cells")
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end)

return T
