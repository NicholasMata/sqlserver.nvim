local sqlserver = require("sqlserver")
local integration = require("tests.helpers.integration")

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

local T = MiniTest.new_set()

local function read_file(path)
  local fd = assert(vim.uv.fs_open(path, "r", 438))
  local stat = assert(vim.uv.fs_fstat(fd))
  local contents = vim.uv.fs_read(fd, stat.size, 0) or ""
  vim.uv.fs_close(fd)
  return contents
end

local function export(execution, extension)
  local path = vim.fn.tempname() .. "." .. extension
  local result, err = await(function(callback)
    sqlserver.export_results({
      result_set = execution.result_sets[1],
      path = path,
    }, callback)
  end)
  assert(not err, err and err.message)
  return result, path, read_file(path)
end

T["Public API should execute and inspect live SQL Server state"] = require("tests.helpers").async(function()
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

  local _, csv_path, csv = export(execution, "csv")
  assert(csv:find("ApiValue", 1, true) and csv:find("42", 1, true))
  vim.fn.delete(csv_path)

  local _, json_path, json = export(execution, "json")
  local decoded = vim.json.decode(json)
  assert(decoded[1].ApiValue == 42 or decoded[1].ApiValue == "42")
  vim.fn.delete(json_path)

  local _, xml_path, xml = export(execution, "xml")
  assert(xml:find("ApiValue", 1, true) and xml:find("42", 1, true))
  vim.fn.delete(xml_path)

  local _, excel_path, excel = export(execution, "xlsx")
  assert(excel:sub(1, 2) == "PK", "XLSX export should be an OOXML archive")
  assert(excel:find("PK\005\006", 1, true), "XLSX export should contain a ZIP end record")
  vim.fn.delete(excel_path)

  local newer_execution = await(function(callback)
    sqlserver.execute({ bufnr = 0, text = "SELECT 84 AS NewValue" }, callback)
  end)
  local stale_path = vim.fn.tempname() .. ".csv"
  local _, stale_error = await(function(callback)
    sqlserver.export_results({ result_set = execution.result_sets[1], path = stale_path }, callback)
  end)
  assert(stale_error and stale_error.message:find("no longer available", 1, true))
  assert(vim.fn.filereadable(stale_path) == 0, "A stale execution must not write an export file")
  assert(execution.dispose())

  assert(newer_execution.dispose())
  assert(not newer_execution.dispose(), "A public execution should only be disposed once")
  integration.defer_async(100)
  local disposed_path = vim.fn.tempname() .. ".csv"
  local _, disposed_export_error = await(function(callback)
    sqlserver.export_results({ result_set = newer_execution.result_sets[1], path = disposed_path }, callback)
  end)
  assert(disposed_export_error, "Disposed SQL Tools Service results should no longer be exportable")
  vim.fn.delete(disposed_path)

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
end)

return T
