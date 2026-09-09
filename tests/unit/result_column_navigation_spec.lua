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
    },
    row_count = 2,
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
  assert(view.next_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 7)
  assert(view.next_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 16, "Unicode rows require their own byte boundaries")
  assert(view.previous_column())
  assert(vim.api.nvim_win_get_cursor(0)[2] == 7)

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

  vim.api.nvim_win_set_cursor(0, { 3, 7 })
  vim.cmd("normal! v")
  local selected = assert(view.visual_selection())
  vim.cmd("normal! \27")
  assert(vim.deep_equal(selected, { row_start = 0, row_end = 0, column_start = 1, column_end = 1 }))

  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  assert(not view.next_column(), "Summary lines should not be treated as result cells")
  assert(not view.copy_cell(), "Summary lines should not be copied as result cells")
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end)

return T
