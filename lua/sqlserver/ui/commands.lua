local utils = require("sqlserver.utils")
local workspace_module = require("sqlserver.workspace")
local workspace_registry = require("sqlserver.workspace.registry")
local query_results = require("sqlserver.results.ui.view")

local M = {}

local function available_commands(handlers)
  return {
    Activity = handlers.toggle_activity,
    Connect = handlers.connect,
    Reconnect = handlers.reconnect,
    Disconnect = handlers.disconnect,
    BackupDatabase = handlers.backup_database,
    RestoreDatabase = handlers.restore_database,
    ExecuteQuery = handlers.execute_query,
    ExecuteBuffer = handlers.execute_buffer,
    RefreshCache = handlers.refresh_cache,
    EditConnections = handlers.edit_connections,
    SwitchDatabase = handlers.switch_database,
    NewQuery = handlers.new_query,
    NewDefaultQuery = handlers.new_default_query,
    SaveQueryResults = handlers.save_query_results,
    ShowResults = handlers.show_results,
    NextResult = handlers.next_result,
    PreviousResult = handlers.previous_result,
    NextExecution = handlers.next_execution,
    PreviousExecution = handlers.previous_execution,
    RemoveResult = handlers.remove_result,
    CopyResultCell = handlers.copy_result_cell,
    Find = handlers.find_object,
    ObjectDefinition = handlers.show_object_definition,
    CancelQuery = handlers.cancel_query,
  }
end

local function completion_items()
  local workspace = workspace_registry.get()
  if vim.b.query_result_info then
    return {
      "NewQuery",
      "NewDefaultQuery",
      "EditConnections",
      "SaveQueryResults",
      "NextResult",
      "PreviousResult",
      "NextExecution",
      "PreviousExecution",
      "RemoveResult",
      "CopyResultCell",
    }
  elseif not workspace then
    local items = { "NewQuery", "NewDefaultQuery", "EditConnections" }
    if query_results.has_results() then
      table.insert(items, "ShowResults")
    end
    return items
  end

  local state = workspace.get_state()
  local states = workspace_module.states
  local function with_activity(items)
    table.insert(items, 1, "Activity")
    return items
  end
  if state == states.connecting then
    return with_activity({ "NewQuery", "NewDefaultQuery", "EditConnections" })
  elseif state == states.executing then
    return with_activity({ "NewQuery", "NewDefaultQuery", "EditConnections", "CancelQuery" })
  elseif state == states.connected then
    local items = {
      "NewQuery",
      "NewDefaultQuery",
      "EditConnections",
      "RefreshCache",
      "ExecuteQuery",
      "ExecuteBuffer",
      "Disconnect",
      "SwitchDatabase",
      "BackupDatabase",
      "RestoreDatabase",
      "Find",
      "ObjectDefinition",
    }
    if query_results.has_results(workspace.bufnr) then
      table.insert(items, "ShowResults")
    end
    return with_activity(items)
  elseif state == states.disconnected then
    local items = { "NewQuery", "NewDefaultQuery", "EditConnections", "Connect" }
    if workspace.can_reconnect() then
      table.insert(items, "Reconnect")
    end
    if query_results.has_results(workspace.bufnr) then
      table.insert(items, "ShowResults")
    end
    return with_activity(items)
  elseif state == states.cancelling then
    return with_activity({ "NewQuery", "NewDefaultQuery", "EditConnections" })
  end
  utils.log_error("Entered unrecognised query state: " .. state)
  return {}
end

function M.setup(handlers)
  local commands = available_commands(handlers)
  vim.api.nvim_create_user_command("SQLServer", function(args)
    local command = commands[args.args]
    if not command then
      error("No such command " .. args.args, 0)
    end
    command()
  end, { nargs = 1, complete = completion_items })
end

return M
