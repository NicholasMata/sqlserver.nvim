local api = require("sqlserver.api")
local workspace_module = require("sqlserver.core.workspace")
local registry = require("sqlserver.core.workspace_registry")
local query_backend = require("sqlserver.adapters.sql_tools_service.query_backend")

local function completed(invoke)
  local calls = 0
  local result
  local err
  invoke(function(value, failure)
    calls = calls + 1
    result = value
    err = failure
  end)
  assert(calls == 1, "Public API callback should run exactly once")
  return result, err
end

return {
  test_name = "Public API should expose UI-independent workspace operations",
  run_test_async = function()
    local backend = {
      owner_uri = "file:///public-api.sql",
      client = {},
      connect_async = function()
        return { connectionSummary = { databaseName = "ApplicationDb" } }
      end,
      disconnect_async = function() end,
      execute_async = function()
        return {
          ownerUri = "file:///public-api.sql",
          batchSummaries = {
            { hasError = false, resultSetSummaries = { { rowCount = 0, columnInfo = {} } } },
          },
        }
      end,
      cancel_async = function() end,
      rebuild_intellisense = function() end,
    }
    local objects = {
      initialise_cache_async = function() end,
      is_refreshing = function()
        return false
      end,
      list = function(_, filters)
        return { { id = "table-1", name = filters.name or "Person", schema = "dbo", type = "Table" } }
      end,
      script_async = function(_, _, opts)
        return { script = "SELECT * FROM dbo.Person", intent = opts.intent }
      end,
    }
    local workspace = workspace_module.create({ bufnr = 321, backend = backend, objects = objects })
    registry.attach(321, workspace)
    local connections_file = vim.fn.tempname()
    vim.fn.writefile({
      vim.json.encode({
        development = {
          server = "localhost",
          database = "master",
          authenticationType = "SqlLogin",
          user = "sa",
          password = "Secret123",
        },
      }),
    }, connections_file)
    api.configure({ results = { max_rows = 0 }, connections_file = connections_file })

    local connection, err = completed(function(callback)
      api.connect("development", { bufnr = 321 }, callback)
    end)
    vim.fn.delete(connections_file)
    assert(not err and connection.database == "ApplicationDb")
    assert(connection.password == nil, "Public connection snapshots must not expose passwords")
    local current = api.current_connection(321)
    assert(current.server == "localhost" and current.password == nil)

    local pending_execution
    backend.execute_async = function()
      pending_execution = coroutine.running()
      return coroutine.yield()
    end
    local cancellation_result
    local cancellation_calls = 0
    api.execute({ bufnr = 321, text = "WAITFOR" }, function(value, failure)
      assert(not failure)
      cancellation_calls = cancellation_calls + 1
      cancellation_result = value
    end)
    assert(pending_execution and cancellation_calls == 0)
    local cancellation = completed(function(callback)
      api.cancel(321, callback)
    end)
    assert(cancellation.cancellation_requested)
    assert(coroutine.resume(pending_execution, { batchSummaries = {} }))
    assert(cancellation_calls == 1 and cancellation_result.cancelled)

    backend.execute_async = function()
      return {
        ownerUri = "file:///public-api.sql",
        batchSummaries = {
          { hasError = false, resultSetSummaries = { { rowCount = 0, columnInfo = {} } } },
        },
      }
    end
    local execution = completed(function(callback)
      api.execute({ bufnr = 321, text = "SELECT 1" }, callback)
    end)
    assert(execution.summary.row_count == 0 and #execution.result_sets == 1)

    local listed = completed(function(callback)
      api.list_objects({ bufnr = 321, name = "Person" }, callback)
    end)
    assert(listed[1].id == "table-1")
    local scripted = completed(function(callback)
      api.script_object({ bufnr = 321, id = "table-1", intent = "query" }, callback)
    end)
    assert(scripted.script == "SELECT * FROM dbo.Person" and scripted.intent == "query")

    local original_export = query_backend.export_result_async
    local exported
    query_backend.export_result_async = function(locator, path, format)
      exported = { locator = locator, path = path, format = format }
    end
    local export_result = completed(function(callback)
      api.export_results({
        result_set = { locator = { ownerUri = "file:///public-api.sql" } },
        path = "/tmp/result.csv",
      }, callback)
    end)
    query_backend.export_result_async = original_export
    assert(export_result.format == "csv" and exported.path == "/tmp/result.csv")

    local disconnected = completed(function(callback)
      api.disconnect(321, callback)
    end)
    assert(disconnected.disconnected)
    local reconnected = completed(function(callback)
      api.reconnect(321, callback)
    end)
    assert(reconnected.database == "ApplicationDb")
    completed(function(callback)
      api.disconnect(321, callback)
    end)
    local _, profile_error = completed(function(callback)
      api.connect("missing", { bufnr = 321 }, callback)
    end)
    assert(profile_error.code == "profile_not_found")
    local _, cancellation_error = completed(function(callback)
      api.cancel(321, callback)
    end)
    assert(cancellation_error.code == "cancellation_failed")
    registry.detach(321)
    local _, workspace_error = api.current_connection(321)
    assert(workspace_error.code == "workspace_not_found")
  end,
}
