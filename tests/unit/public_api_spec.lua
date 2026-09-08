local api = require("sqlserver.api")
local workspace_module = require("sqlserver.core.workspace")
local registry = require("sqlserver.core.workspace_registry")

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

local T = MiniTest.new_set()

T["Public API should expose UI-independent workspace operations"] = require("tests.helpers").async(function()
  local exported
  local backend = {
    owner_uri = "file:///public-api.sql",
    client = {},
    connect_async = function()
      return { connectionSummary = { databaseName = "ApplicationDb" } }
    end,
    disconnect_async = function() end,
    execute_async = function()
      return {
        _sqlserver_query_id = 1,
        ownerUri = "file:///public-api.sql",
        batchSummaries = {
          { hasError = false, resultSetSummaries = { { rowCount = 0, columnInfo = {} } } },
        },
      }
    end,
    cancel_async = function() end,
    dispose_query_async = function() end,
    export_result_async = function(locator, path, format, opts)
      exported = { locator = locator, path = path, format = format, opts = opts }
    end,
    rebuild_intellisense = function() end,
  }
  local refreshing = false
  local has_cache = true
  local objects = {
    initialise_cache_async = function()
      return { cancelled = false, count = 1 }
    end,
    is_refreshing = function()
      return refreshing
    end,
    has_cache = function()
      return has_cache
    end,
    list = function(_, filters)
      return { { id = "table-1", name = filters.name or "Person", schema = "dbo", type = "Table" } }
    end,
    script_async = function(_, _, _, opts)
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
  api.configure({ results = { max_rows = 0 }, timeouts = { export = 10000 }, connections_file = connections_file })

  local connection, err = completed(function(callback)
    api.connect("development", { bufnr = 321 }, callback)
  end)
  vim.fn.delete(connections_file)
  assert(not err and connection.database == "ApplicationDb")
  assert(connection.password == nil, "Public connection snapshots must not expose passwords")
  local current = api.current_connection(321)
  assert(current.server == "localhost" and current.password == nil)
  local refreshed = completed(function(callback)
    api.refresh_objects(321, callback)
  end)
  assert(refreshed.count == 1)

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
      _sqlserver_query_id = 2,
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
  local disposed_queries = 0
  local disposed_query_id
  backend.dispose_query_async = function(query_id)
    disposed_query_id = query_id
    disposed_queries = disposed_queries + 1
  end
  assert(execution.dispose())
  assert(not execution.dispose())
  assert(disposed_queries == 1, "Public query results should only be released once")
  assert(disposed_query_id == 2)

  backend.execute_async = function()
    return { _sqlserver_query_id = 3, ownerUri = "file:///public-api.sql", batchSummaries = {} }
  end
  local empty_execution = completed(function(callback)
    api.execute({ bufnr = 321, text = "PRINT 'done'" }, callback)
  end)
  assert(#empty_execution.result_sets == 0)
  assert(not empty_execution.dispose(), "Executions without results should be disposed automatically")
  assert(disposed_queries == 2, "Result-free executions should release SQL Tools Service storage")
  assert(disposed_query_id == 3)

  local listed = completed(function(callback)
    api.list_objects({ bufnr = 321, name = "Person" }, callback)
  end)
  assert(listed[1].id == "table-1")
  refreshing = true
  has_cache = false
  local _, refreshing_error = completed(function(callback)
    api.list_objects({ bufnr = 321 }, callback)
  end)
  assert(refreshing_error.code == "metadata_refreshing")
  refreshing = false
  has_cache = true
  local scripted = completed(function(callback)
    api.script_object({ bufnr = 321, id = "table-1", intent = "query" }, callback)
  end)
  assert(scripted.script == "SELECT * FROM dbo.Person" and scripted.intent == "query")

  local export_result = completed(function(callback)
    api.export_results({
      result_set = { locator = { ownerUri = "file:///public-api.sql" } },
      path = "/tmp/result.csv",
    }, callback)
  end)
  assert(export_result.format == "csv" and exported.path == "/tmp/result.csv")

  assert(exported.opts.timeout == 10000)

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
end)

return T
