local workspace_module = require("sqlserver.core.workspace")
local registry = require("sqlserver.core.workspace_registry")
local activity_stream_module = require("sqlserver.core.activity_stream")

local function create_objects_fake()
  return {
    initialise_cache_async = function() end,
    find_async = function()
      return { script = "SELECT 1", select = true }
    end,
    is_refreshing = function()
      return false
    end,
  }
end

return {
  test_name = "Workspace should own connection and query state",
  run_test_async = function()
    local workspace
    local activity = {}
    local activity_stream = activity_stream_module.create()
    activity_stream.subscribe(function(_, event)
      table.insert(activity, event)
    end)
    local initialized_connection
    local objects = create_objects_fake()
    objects.initialise_cache_async = function(_, connection)
      initialized_connection = vim.deepcopy(connection)
    end
    local backend = {
      owner_uri = "file:///workspace.sql",
      client = {},
      connect_async = function()
        workspace.connection_changed_async({
          ownerUri = "file:///workspace.sql",
          connection = {
            userName = "sa",
            databaseName = "ApplicationDb",
            serverName = "localhost",
          },
        })
        return { connectionSummary = { databaseName = "ApplicationDb" } }
      end,
      disconnect_async = function() end,
      execute_async = function()
        return coroutine.yield()
      end,
      cancel_async = function() end,
      list_databases_async = function()
        return { "ApplicationDb" }
      end,
      rebuild_intellisense = function() end,
    }
    workspace = workspace_module.create({
      bufnr = 99,
      backend = backend,
      objects = objects,
      activity_stream = activity_stream,
    })

    registry.attach(99, workspace)
    assert(registry.get(99) == workspace)
    assert(registry.find_by_owner_uri(backend.owner_uri) == workspace)
    assert(workspace.get_state() == workspace_module.states.disconnected)

    workspace.connect_async({
      connection = {
        options = { server = "localhost", database = "master", trustServerCertificate = true },
      },
    })
    assert(workspace.get_state() == workspace_module.states.connected)
    assert(workspace.get_connection().database == "ApplicationDb")
    assert(initialized_connection.trustServerCertificate == true)
    assert(activity[1].message == "Connecting" and activity[1].status == "running")
    assert(activity[#activity].message == "Connected" and activity[#activity].status == "success")

    objects.initialise_cache_async = function()
      return coroutine.yield()
    end
    local refresh = coroutine.create(function()
      workspace.initialise_objects_async(true)
    end)
    assert(coroutine.resume(refresh))
    assert(workspace.get_active_operation().kind == "metadata")

    local execution = coroutine.create(function()
      local result = workspace.execute_async({ kind = "buffer", text = "WAITFOR DELAY '00:00:01'" })
      assert(result == nil)
    end)
    assert(coroutine.resume(execution))
    assert(workspace.get_state() == workspace_module.states.executing)
    assert(workspace.get_active_operation().message == "Executing query")
    assert(coroutine.resume(refresh))
    assert(workspace.get_active_operation().message == "Executing query")
    workspace.cancel_async()
    assert(workspace.get_state() == workspace_module.states.cancelling)
    assert(workspace.get_active_operation().message == "Cancelling query")
    assert(coroutine.resume(execution, { batchSummaries = {} }))
    assert(workspace.get_state() == workspace_module.states.connected)
    assert(workspace.get_active_operation() == nil)
    assert(activity[#activity].status == "cancelled")

    workspace.record_message("Changed database context", false)
    assert(activity[#activity].kind == "message")
    assert(activity[#activity].message == "Changed database context")

    workspace.disconnect_async()
    assert(workspace.get_state() == workspace_module.states.disconnected)
    assert(workspace.get_connection() == nil)
    assert(workspace.can_reconnect())

    objects.initialise_cache_async = function() end
    workspace.reconnect_async()
    assert(workspace.get_state() == workspace_module.states.connected)

    backend.execute_async = function()
      return { batchSummaries = { { hasError = true, resultSetSummaries = {} } } }
    end
    backend.is_connected_async = function()
      return true
    end
    workspace.execute_async({ kind = "buffer", text = "SELECT invalid" })
    assert(workspace.get_state() == workspace_module.states.connected)
    assert(workspace.get_activity()[#workspace.get_activity()].message == "Query failed")

    backend.is_connected_async = function()
      return false
    end
    workspace.execute_async({ kind = "buffer", text = "SELECT invalid" })
    assert(workspace.get_state() == workspace_module.states.disconnected)
    assert(workspace.get_activity()[#workspace.get_activity()].message == "Connection lost")

    workspace.reconnect_async()
    backend.execute_async = function()
      error("transport closed")
    end
    local execution_ok = pcall(function()
      workspace.execute_async({ kind = "buffer", text = "SELECT 1" })
    end)
    assert(not execution_ok)
    assert(workspace.get_state() == workspace_module.states.disconnected)
    assert(workspace.get_connection().database == "ApplicationDb")
    assert(workspace.get_activity()[#workspace.get_activity()].message == "Connection lost")

    workspace.reconnect_async()
    workspace.disconnect_async()
    assert(#workspace.get_activity() == #activity)
    assert(registry.detach(99) == workspace)
  end,
}
