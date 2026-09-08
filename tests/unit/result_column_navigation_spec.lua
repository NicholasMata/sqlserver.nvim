local query_result = require("sqlserver.core.query_result")
local result_cell = require("sqlserver.core.result_cell")
local view = require("sqlserver.ui.results.view")

local T = MiniTest.new_set()

T["Result column navigation follows rendered cell boundaries"] = require("tests.helpers").async(function()
  view.clear()
  local source = vim.api.nvim_create_buf(false, true)
  local model = query_result.create({
    columns = { "ID", "X", "Payload" },
    rows = {
      {
        result_cell.create({ display_value = "1" }),
        result_cell.create({ display_value = "😀" }),
        result_cell.create({ display_value = "long value" }),
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

  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  assert(not view.next_column(), "Summary lines should not be treated as result cells")
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end)

return T
