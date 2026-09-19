local sqlserver = require("sqlserver")
local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

T["Object Explorer completes an object workflow"] = require("tests.helpers").async(function()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local source_workspace = assert(require("sqlserver.workspace.registry").get(source_bufnr))
  test_utils.await(function(callback)
    sqlserver.disconnect(source_bufnr, callback)
  end)
  test_utils.connect(source_bufnr, "TestDbB")
  local picker_options
  local focus_count = 0
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
    refresh = function() end,
    focus = function(_, target)
      assert(target == "list")
      focus_count = focus_count + 1
    end,
    norm = function(_, callback)
      callback()
    end,
  }
  local previous_snacks = package.loaded.snacks
  local fake_snacks = {
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
  package.loaded.snacks = fake_snacks
  sqlserver.object_explorer()
  assert(
    vim.wait(60000, function()
      return picker_options ~= nil
    end, 20),
    "Object Explorer did not open the Snacks picker"
  )
  package.loaded.snacks = previous_snacks

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

  local initial_items = picker_options.finder()
  local programmability = vim.iter(initial_items):find(function(item)
    return item.label == "Programmability"
  end)
  local tables = vim.iter(initial_items):find(function(item)
    return item.label == "Tables"
  end)
  local views = vim.iter(initial_items):find(function(item)
    return item.label == "Views"
  end)
  assert(programmability and tables and views, "Object Explorer did not preserve the database root children")

  local programmability_children = expand(programmability)
  local stored_procedures = assert_child(programmability_children, "Stored Procedures")
  local functions = assert_child(programmability_children, "Functions")
  expand(stored_procedures)
  local procedure = assert(find_object("StoredProcedure"), "Object Explorer did not load stored procedures")
  assert(procedure.parent and procedure.parent.label == "Stored Procedures")
  assert(procedure.parent.parent and procedure.parent.parent.label == "Programmability")

  expand(views)
  local view = assert(find_object("View", "CarView"), "Object Explorer did not include the seeded view")

  local function_folders = expand(functions)
  for _, folder in ipairs(function_folders) do
    if folder.node.isLeaf == false then
      expand(folder)
    end
  end
  local scalar_function =
    assert(find_object("ScalarValuedFunction", "GetCarMake"), "Object Explorer did not include the scalar function")
  local table_function =
    assert(find_object("TableValuedFunction", "CarsForPerson"), "Object Explorer did not include the table function")
  assert(view.parent.label == "Views")
  assert(scalar_function.parent.parent.label == "Functions")
  assert(table_function.parent.parent.label == "Functions")
  expand(tables)
  local items = picker_options.finder()
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
  assert(columns.node.isLeaf == false, "SQL Tools Service Columns node was not expandable")
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

  for _, object in ipairs({ procedure, scalar_function, table_function, view }) do
    for _, child in ipairs(expand(object)) do
      assert(child.parent.id == object.id)
      assert(vim.startswith(child.node.nodePath, object.node.nodePath .. "/"))
    end
  end

  picker_options.actions.object_definition(picker, car)
  assert(
    vim.wait(60000, function()
      local object = vim.b.sqlserver_object
      return object and object.name == "Car"
    end, 20),
    "Object Explorer definition action did not open the Car definition"
  )
  local definition_bufnr = vim.api.nvim_get_current_buf()
  local definition = table.concat(vim.api.nvim_buf_get_lines(definition_bufnr, 0, -1, false), "\n")
  assert(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(definition_bufnr), ":t") == "dbo.Car.sql")
  assert(definition:upper():find("CREATE TABLE", 1, true))
  vim.api.nvim_buf_delete(definition_bufnr, { force = true })
  vim.api.nvim_set_current_buf(source_bufnr)

  package.loaded.snacks = fake_snacks
  sqlserver.object_explorer()
  package.loaded.snacks = previous_snacks
  assert(focus_count == 1, "Reopening Object Explorer did not focus its existing picker")

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

  vim.api.nvim_set_current_buf(source_bufnr)
  sqlserver.commands.disconnect()
  assert(
    vim.wait(30000, function()
      return source_workspace.get_state() == require("sqlserver.workspace").states.disconnected
    end, 20),
    "Object Explorer workspace did not disconnect"
  )
  assert(picker.closed, "Disconnecting did not close Object Explorer")
  assert(source_workspace.get_active_operation() == nil, "Disconnect left an active workspace operation")
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
