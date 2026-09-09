local selection = require("sqlserver.results.selection")

local T = MiniTest.new_set()

local result_set = {
  columns = { "ID", "Name", "Age" },
  rows = { {}, {} },
}

local ranges = {
  [3] = {
    { start_col = 0, end_col = 2 },
    { start_col = 5, end_col = 9 },
    { start_col = 12, end_col = 15 },
  },
  [4] = {
    { start_col = 0, end_col = 2 },
    { start_col = 5, end_col = 10 },
    { start_col = 13, end_col = 15 },
  },
}

T["Result selections normalize visual cells to inclusive result indices"] = function()
  local selected = assert(selection.create(result_set, ranges, { line = 3, col = 5 }, { line = 4, col = 13 }, "\22"))
  assert(vim.deep_equal(selected, { row_start = 0, row_end = 1, column_start = 1, column_end = 2 }))

  local reversed = assert(selection.create(result_set, ranges, { line = 4, col = 13 }, { line = 3, col = 5 }, "v"))
  assert(vim.deep_equal(reversed, selected))

  local rows = assert(selection.create(result_set, ranges, { line = 3, col = 8 }, { line = 4, col = 8 }, "V"))
  assert(vim.deep_equal(rows, { row_start = 0, row_end = 1, column_start = 0, column_end = 2 }))
end

T["Result selections reject headers and summary lines"] = function()
  local selected, err = selection.create(result_set, ranges, { line = 2, col = 0 }, { line = 3, col = 5 }, "v")
  assert(not selected and err == "Select only query result data cells")

  selected, err = selection.create(result_set, ranges, { line = 3, col = 0 }, { line = 5, col = 0 }, "V")
  assert(not selected and err == "Select only query result data cells")
end

return T
