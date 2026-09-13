local api = require("sqlserver.api")
local result_cell = require("sqlserver.results.cell")
local workspace_module = require("sqlserver.workspace")
local activity_stream_module = require("sqlserver.workspace.activity_stream")
local registry = require("sqlserver.workspace.registry")

local T = MiniTest.new_set()

local function setup_workspace(fetch_rows)
  local activity = {}
  local stream = activity_stream_module.create()
  stream.subscribe(function(_, event)
    table.insert(activity, event)
  end)
  local disposed = {}
  local backend = {
    owner_uri = "file:///query-lifecycle.sql",
    client = {},
    connect_async = function()
      return { connectionSummary = { databaseName = "master" } }
    end,
    disconnect_async = function() end,
    execute_async = function()
      return {
        _sqlserver_query_id = 42,
        ownerUri = "file:///query-lifecycle.sql",
        batchSummaries = {
          {
            hasError = false,
            executionElapsed = "00:00:00.1250000",
            resultSetSummaries = {
              {
                rowCount = 1,
                columnInfo = { { columnName = "Value", dataTypeName = "int" } },
              },
            },
          },
        },
      }
    end,
    fetch_result_rows_async = fetch_rows,
    cancel_async = function() end,
    dispose_query_async = function(query_id)
      table.insert(disposed, query_id)
    end,
  }
  local workspace = workspace_module.create({
    bufnr = 654,
    backend = backend,
    objects = {
      initialise_cache_async = function() end,
      is_refreshing = function()
        return false
      end,
    },
    activity_stream = stream,
  })
  registry.attach(654, workspace)
  workspace.connect_async({ connection = { options = { server = "localhost", database = "master" } } })
  api.configure({ results = { max_rows = 100 } })
  return workspace, activity, disposed, function()
    registry.detach(654)
    workspace.dispose_async()
  end
end

T["Query lifecycle waits for collection and presentation"] = require("tests.helpers").async(function()
  local fetch_coroutine
  local workspace, activity, _, cleanup = setup_workspace(function()
    fetch_coroutine = coroutine.running()
    return coroutine.yield()
  end)
  local presented = 0
  local completed = 0

  api.execute({
    bufnr = 654,
    text = "SELECT 1",
    _present = function(execution)
      presented = presented + 1
      assert(workspace.get_active_operation().phase == "rendering_results")
      assert(execution.result_sets[1].rows[1][1].display_value == "1")
      return true
    end,
  }, function(execution, err)
    assert(not err and not execution.cancelled)
    completed = completed + 1
  end)

  assert(fetch_coroutine and presented == 0 and completed == 0)
  assert(workspace.get_state() == workspace_module.states.executing)
  assert(workspace.get_active_operation().phase == "loading_results")
  assert(activity[#activity].message == "Loading query results")

  assert(coroutine.resume(fetch_coroutine, { { result_cell.create({ display_value = "1" }) } }))
  assert(presented == 1 and completed == 1)
  assert(workspace.get_state() == workspace_module.states.connected)
  assert(workspace.get_active_operation() == nil)
  assert(activity[#activity].message == "Query completed (1 rows)")
  cleanup()
end)

T["Query lifecycle fails without presenting incomplete results"] = require("tests.helpers").async(function()
  local workspace, activity, disposed, cleanup = setup_workspace(function()
    error("row retrieval failed")
  end)
  local presented = false
  local result
  local api_error

  api.execute({
    bufnr = 654,
    text = "SELECT 1",
    _present = function()
      presented = true
    end,
  }, function(value, err)
    result = value
    api_error = err
  end)

  assert(result == nil and api_error.message:find("row retrieval failed", 1, true))
  assert(not presented, "Failed result collection must not invoke presentation")
  assert(workspace.get_state() == workspace_module.states.connected)
  assert(workspace.get_active_operation() == nil)
  assert(activity[#activity].message == "Loading query results failed")
  assert(disposed[1] == 42)
  cleanup()
end)

T["Query lifecycle cancels while loading results"] = require("tests.helpers").async(function()
  local fetch_coroutine
  local workspace, activity, disposed, cleanup = setup_workspace(function()
    fetch_coroutine = coroutine.running()
    return coroutine.yield()
  end)
  local presented = false
  local execution

  api.execute({
    bufnr = 654,
    text = "SELECT 1",
    _present = function()
      presented = true
    end,
  }, function(value, err)
    assert(not err)
    execution = value
  end)
  workspace.cancel_async()
  assert(coroutine.resume(fetch_coroutine, { { result_cell.create({ display_value = "1" }) } }))

  assert(execution and execution.cancelled)
  assert(not presented, "Cancelled result collection must not invoke presentation")
  assert(workspace.get_state() == workspace_module.states.connected)
  assert(activity[#activity].status == "cancelled")
  assert(disposed[1] == 42)
  cleanup()
end)

T["Query lifecycle disposes results after presentation failure"] = require("tests.helpers").async(function()
  local workspace, activity, disposed, cleanup = setup_workspace(function()
    return { { result_cell.create({ display_value = "1" }) } }
  end)
  local result
  local api_error

  api.execute({
    bufnr = 654,
    text = "SELECT 1",
    _present = function()
      assert(workspace.get_active_operation().phase == "rendering_results")
      error("result window failed")
    end,
  }, function(value, err)
    result = value
    api_error = err
  end)

  assert(result == nil and api_error.message:find("result window failed", 1, true))
  assert(workspace.get_state() == workspace_module.states.connected)
  assert(workspace.get_active_operation() == nil)
  assert(activity[#activity].message == "Rendering query results failed")
  assert(#disposed == 1 and disposed[1] == 42)
  cleanup()
end)

return T
