local utils = require("sqlserver.utils")
local workspace_module = require("sqlserver.workspace")
local workspace_registry = require("sqlserver.workspace.registry")
local query_results = require("sqlserver.results.ui.view")

local M = {}

local function available_commands(handlers)
  return {
    Activity = handlers.toggle_activity,
    ConnectionInfo = handlers.show_connection_info,
    Connect = handlers.connect,
    Reconnect = handlers.reconnect,
    Disconnect = handlers.disconnect,
    BackupDatabase = handlers.backup_database,
    RestoreDatabase = handlers.restore_database,
    ExecuteQuery = handlers.execute_query,
    ExecuteBuffer = handlers.execute_buffer,
    EstimatedPlan = handlers.estimated_plan,
    EstimatedPlanBuffer = handlers.estimated_plan_buffer,
    ActualPlan = handlers.actual_plan,
    ActualPlanBuffer = handlers.actual_plan_buffer,
    ShowPlans = handlers.show_plans,
    SavePlan = handlers.save_plan,
    RefreshCache = handlers.refresh_cache,
    EditConnections = handlers.edit_connections,
    SwitchDatabase = handlers.switch_database,
    NewQuery = handlers.new_query,
    NewDefaultQuery = handlers.new_default_query,
    ExportQueryResults = handlers.export_query_results,
    ShowResults = handlers.show_results,
    ShowQuery = handlers.show_query,
    NextResult = handlers.next_result,
    PreviousResult = handlers.previous_result,
    NextExecution = handlers.next_execution,
    PreviousExecution = handlers.previous_execution,
    RemoveResult = handlers.remove_result,
    CopyResultCell = handlers.copy_result_cell,
    Find = handlers.find_object,
    ObjectDefinition = handlers.show_object_definition,
    ObjectExplorer = handlers.object_explorer,
    CancelOperation = handlers.cancel_operation,
    CancelQuery = handlers.cancel_query,
  }
end

local function get_items()
  local workspace = workspace_registry.get()
  if vim.b.sqlserver_plan_info then
    return {
      "ShowPlans",
      "SavePlan",
      "ShowResults",
      "NextResult",
      "PreviousResult",
      "NextExecution",
      "PreviousExecution",
      "RemoveResult",
    }
  elseif vim.b.query_result_info then
    return {
      "NewQuery",
      "NewDefaultQuery",
      "EditConnections",
      "ExportQueryResults",
      "NextResult",
      "PreviousResult",
      "NextExecution",
      "PreviousExecution",
      "RemoveResult",
      "CopyResultCell",
      "ShowQuery",
      "ShowPlans",
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
    return with_activity({ "NewQuery", "NewDefaultQuery", "EditConnections", "CancelOperation" })
  elseif state == states.connected then
    local items = {
      "ConnectionInfo",
      "NewQuery",
      "NewDefaultQuery",
      "EditConnections",
      "RefreshCache",
      "ExecuteQuery",
      "ExecuteBuffer",
      "EstimatedPlan",
      "EstimatedPlanBuffer",
      "ActualPlan",
      "ActualPlanBuffer",
      "ShowPlans",
      "Disconnect",
      "SwitchDatabase",
      "BackupDatabase",
      "RestoreDatabase",
      "Find",
      "ObjectDefinition",
      "ObjectExplorer",
    }
    if query_results.has_results(workspace.bufnr) then
      table.insert(items, "ShowResults")
    end
    local operation = workspace.get_active_operation()
    if operation and operation.kind == "object" then
      table.insert(items, "CancelOperation")
    end
    return with_activity(items)
  elseif state == states.disconnected then
    local items = { "NewQuery", "NewDefaultQuery", "EditConnections", "Connect" }
    if workspace.can_reconnect() then
      table.insert(items, "Reconnect")
    end
    if query_results.has_results(workspace.bufnr) then
      table.insert(items, "ShowResults")
      table.insert(items, "ShowPlans")
    end
    return with_activity(items)
  elseif state == states.cancelling then
    return with_activity({ "NewQuery", "NewDefaultQuery", "EditConnections" })
  end
  utils.log_error("Entered unrecognised query state: " .. state)
  return {}
end

local function completion_items(arg_lead, _, _)
  local items = get_items()
  if not arg_lead or arg_lead == "" then
    return items
  end

  local matched = {}
  local wordln = #arg_lead
  arg_lead = arg_lead:lower()

  for _, item in ipairs(items) do
    if item:sub(1, wordln):lower() == arg_lead then
      table.insert(matched, item)
    end
  end
  return matched
end

function M.setup(handlers)
  local commands = available_commands(handlers)
  vim.api.nvim_create_user_command("SQLServer", function(args)
    local command = commands[args.args]
    if not command then
      error("No such command " .. args.args, 0)
    end
    if args.range > 0 and (args.args == "EstimatedPlan" or args.args == "ActualPlan") then
      local last_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, false)[1] or ""
      command({
        request = {
          kind = "selection",
          range = {
            startLine = args.line1 - 1,
            startColumn = 0,
            endLine = args.line2 - 1,
            endColumn = vim.str_utfindex(last_line, "utf-16"),
          },
        },
      })
      return
    end
    command()
  end, { nargs = 1, range = true, complete = completion_items })
end

return M
