local result_options = require("sqlserver.config.results")

local T = MiniTest.new_set()

T["Result options should normalize cell navigation"] = function()
  assert(vim.deep_equal(result_options.normalize_cell_navigation(true), { enabled = true, wrap = true }))
  assert(vim.deep_equal(result_options.normalize_cell_navigation(false), { enabled = false, wrap = true }))
  assert(vim.deep_equal(result_options.normalize_cell_navigation({}), { enabled = true, wrap = true }))
  assert(vim.deep_equal(result_options.normalize_cell_navigation({ wrap = false }), { enabled = true, wrap = false }))

  local ok, err = pcall(result_options.normalize_cell_navigation, "cells")
  assert(not ok and err:find("true, false, or a table", 1, true))
  ok, err = pcall(result_options.normalize_cell_navigation, { wrap = "yes" })
  assert(not ok and err:find("wrap must be true or false", 1, true))
  ok, err = pcall(result_options.normalize_cell_navigation, { vertical_wrap = true })
  assert(not ok and err:find("Unknown results.cell_navigation option", 1, true))
end

return T
