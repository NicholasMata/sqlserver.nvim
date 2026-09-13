local api = require("sqlserver.api")
local workspace_module = require("sqlserver.workspace")
local registry = require("sqlserver.workspace.registry")
local activity_stream_module = require("sqlserver.workspace.activity_stream")

local T = MiniTest.new_set()

local function setup_workspace(bufnr, backend, objects)
  local events = {}
  local stream = activity_stream_module.create()
  stream.subscribe(function(_, event)
    table.insert(events, event)
  end)
  local workspace = workspace_module.create({
    bufnr = bufnr,
    backend = backend,
    objects = objects,
    activity_stream = stream,
  })
  registry.attach(bufnr, workspace)
  api.configure({ connections_file = vim.fn.tempname() })
  return workspace, events
end

local function profile()
  return {
    server = "localhost",
    database = "master",
    authenticationType = "SqlLogin",
    user = "sa",
    password = "secret",
  }
end

T["Connection remains active until initial metadata is ready"] = require("tests.helpers").async(function()
  local metadata_coroutine
  local backend = {
    owner_uri = "file:///connection-lifecycle.sql",
    client = {},
    connect_async = function()
      return { connectionSummary = { databaseName = "ApplicationDb" } }
    end,
    disconnect_async = function() end,
  }
  local objects = {
    initialise_cache_async = function()
      metadata_coroutine = coroutine.running()
      return coroutine.yield()
    end,
    is_refreshing = function()
      return false
    end,
  }
  local workspace, events = setup_workspace(710, backend, objects)
  local callback_count = 0

  api.connect(profile(), { bufnr = 710 }, function(connection, err)
    assert(not err and connection.database == "ApplicationDb")
    callback_count = callback_count + 1
  end)

  assert(metadata_coroutine and callback_count == 0)
  assert(workspace.get_state() == workspace_module.states.connecting)
  local operation = workspace.get_active_operation()
  assert(operation.kind == "connection")
  assert(operation.phase == "loading_metadata")
  assert(operation.message == "Loading database objects")
  assert(coroutine.resume(metadata_coroutine, { count = 12 }))
  assert(callback_count == 1)
  assert(workspace.get_state() == workspace_module.states.connected)
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].message == "Connected" and events[#events].phase == "ready")

  workspace.dispose_async()
  registry.detach(710)
end)

T["SQL Tools Service startup owns the workspace until attachment"] = function()
  local backend = { owner_uri = "file:///service-startup.sql" }
  local objects = {
    is_refreshing = function()
      return false
    end,
  }
  local stream = activity_stream_module.create()
  local events = {}
  stream.subscribe(function(_, event)
    table.insert(events, event)
  end)
  local workspace = workspace_module.create({
    bufnr = 713,
    backend = backend,
    objects = objects,
    activity_stream = stream,
    service_pending = true,
  })
  assert(workspace.get_state() == workspace_module.states.starting)
  assert(workspace.get_active_operation().kind == "service")
  assert(workspace.get_active_operation().message == "Starting SQL Tools Service")
  assert(workspace.service_ready())
  assert(workspace.get_state() == workspace_module.states.disconnected)
  assert(events[#events].status == "success" and events[#events].phase == "ready")
  workspace.dispose_async()
end

T["Metadata failure rolls back a partial connection"] = require("tests.helpers").async(function()
  local disconnect_count = 0
  local backend = {
    owner_uri = "file:///connection-failure.sql",
    client = {},
    connect_async = function()
      return { connectionSummary = { databaseName = "ApplicationDb" } }
    end,
    disconnect_async = function()
      disconnect_count = disconnect_count + 1
    end,
  }
  local objects = {
    initialise_cache_async = function()
      error("metadata transport closed", 0)
    end,
    is_refreshing = function()
      return false
    end,
  }
  local workspace, events = setup_workspace(711, backend, objects)
  local callback_error

  api.connect(profile(), { bufnr = 711 }, function(_, err)
    callback_error = err
  end)

  assert(callback_error and callback_error.message == "metadata transport closed")
  assert(disconnect_count == 1)
  assert(workspace.get_state() == workspace_module.states.disconnected)
  assert(workspace.get_connection() == nil)
  assert(events[#events].status == "error")
  assert(events[#events].message == "Connection initialization failed")
  assert(events[#events].phase == "failed")

  workspace.dispose_async()
  registry.detach(711)
end)

T["Disposed workspaces ignore late connection completion"] = require("tests.helpers").async(function()
  local connect_coroutine
  local backend = {
    owner_uri = "file:///late-connection.sql",
    client = {},
    connect_async = function()
      connect_coroutine = coroutine.running()
      return coroutine.yield()
    end,
    disconnect_async = function() end,
  }
  local objects = {
    initialise_cache_async = function()
      error("Metadata should not load after disposal", 0)
    end,
    is_refreshing = function()
      return false
    end,
  }
  local workspace = setup_workspace(712, backend, objects)
  local callback_count = 0

  api.connect(profile(), { bufnr = 712 }, function()
    callback_count = callback_count + 1
  end)
  assert(connect_coroutine)
  workspace.dispose_async()
  registry.detach(712)
  assert(coroutine.resume(connect_coroutine, { connectionSummary = { databaseName = "late" } }))
  assert(callback_count == 1)
  assert(workspace.get_state() == workspace_module.states.disconnected)
end)

return T
