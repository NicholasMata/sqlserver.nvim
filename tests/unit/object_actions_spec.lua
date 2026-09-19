local actions = require("sqlserver.objects.actions")

local T = MiniTest.new_set()

T["Object actions describe contextual query behavior"] = function()
  local expectations = {
    Table = "Select rows",
    View = "Select rows",
    StoredProcedure = "Create execution script",
    ScalarValuedFunction = "Create query script",
    TableValuedFunction = "Create query script",
  }
  for object_type, query_label in pairs(expectations) do
    local available = actions.for_object({ type = object_type, name = "Object" })
    assert(available[1].id == "query" and available[1].label == query_label)
    assert(vim.deep_equal(
      vim.tbl_map(function(action)
        return action.id
      end, available),
      { "query", "definition", "copy_name", "copy_qualified_name", "refresh" }
    ))
  end
end

T["Object actions quote qualified SQL Server names"] = function()
  assert(
    actions.qualified_name({ schema = "reporting]archive", name = "Order Details]" })
      == "[reporting]]archive].[Order Details]]]"
  )
  assert(actions.qualified_name({ name = "Server Setting" }) == "[Server Setting]")
end

return T
