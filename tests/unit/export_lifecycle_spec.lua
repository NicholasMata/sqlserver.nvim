local api = require("sqlserver.api")
local workspace_module = require("sqlserver.workspace")
local registry = require("sqlserver.workspace.registry")
local activity_stream_module = require("sqlserver.workspace.activity_stream")

local T = MiniTest.new_set()

local function setup_workspace(bufnr, export_async)
  local events = {}
  local stream = activity_stream_module.create()
  stream.subscribe(function(_, event)
    table.insert(events, event)
  end)
  local workspace = workspace_module.create({
    bufnr = bufnr,
    backend = {
      owner_uri = "file:///export-lifecycle.sql",
      client = {},
      connect_async = function()
        return { connectionSummary = { databaseName = "ApplicationDb" } }
      end,
      disconnect_async = function() end,
      export_result_async = export_async,
    },
    objects = {
      is_refreshing = function()
        return false
      end,
    },
    activity_stream = stream,
  })
  registry.attach(bufnr, workspace)
  workspace.connect_async({ connection = { options = { server = "localhost", database = "ApplicationDb" } } })
  api.configure({ timeouts = { export = 1000 } })
  return workspace, events
end

local function export_opts(present)
  return {
    result_set = { locator = { ownerUri = "file:///export-lifecycle.sql" } },
    path = "/tmp/sqlserver-export-lifecycle.csv",
    format = "csv",
    _present = present,
  }
end

T["Export remains active through buffer presentation"] = require("tests.helpers").async(function()
  local export_coroutine
  local workspace, events = setup_workspace(730, function()
    export_coroutine = coroutine.running()
    return coroutine.yield()
  end)
  local presented = false
  local callback_result

  api.export_results(
    export_opts(function(path, format)
      assert(path:match("%.csv$") and format == "csv")
      presented = true
    end),
    function(result, err)
      assert(not err)
      callback_result = result
    end
  )

  assert(export_coroutine and not presented and callback_result == nil)
  local exporting = workspace.get_active_operation()
  assert(exporting.kind == "export" and exporting.phase == "exporting")
  assert(coroutine.resume(export_coroutine))
  assert(presented and callback_result.format == "csv")
  assert(events[#events].status == "success")
  assert(events[#events].phase == "ready" and events[#events].message == "Export ready")

  workspace.dispose_async()
  registry.detach(730)
end)

T["Export presentation failure terminates the operation"] = function()
  local workspace, events = setup_workspace(731, function() end)
  local callback_error
  api.export_results(
    export_opts(function()
      error("buffer creation failed", 0)
    end),
    function(_, err)
      callback_error = err
    end
  )

  assert(callback_error and callback_error.message == "buffer creation failed")
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].status == "error")
  assert(events[#events].message == "Opening export buffer failed")
  workspace.dispose_async()
  registry.detach(731)
end

T["Disposed workspaces suppress late export presentation"] = require("tests.helpers").async(function()
  local export_coroutine
  local workspace = setup_workspace(732, function()
    export_coroutine = coroutine.running()
    return coroutine.yield()
  end)
  local presented = false
  local callback_error
  api.export_results(
    export_opts(function()
      presented = true
    end),
    function(_, err)
      callback_error = err
    end
  )

  workspace.dispose_async()
  registry.detach(732)
  assert(coroutine.resume(export_coroutine))
  assert(not presented)
  assert(callback_error and callback_error.code == "export_cancelled")
end)

T["Removed results cancel late export presentation"] = function()
  local workspace, events = setup_workspace(733, function() end)
  local callback_error
  api.export_results(
    export_opts(function()
      return false
    end),
    function(_, err)
      callback_error = err
    end
  )

  assert(callback_error and callback_error.code == "export_cancelled")
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].status == "cancelled" and events[#events].message == "Export cancelled")
  workspace.dispose_async()
  registry.detach(733)
end

return T
