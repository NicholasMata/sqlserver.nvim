local explorer = require("sqlserver.objects.explorer")

local T = MiniTest.new_set()

T["Object explorer preserves the SQL Tools Service hierarchy"] = function()
  local root = explorer.build({ server = "localhost", database = "TestDb" }, {
    { id = "table-a", name = "Account", type = "Table", path = "Tables/" },
    { id = "view-a", name = "Adults", type = "View", path = "Views/" },
    {
      id = "procedure-a",
      name = "GetAccount",
      type = "StoredProcedure",
      path = "Programmability/Stored Procedures/",
    },
  })

  assert(root.kind == "server" and root.label == "localhost")
  local database = root.children[1]
  assert(database.kind == "database" and database.label == "TestDb")
  assert(#database.children == 3)

  local tables = database.children[1]
  assert(tables.label == "Tables")
  assert(tables.children[1].label == "Account")

  local views = database.children[2]
  assert(views.label == "Views")
  assert(views.children[1].object.id == "view-a")

  local programmability = database.children[3]
  assert(programmability.label == "Programmability")
  assert(programmability.children[1].label == "Stored Procedures")
  assert(programmability.children[1].children[1].object.id == "procedure-a")
end

T["Object explorer represents every supported object type in service order"] = function()
  local root = explorer.build({ server = "localhost", database = "TestDb" }, {
    { id = "table", name = "Table / [One]", type = "Table", path = "Tables/" },
    { id = "view", name = "Résumé View", type = "View", path = "Views/" },
    {
      id = "procedure",
      name = "Run Report",
      type = "StoredProcedure",
      path = "Programmability/Stored Procedures/",
    },
    {
      id = "scalar-function",
      name = "Calculate Total",
      type = "ScalarValuedFunction",
      path = "Programmability/Functions/Scalar-valued Functions/",
    },
    {
      id = "table-function",
      name = "List Rows",
      type = "TableValuedFunction",
      path = "Programmability/Functions/Table-valued Functions/",
    },
  })

  local database = root.children[1]
  assert(vim.deep_equal(
    vim.tbl_map(function(item)
      return item.label
    end, database.children),
    { "Tables", "Views", "Programmability" }
  ))
  assert(database.children[1].children[1].label == "Table / [One]")
  assert(database.children[2].children[1].label == "Résumé View")
  local programmability = database.children[3]
  assert(vim.deep_equal(
    vim.tbl_map(function(item)
      return item.label
    end, programmability.children),
    { "Stored Procedures", "Functions" }
  ))
  assert(programmability.children[2].children[1].children[1].object.type == "ScalarValuedFunction")
  assert(programmability.children[2].children[2].children[1].object.type == "TableValuedFunction")
end

T["Object explorer attaches lazy SQL Tools Service children"] = function()
  local root = explorer.build({ server = "localhost", database = "TestDb" }, {
    { id = "table-a", name = "Person", schema = "dbo", type = "Table", path = "Tables/" },
  })
  local person = root.children[1].children[1].children[1]
  assert(person.loadable and not person.loaded)
  explorer.set_children(person, {
    { id = "table-a/Columns", label = "Columns", type = "Folder", expandable = true },
  })
  assert(person.loaded and person.children[1].label == "Columns")
  assert(person.children[1].loadable and not person.children[1].loaded)
end

T["Object explorer preserves known and future detail node types"] = function()
  local root = explorer.build({ server = "localhost", database = "TestDb" }, {
    { id = "table-a", name = "Person", type = "Table", path = "Tables/" },
  })
  local person = root.children[1].children[1].children[1]
  local types = { "Column", "Key", "Constraint", "Index", "Statistic", "Trigger", "Parameter", "FutureNode" }
  explorer.set_children(
    person,
    vim.tbl_map(function(node_type)
      return { id = "table-a/" .. node_type, label = node_type, type = node_type }
    end, types)
  )

  assert(#person.children == #types)
  for index, node_type in ipairs(types) do
    assert(person.children[index].node_type == node_type)
    assert(type(person.children[index].icon) == "string" and person.children[index].icon ~= "")
  end
end

T["Object explorer accepts empty child collections"] = function()
  local root = explorer.build({ server = "localhost", database = "TestDb" }, {
    { id = "view-a", name = "EmptyView", type = "View", path = "Views/", expandable = true },
  })
  local view = root.children[1].children[1].children[1]
  explorer.set_children(view, {})
  assert(view.loaded and #view.children == 0)
end

T["Object explorer does not retain connection secrets"] = function()
  local root = explorer.build({ server = "localhost", database = "TestDb", password = "secret" }, {})
  assert(root.password == nil)
  assert(not vim.inspect(root):find("secret", 1, true))
end

return T
