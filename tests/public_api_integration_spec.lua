local sqlserver = require("sqlserver")

local function await(invoke)
  local co = coroutine.running()
  local completed = false
  local value
  local failure
  invoke(function(result, err)
    completed = true
    value = result
    failure = err
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co)
    end
  end)
  if not completed then
    coroutine.yield()
  end
  return value, failure
end

return {
  test_name = "Public API should execute and inspect live SQL Server state",
  run_test_async = function()
    local connection, connection_error = sqlserver.current_connection(0)
    assert(not connection_error and connection.database)
    assert(connection.password == nil and connection.azureAccountToken == nil)

    local execution, execution_error = await(function(callback)
      sqlserver.execute({ bufnr = 0, text = "SELECT 42 AS ApiValue" }, callback)
    end)
    assert(not execution_error, execution_error and execution_error.message)
    assert(execution.summary.row_count == 1 and #execution.result_sets == 1)
    assert(execution.result_sets[1].columns[1] == "ApiValue")
    assert(execution.result_sets[1].rows[1][1].display_value == "42")

    local export_path = vim.fn.tempname() .. ".csv"
    local exported, export_error = await(function(callback)
      sqlserver.export_results({ result_set = execution.result_sets[1], path = export_path }, callback)
    end)
    assert(not export_error, export_error and export_error.message)
    assert(exported.path == export_path and vim.fn.filereadable(export_path) == 1)
    vim.fn.delete(export_path)

    local objects, object_error = await(function(callback)
      sqlserver.list_objects({ bufnr = 0, name = "spt_monitor", schema = "dbo", type = "Table" }, callback)
    end)
    assert(not object_error, object_error and object_error.message)
    assert(#objects == 1 and objects[1].name == "spt_monitor")
    local script, script_error = await(function(callback)
      sqlserver.script_object({ bufnr = 0, object = objects[1], intent = "query" }, callback)
    end)
    assert(not script_error, script_error and script_error.message)
    assert(script.script:find("SELECT", 1, true))
  end,
}
