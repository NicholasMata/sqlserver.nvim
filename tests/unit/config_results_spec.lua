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

T["Result options should normalize column icons"] = function()
  local defaults = result_options.default_column_icons
  assert(vim.deep_equal(result_options.normalize_column_icons(true), { enabled = true, icons = defaults }))
  assert(vim.deep_equal(result_options.normalize_column_icons(false), { enabled = false, icons = defaults }))

  local custom = result_options.normalize_column_icons({ text = "T", unknown = "", nullable = "?" })
  assert(custom.enabled and custom.icons.text == "T" and custom.icons.unknown == "")
  assert(custom.icons.nullable == "?")
  assert(custom.icons.number == defaults.number, "Partial icon configuration should retain defaults")

  local ok, err = pcall(result_options.normalize_column_icons, "icons")
  assert(not ok and err:find("true, false, or a table", 1, true))
  ok, err = pcall(result_options.normalize_column_icons, { text = 1 })
  assert(not ok and err:find("column_icons.text must be a string", 1, true))
  ok, err = pcall(result_options.normalize_column_icons, { spatial = "S" })
  assert(not ok and err:find("Unknown results.column_icons option", 1, true))
end

return T
