local object_script = require("sqlserver.core.object_script")

return {
  test_name = "Object scripting should separate queries from definitions",
  run_test_async = function()
    for _, object_type in ipairs({ "Table", "View" }) do
      local query = object_script.for_intent(object_type, "query")
      assert(query.script_create_drop == "ScriptSelect" and query.operation == 0)
      assert(query.execute_immediately == true)

      local definition = object_script.for_intent(object_type, "definition")
      assert(definition.script_create_drop == "ScriptCreate" and definition.operation == 1)
      assert(not definition.execute_immediately)
    end

    local procedure_query = object_script.for_intent("StoredProcedure", "query")
    assert(procedure_query.script_create_drop == "ScriptCreate")
    assert(procedure_query.operation == 5)
    assert(not procedure_query.execute_immediately)

    local procedure_definition = object_script.for_intent("StoredProcedure", "definition")
    assert(procedure_definition.script_create_drop == "ScriptCreate")
    assert(procedure_definition.operation == 1)

    for _, function_type in ipairs({ "ScalarValuedFunction", "TableValuedFunction" }) do
      assert(object_script.for_intent(function_type, "query").operation == 0)
      assert(object_script.for_intent(function_type, "definition").operation == 1)
    end

    local supported = object_script.supported_types()
    assert(vim.tbl_contains(supported, "Table") and vim.tbl_contains(supported, "StoredProcedure"))
    local valid, err = pcall(object_script.for_intent, "Table", "drop")
    assert(not valid and err:find("query", 1, true) and err:find("definition", 1, true))
    valid, err = pcall(object_script.for_intent, "Database", "definition")
    assert(not valid and err:find("Unsupported", 1, true))
  end,
}
