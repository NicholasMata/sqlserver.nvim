local sqlserver = require("sqlserver")
local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

local function search(picker, pattern, expected_label)
  vim.api.nvim_set_current_win(picker.input.win.win)
  picker.input:set(pattern)
  picker:find()
  assert(
    vim.wait(10000, function()
      if picker.input.filter.pattern ~= pattern or picker.matcher:running() then
        return false
      end
      local first = picker.list:get(1)
      if not first or not first.search_all then
        return false
      end
      for index = 1, picker.list:count() do
        local item = picker.list:get(index)
        if item and item.label == expected_label then
          picker.list:view(index)
          return true
        end
      end
      return false
    end, 20),
    string.format("Searching for %s did not select %s", pattern, expected_label)
  )
end

local function press_normal(key)
  vim.cmd("stopinsert")
  assert(
    vim.wait(1000, function()
      return vim.fn.mode():find("^n") ~= nil
    end, 10),
    "Snacks input did not leave insert mode"
  )
  assert(vim.fn.maparg(key, "n") ~= "", string.format("Snacks input has no normal-mode %s mapping", key))
  vim.api.nvim_feedkeys(key, "xt", false)
end

T["Object Explorer works with a real Snacks picker"] = require("tests.helpers").async(function()
  local source_bufnr = vim.api.nvim_get_current_buf()
  test_utils.await(function(callback)
    sqlserver.disconnect(source_bufnr, callback)
  end)
  test_utils.connect(source_bufnr, "TestDbB")

  local root = vim.fn.getcwd()
  vim.opt.runtimepath:prepend(vim.fs.joinpath(root, ".tests", "deps", "snacks.nvim"))

  local snacks = require("snacks")
  snacks.setup({ picker = { enabled = true } })

  sqlserver.object_explorer()
  local picker
  assert(
    vim.wait(10000, function()
      picker = snacks.picker.get({ tab = false })[1]
      return picker and picker.shown and picker.list:count() >= 3
    end, 20),
    "Object Explorer did not open a real Snacks picker"
  )

  assert(picker.opts.title == "SQL Server Object Explorer")
  assert(picker.opts.win.list.keys.l == "object_toggle")
  assert(picker.opts.win.list.keys.h == "object_collapse")
  assert(picker.opts.win.list.keys.L == "object_expand_all")
  assert(picker.opts.win.list.keys.H == "object_collapse_all")
  assert(picker.opts.win.list.keys.K == "object_actions")
  assert(type(picker.opts.win.list.actions.object_toggle.action) == "function")

  local tables
  for index = 1, picker.list:count() do
    local item = picker.list:get(index)
    if item and item.label == "Tables" then
      tables = item
      break
    end
  end
  assert(tables, "Object Explorer did not contain SQL Tools Service's Tables node")
  picker.opts.actions.object_toggle(picker, tables)
  assert(
    vim.wait(10000, function()
      return tables.node.loaded and not picker.matcher:running()
    end, 20),
    "Object Explorer did not load Tables before searching"
  )

  search(picker, "Car", "dbo.Car")
  local filtered_labels = {}
  for index = 1, picker.list:count() do
    filtered_labels[#filtered_labels + 1] = picker.list:get(index).label
  end
  assert(
    picker.list:count() == 4,
    "Filtered Object Explorer included unrelated nodes: " .. vim.inspect(filtered_labels)
  )
  press_normal("K")
  local action_picker
  assert(
    vim.wait(1000, function()
      for _, candidate in ipairs(snacks.picker.get({ tab = false })) do
        if candidate ~= picker and candidate.opts.source == "select" then
          action_picker = candidate
          return candidate.shown
        end
      end
      return false
    end, 20),
    "K did not open the object action menu after searching"
  )
  action_picker:close()

  vim.api.nvim_set_current_win(picker.input.win.win)
  picker.input:set("NoSuchDatabaseObject")
  picker:find()
  assert(
    vim.wait(1000, function()
      local first = picker.list:get(1)
      local second = picker.list:get(2)
      return picker.input.filter.pattern == "NoSuchDatabaseObject"
        and not picker.matcher:running()
        and picker.list:count() == 2
        and first
        and first.search_all
        and first.label == "Search all objects…"
        and second
        and second.placeholder
        and second.label == "No matching loaded objects"
    end, 20),
    "Empty object search did not show its no-match row"
  )

  picker.opts.actions.object_toggle(picker, picker:current({ resolve = false }))
  picker.opts.actions.object_collapse(picker, picker:current({ resolve = false }))
  picker.opts.actions.object_actions(picker, picker:current({ resolve = false }))
  picker:close()
  assert(
    vim.wait(1000, function()
      return #snacks.picker.get({ tab = false }) == 0
    end, 10),
    "Real Snacks picker did not close cleanly"
  )
end)

return T
