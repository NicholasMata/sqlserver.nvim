local sqlserver = require("sqlserver")
local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

local function run_action_with_search(action, pattern, expected_name)
  local completed = false
  action(function()
    completed = true
  end)

  local snacks = require("snacks")
  local picker
  assert(
    vim.wait(10000, function()
      picker = snacks.picker.get({ tab = false })[1]
      return picker and picker.shown
    end, 20),
    "Object picker did not open"
  )

  vim.api.nvim_set_current_win(picker.input.win.win)
  vim.api.nvim_buf_set_lines(picker.input.win.buf, 0, -1, false, { pattern })
  vim.api.nvim_win_set_cursor(picker.input.win.win, { 1, #pattern })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = picker.input.win.buf })
  local matched = vim.wait(10000, function()
    if picker.input.filter.pattern ~= pattern then
      return false
    end
    local item = picker:current({ resolve = false })
    return item and item.object and item.object.name == expected_name
  end, 20)
  assert(
    matched,
    string.format(
      "Searching for %s did not select %s: %s",
      pattern,
      expected_name,
      vim.inspect({ filter = picker.input.filter.pattern, current = picker:current({ resolve = false }) })
    )
  )
  assert(picker.input.filter.pattern == pattern)
  picker:action("confirm")

  assert(
    vim.wait(60000, function()
      return completed
    end, 20),
    "Object action did not finish after confirming the Snacks selection"
  )
  assert(picker.closed)
end

T["Find Query and Object Definition support real Snacks search"] = require("tests.helpers").async(function()
  local root = vim.fn.getcwd()
  vim.opt.runtimepath:prepend(vim.fs.joinpath(root, ".tests", "deps", "snacks.nvim"))
  local snacks = require("snacks")
  snacks.setup({ picker = { enabled = true } })
  require("sqlserver.objects.ui.picker").setup(
    { object_explorer = 10000 },
    require("sqlserver.objects.ui.snacks").select
  )

  local source_bufnr = vim.api.nvim_get_current_buf()
  test_utils.await(function(callback)
    sqlserver.disconnect(source_bufnr, callback)
  end)
  test_utils.connect(source_bufnr, "TestDbB")

  run_action_with_search(sqlserver.find_object, "CarsForPerson", "CarsForPerson")
  local query_bufnr = vim.api.nvim_get_current_buf()
  local query = table.concat(vim.api.nvim_buf_get_lines(query_bufnr, 0, -1, false), "\n")
  assert(query:find("CarsForPerson", 1, true) and query:upper():find("SELECT", 1, true))
  if query_bufnr ~= source_bufnr then
    vim.api.nvim_buf_delete(query_bufnr, { force = true })
  end
  vim.api.nvim_set_current_buf(source_bufnr)

  run_action_with_search(sqlserver.show_object_definition, "CarView", "CarView")
  local definition_bufnr = vim.api.nvim_get_current_buf()
  local definition = table.concat(vim.api.nvim_buf_get_lines(definition_bufnr, 0, -1, false), "\n")
  assert(definition:find("CarView", 1, true) and definition:upper():find("CREATE VIEW", 1, true))
  assert(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(definition_bufnr), ":t") == "dbo.CarView.sql")
  vim.api.nvim_buf_delete(definition_bufnr, { force = true })
end)

return T
