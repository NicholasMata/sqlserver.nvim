local workspace_module = require("sqlserver.workspace")
local activity_stream_module = require("sqlserver.workspace.activity_stream")

local T = MiniTest.new_set()

local function create_workspace(objects)
  local events = {}
  local stream = activity_stream_module.create()
  stream.subscribe(function(_, event)
    table.insert(events, event)
  end)
  local workspace = workspace_module.create({
    bufnr = 720,
    backend = {
      owner_uri = "file:///objects.sql",
      client = {},
      connect_async = function()
        return { connectionSummary = { databaseName = "ApplicationDb" } }
      end,
      disconnect_async = function() end,
    },
    objects = objects,
    activity_stream = stream,
  })
  workspace.connect_async({ connection = { options = { server = "localhost", database = "ApplicationDb" } } })
  return workspace, events
end

T["Object scripting starts after interactive selection"] = require("tests.helpers").async(function()
  local selection_coroutine
  local scripting_coroutine
  local selected_item = { objectType = "Table" }
  local workspace, events = create_workspace({
    select_async = function()
      selection_coroutine = coroutine.running()
      return coroutine.yield()
    end,
    generate_script_async = function(item)
      assert(item == selected_item)
      scripting_coroutine = coroutine.running()
      return coroutine.yield()
    end,
    is_refreshing = function()
      return false
    end,
  })
  local result
  local workflow = coroutine.create(function()
    result = workspace.find_object_async("definition")
  end)

  assert(coroutine.resume(workflow))
  assert(workspace.get_active_operation() == nil, "Waiting for user selection must not start a timer")
  assert(coroutine.resume(selection_coroutine, selected_item))
  local scripting = workspace.get_active_operation()
  assert(scripting.kind == "object" and scripting.phase == "generating_script")
  assert(scripting.message == "Generating object script")
  assert(coroutine.resume(scripting_coroutine, { script = "CREATE TABLE dbo.Person (ID int)" }))
  assert(result.script:find("CREATE TABLE", 1, true))
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].status == "success" and events[#events].message == "Object script ready")

  workspace.dispose_async()
end)

T["Closing the object picker does not create an operation"] = function()
  local workspace, events = create_workspace({
    select_async = function()
      return nil
    end,
    is_refreshing = function()
      return false
    end,
  })

  assert(workspace.find_object_async("query") == nil)
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].kind == "connection")
  workspace.dispose_async()
end

T["Object scripting failures terminate their operation"] = function()
  local workspace, events = create_workspace({
    script_async = function()
      error("scripting unavailable", 0)
    end,
    is_refreshing = function()
      return false
    end,
  })

  local ok, err = pcall(workspace.script_object_async, { id = "table-1", intent = "definition" })
  assert(not ok and err == "scripting unavailable")
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].status == "error" and events[#events].message == "Object scripting failed")
  workspace.dispose_async()
end

T["Object scripting cancellation owns the protocol operation"] = require("tests.helpers").async(function()
  local scripting_coroutine
  local cancellation_requests = 0
  local workspace, events = create_workspace({
    script_async = function(_, _, _, _, control)
      control.on_operation("script-42", function()
        cancellation_requests = cancellation_requests + 1
        return true
      end)
      control.on_progress({
        operationId = "script-42",
        completedCount = 1,
        totalCount = 3,
        status = "Progress",
      })
      scripting_coroutine = coroutine.running()
      coroutine.yield()
      error({ code = "cancelled", message = "Object scripting cancelled" }, 0)
    end,
    is_refreshing = function()
      return false
    end,
  })
  local result
  local workflow = coroutine.create(function()
    result = workspace.script_object_async({ id = "table-1", intent = "definition" })
  end)

  assert(coroutine.resume(workflow))
  local operation = workspace.get_active_operation()
  assert(operation.message == "Generating object script (1/3)")
  assert(operation.details.completed_count == 1 and operation.details.total_count == 3)
  workspace.cancel_async()
  assert(cancellation_requests == 1)
  assert(workspace.get_active_operation().phase == "cancelling_script")
  assert(coroutine.resume(scripting_coroutine))
  assert(result == nil and workspace.get_active_operation() == nil)
  assert(events[#events].status == "cancelled")
  assert(events[#events].message == "Object scripting cancelled")
  workspace.dispose_async()
end)

T["Workspace disposal cancels SQL Tools Service object scripting"] = require("tests.helpers").async(function()
  local scripting_coroutine
  local cancellation_requests = 0
  local workspace = create_workspace({
    script_async = function(_, _, _, _, control)
      control.on_operation("dispose-script", function()
        cancellation_requests = cancellation_requests + 1
        return true
      end)
      scripting_coroutine = coroutine.running()
      return coroutine.yield()
    end,
    is_refreshing = function()
      return false
    end,
  })
  local workflow = coroutine.create(function()
    workspace.script_object_async({ id = "table-1", intent = "definition" })
  end)

  assert(coroutine.resume(workflow))
  workspace.dispose_async()
  assert(cancellation_requests == 1)
  assert(coroutine.resume(scripting_coroutine, { script = "CREATE TABLE dbo.Person (ID int)" }))
end)

T["Object Explorer child loading uses the shared operation lifecycle"] = function()
  local expected = { { id = "column-1", name = "ID" } }
  local workspace, events = create_workspace({
    list_children_async = function(client, connection, object_id)
      assert(type(client) == "table")
      assert(connection.database == "ApplicationDb")
      assert(object_id == "table-1")
      return expected
    end,
    is_refreshing = function()
      return false
    end,
  })

  assert(workspace.list_object_children_async({ id = "table-1" }) == expected)
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].kind == "metadata")
  assert(events[#events].title == "SQL Server Object Explorer")
  assert(events[#events].phase == "loading_object_details")
  assert(events[#events].status == "success")
  assert(events[#events].message == "Database object details loaded")
  assert(events[#events].object_id == "table-1")
  assert(events[#events].node_count == 1)
  workspace.dispose_async()
end

T["Object Explorer child loading failures terminate their operation"] = function()
  local workspace, events = create_workspace({
    list_children_async = function()
      error("object expansion unavailable", 0)
    end,
    is_refreshing = function()
      return false
    end,
  })

  local ok, err = pcall(workspace.list_object_children_async, { id = "table-1" })
  assert(not ok and err == "object expansion unavailable")
  assert(workspace.get_active_operation() == nil)
  assert(events[#events].kind == "metadata")
  assert(events[#events].title == "SQL Server Object Explorer")
  assert(events[#events].status == "error")
  assert(events[#events].message == "Database object details failed")
  assert(events[#events].object_id == "table-1")
  workspace.dispose_async()
end

T["Workspace disposal cancels an active Object Explorer load"] = require("tests.helpers").async(function()
  local loading_coroutine
  local workspace, events = create_workspace({
    list_children_async = function()
      loading_coroutine = coroutine.running()
      return coroutine.yield()
    end,
    is_refreshing = function()
      return false
    end,
  })
  local workflow = coroutine.create(function()
    workspace.list_object_children_async({ id = "table-1" })
  end)

  assert(coroutine.resume(workflow))
  assert(workspace.get_active_operation().title == "SQL Server Object Explorer")
  workspace.dispose_async()
  assert(events[#events].status == "cancelled")
  assert(events[#events].phase == "disposed")
  assert(coroutine.resume(loading_coroutine, {}))
end)

T["Object Explorer expansion activity identifies its node"] = require("tests.helpers").async(function()
  local expansion_coroutine
  local session = {
    expand_async = function(node_path)
      assert(node_path == "database/Tables")
      expansion_coroutine = coroutine.running()
      return coroutine.yield()
    end,
    close = function() end,
  }
  local workspace, events = create_workspace({
    open_explorer_async = function()
      return session, { nodePath = "database", label = "ApplicationDb" }
    end,
    is_refreshing = function()
      return false
    end,
  })
  workspace.open_object_explorer_async()

  local result
  local workflow = coroutine.create(function()
    result =
      workspace.expand_object_explorer_async(session, "database/Tables", false, "Tables", "ApplicationDb › Tables")
  end)
  assert(coroutine.resume(workflow))
  assert(workspace.get_active_operation().message == "Loading database object")
  assert(events[#events].message == "ApplicationDb › Tables · Loading")
  assert(coroutine.resume(expansion_coroutine, { { nodePath = "database/Tables/dbo.Person" } }))
  assert(#result == 1)
  assert(events[#events].message == "ApplicationDb › Tables · Loaded")
  assert(events[#events].node_path == "database/Tables")
  assert(events[#events].node_label == "Tables")

  workspace.dispose_async()
end)

return T
