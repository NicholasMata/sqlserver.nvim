local sqlserver = require("sqlserver")
local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

T["Object Explorer queries an object from the metadata tree"] = require("tests.helpers").async(function()
  local source_bufnr = vim.api.nvim_get_current_buf()
  test_utils.await(function(callback)
    sqlserver.disconnect(source_bufnr, callback)
  end)
  test_utils.connect(source_bufnr, "TestDbB")
  local picker_options
  local picker = {
    closed = false,
    main = vim.api.nvim_get_current_win(),
    matcher = { opts = {} },
    close = function(self)
      self.closed = true
    end,
    filter = function()
      return {
        is_empty = function()
          return true
        end,
      }
    end,
    find = function() end,
    norm = function(_, callback)
      callback()
    end,
  }
  local previous_snacks = package.loaded.snacks
  package.loaded.snacks = {
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      pick = function(options)
        picker_options = options
        picker.matcher.opts = options.matcher
        return picker
      end,
    },
  }

  sqlserver.object_explorer()
  package.loaded.snacks = previous_snacks
  assert(picker_options, "Object Explorer did not open the Snacks picker")

  picker_options.filter.transform(picker, {
    is_empty = function()
      return false
    end,
  })
  local searched_items = picker_options.finder()
  local function find_object(object_type, name)
    return vim.iter(picker_options.finder()):find(function(item)
      return item.object and item.object.type == object_type and (not name or item.object.name == name)
    end)
  end
  local function expand(item)
    picker_options.actions.object_toggle(picker, item)
    assert(
      vim.wait(60000, function()
        return item.node.loaded
      end, 20),
      "Object Explorer did not finish expanding " .. item.label
    )
    return vim
      .iter(picker_options.finder())
      :filter(function(candidate)
        return candidate.parent and candidate.parent.id == item.id
      end)
      :totable()
  end
  local function assert_child(parent, label)
    local child = vim.iter(parent):find(function(item)
      return item.label == label
    end)
    assert(child, "Object Explorer children did not include " .. label .. ": " .. vim.inspect(parent))
    return child
  end
  local function assert_named_child(parent, name)
    local child = vim.iter(parent):find(function(item)
      return vim.startswith(item.label, name)
    end)
    assert(child, "Object Explorer children did not include " .. name .. ": " .. vim.inspect(parent))
    return child
  end

  local procedure = vim.iter(searched_items):find(function(item)
    return item.object and item.object.type == "StoredProcedure"
  end)
  assert(procedure, "Object Explorer did not include a stored procedure: " .. vim.inspect(searched_items))
  assert(procedure.parent and procedure.parent.label == "Stored Procedures")
  assert(procedure.parent.parent and procedure.parent.parent.label == "Programmability")
  local view = assert(find_object("View", "CarView"), "Object Explorer did not include the seeded view")
  local scalar_function =
    assert(find_object("ScalarValuedFunction", "GetCarMake"), "Object Explorer did not include the scalar function")
  local table_function =
    assert(find_object("TableValuedFunction", "CarsForPerson"), "Object Explorer did not include the table function")
  assert(view.parent.label == "Views")
  assert(scalar_function.parent.parent.label == "Functions")
  assert(table_function.parent.parent.label == "Functions")
  picker_options.filter.transform(picker, {
    is_empty = function()
      return true
    end,
  })

  local items = picker_options.finder()
  local tables = vim.iter(items):find(function(item)
    return item.label == "Tables"
  end)
  assert(tables, "Object Explorer did not include Tables")
  picker_options.actions.object_toggle(picker, tables)
  items = picker_options.finder()
  local car = vim.iter(items):find(function(item)
    return item.object and item.object.name == "Car"
  end)
  assert(car, "Car was not present in the Object Explorer tree")

  local car_children = expand(car)
  local columns
  columns = assert_child(car_children, "Columns")
  local keys = assert_child(car_children, "Keys")
  local constraints = assert_child(car_children, "Constraints")
  local indexes = assert_child(car_children, "Indexes")
  local statistics = assert_child(car_children, "Statistics")
  local triggers = assert_child(car_children, "Triggers")
  assert(columns.node.loadable, "SQL Tools Service Columns node was not expandable")
  local column_children = expand(columns)
  assert(
    vim.iter(column_children):any(function(item)
      return item.label == "ID" or vim.startswith(item.label, "ID ")
    end),
    "Car Columns did not include ID: " .. vim.inspect(column_children)
  )
  assert_named_child(expand(keys), "PK__Car")
  assert_named_child(expand(constraints), "CK_Car_PersonId")
  assert_named_child(expand(indexes), "IX_Car_Make")
  assert_named_child(expand(statistics), "IX_Car_Make")
  assert_named_child(expand(triggers), "CarInsertTrigger")

  assert(#expand(procedure) == 0, "SQL Tools Service unexpectedly returned stored procedure children")
  assert(#expand(scalar_function) == 0, "SQL Tools Service unexpectedly returned scalar function children")
  local table_function_children = expand(table_function)
  assert(#table_function_children == 0, "SQL Tools Service unexpectedly returned table function children")
  assert(#expand(view) == 0, "SQL Tools Service unexpectedly returned view children")

  picker_options.confirm(picker, car)

  assert(
    vim.wait(60000, function()
      return vim.b.query_result_info ~= nil
    end, 20),
    "Object Explorer query did not produce results"
  )
  local results = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(results:find("Merc", 1, true) and results:find("Hyundai", 1, true))
  assert(vim.b.query_result_info.source_bufnr == source_bufnr)
end)

T["Object Explorer expands objects visible to a restricted user"] = require("tests.helpers").async(function()
  local restricted_bufnr = test_utils.new_query_buffer()
  test_utils.connect_with(restricted_bufnr, {
    database = "TestDbB",
    user = "sqlserver_nvim_restricted",
    password = "Restricted_Password_123",
  })
  local workspace = assert(require("sqlserver.workspace.registry").get(restricted_bufnr))
  local car = vim.iter(workspace.list_objects()):find(function(object)
    return object.type == "Table" and object.name == "Car"
  end)
  assert(car, "Restricted Object Explorer metadata did not include the granted table")

  local children = workspace.list_object_children_async(car)
  assert(
    vim.iter(children):any(function(child)
      return child.label == "Columns" and child.expandable
    end),
    "Restricted Object Explorer could not expand the granted table"
  )
  local activity = workspace.get_activity()
  assert(activity[#activity].title == "SQL Server Object Explorer")
  assert(activity[#activity].status == "success")
end)

return T
