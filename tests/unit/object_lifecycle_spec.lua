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

return T
