local M = {}
local query_summary = require("sqlserver.queries.summary")
local operations = require("sqlserver.workspace.operations")

M.states = {
  starting = "starting SQL Tools Service",
  disconnected = "disconnected",
  cancelling = "cancelling a query",
  connecting = "connecting",
  connected = "connected",
  executing = "executing a query",
}

---@class SqlServerWorkspace
---@field bufnr integer
---@field owner_uri string

---@param opts { bufnr: integer, backend: table, objects: table, activity_stream?: SqlServerActivityStream, service_pending?: boolean }
---@return SqlServerWorkspace
function M.create(opts)
  local state = opts.service_pending and M.states.starting or M.states.disconnected
  local connect_params
  local last_connect_params
  local backend = opts.backend
  local objects = opts.objects
  local activity = {}
  local disposed = false
  local workspace

  local function emit(event)
    event.time = event.time or os.date("%H:%M:%S")
    table.insert(activity, event)
    if #activity > 200 then
      table.remove(activity, 1)
    end
    if opts.activity_stream then
      opts.activity_stream.publish(workspace, event)
    end
  end

  local operation_manager = operations.create({
    on_error = function(message)
      emit({ kind = "message", message = message, status = "error" })
    end,
  })

  operation_manager.subscribe(function(operation)
    if operation.status == operations.statuses.pending then
      return
    end
    local status = ({
      [operations.statuses.running] = "running",
      [operations.statuses.succeeded] = "success",
      [operations.statuses.failed] = "error",
      [operations.statuses.cancelled] = "cancelled",
    })[operation.status]
    local event = {
      kind = operation.kind,
      title = operation.title,
      message = operation.message,
      status = operation.details and operation.details.activity_status or status,
      operation_id = operation.id,
      phase = operation.phase,
      duration_ms = operation.duration_ms,
    }
    if operation.details then
      event = vim.tbl_extend("force", event, operation.details)
      event.activity_status = nil
    end
    emit(event)
  end)

  local function begin_operation(kind, title, message, phase)
    return operation_manager.start({
      kind = kind,
      title = title,
      message = message,
      phase = phase or kind,
      source_bufnr = opts.bufnr,
    }).id
  end

  local function update_operation(operation_id, message, phase)
    local operation = operation_manager.operation(operation_id)
    if not operation then
      return
    end
    operation.update({ message = message, phase = phase })
  end

  local function finish_operation(operation_id, status, message, details)
    local operation = operation_manager.operation(operation_id)
    if not operation then
      return
    end
    local update = { message = message, details = details }
    if status == "success" then
      operation.succeed(update)
    elseif status == "warning" then
      update.details = vim.tbl_extend("force", details or {}, { activity_status = "warning" })
      operation.succeed(update)
    elseif status == "cancelled" then
      operation.cancel(update)
    else
      operation.fail({ code = operation.snapshot().kind .. "_failed", message = message }, update)
    end
  end

  local function set_state(next_state)
    state = next_state
  end

  workspace = {
    bufnr = opts.bufnr,
    owner_uri = backend.owner_uri,
  }

  local service_operation_id = opts.service_pending
      and begin_operation("service", "SQL Tools Service", "Starting SQL Tools Service")
    or nil

  function workspace.service_ready()
    if not service_operation_id then
      return false
    end
    local operation = operation_manager.operation(service_operation_id)
    service_operation_id = nil
    set_state(M.states.disconnected)
    return operation and operation.succeed({ phase = "ready", message = "SQL Tools Service ready" }) or false
  end

  function workspace.service_failed(message)
    if not service_operation_id then
      return false
    end
    local operation = operation_manager.operation(service_operation_id)
    service_operation_id = nil
    set_state(M.states.disconnected)
    return operation
        and operation.fail(
          { code = "service_startup_failed", message = message },
          { phase = "failed", message = message }
        )
      or false
  end

  function workspace.service_stopped(message)
    if disposed then
      return false
    end
    operation_manager.cancel_all({
      phase = "cancelled",
      message = "Operation cancelled because SQL Tools Service stopped",
    })
    connect_params = nil
    set_state(M.states.disconnected)
    local operation = operation_manager.create_operation({
      kind = "service",
      title = "SQL Tools Service",
      message = message,
      phase = "failed",
      source_bufnr = opts.bufnr,
    })
    return operation.fail({ code = "service_stopped", message = message })
  end

  function workspace.get_state()
    return state
  end

  function workspace.get_active_operation()
    return operation_manager.latest_active()
  end

  function workspace.get_activity()
    return vim.deepcopy(activity)
  end

  function workspace.record_message(message, is_error, error_selection)
    emit({
      kind = "message",
      message = message,
      status = is_error and "error" or "info",
      error_selection = error_selection and vim.deepcopy(error_selection) or nil,
    })
  end

  function workspace.get_connect_params()
    return connect_params and vim.deepcopy(connect_params) or nil
  end

  function workspace.get_connection()
    return connect_params and connect_params.connection and vim.deepcopy(connect_params.connection.options) or nil
  end

  local function complete_connection(operation_id)
    if disposed then
      return false
    end
    local operation = operation_manager.operation(operation_id)
    set_state(M.states.connected)
    return operation and operation.succeed({ phase = "ready", message = "Connected" }) or false
  end

  ---@param params table
  ---@param execution_opts? { defer_completion?: boolean }
  function workspace.connect_async(params, execution_opts)
    if state ~= M.states.disconnected then
      error("You are currently " .. state, 0)
    end
    connect_params = vim.deepcopy(params)
    last_connect_params = vim.deepcopy(params)
    connect_params.ownerUri = backend.owner_uri
    local operation_id = begin_operation("connection", "SQL Server connection", "Connecting")
    set_state(M.states.connecting)
    local ok, result = pcall(backend.connect_async, params)
    if disposed then
      return nil
    end
    if state ~= M.states.connecting then
      pcall(backend.disconnect_async)
      return nil
    end
    if not ok then
      pcall(backend.disconnect_async)
      connect_params = nil
      set_state(M.states.disconnected)
      if type(result) == "table" and result.diagnostic then
        workspace.record_message(result.diagnostic, false)
      end
      finish_operation(
        operation_id,
        "error",
        type(result) == "table" and result.operation_message or "Connection failed"
      )
      error(type(result) == "table" and result.message or result, 0)
    end

    if result and result.connectionSummary then
      local database = result.connectionSummary.databaseName
      connect_params.connection.options.database = database
      connect_params.connection.options.DatabaseDisplayName = database
    end
    local finished = false
    local lifecycle = {}

    function lifecycle.update(phase, message, details)
      if finished or disposed or state ~= M.states.connecting then
        return false
      end
      local operation = operation_manager.operation(operation_id)
      return operation and operation.update({ phase = phase, message = message, details = details }) or false
    end

    function lifecycle.complete()
      if finished then
        return false
      end
      finished = true
      return complete_connection(operation_id)
    end

    function lifecycle.fail(message, err)
      if finished or disposed then
        return false
      end
      finished = true
      pcall(backend.disconnect_async)
      connect_params = nil
      set_state(M.states.disconnected)
      local operation = operation_manager.operation(operation_id)
      return operation
          and operation.fail({ code = "connection_failed", message = message }, {
            phase = "failed",
            message = message,
            details = {
              error = type(err) == "table" and vim.deepcopy(err) or { message = tostring(err) },
            },
          })
        or false
    end

    if execution_opts and execution_opts.defer_completion then
      return result, lifecycle
    end
    lifecycle.complete()
    return result
  end

  function workspace.can_reconnect()
    return last_connect_params ~= nil
  end

  function workspace.reconnect_async(execution_opts)
    if state ~= M.states.disconnected then
      error("You are currently " .. state, 0)
    end
    if not last_connect_params then
      error("No previous SQL Server connection is available", 0)
    end
    return workspace.connect_async(vim.deepcopy(last_connect_params), execution_opts)
  end

  function workspace.disconnect_async()
    if state ~= M.states.connected then
      error("You are currently " .. state, 0)
    end
    local operation_id = begin_operation("connection", "SQL Server connection", "Disconnecting")
    local ok, err = pcall(backend.disconnect_async)
    if not ok then
      finish_operation(operation_id, "error", "Disconnect failed")
      error(err, 0)
    end
    connect_params = nil
    set_state(M.states.disconnected)
    finish_operation(operation_id, "success", "Disconnected")
  end

  function workspace.dispose_query_async(query_id)
    if not (query_id and backend.dispose_query_async) then
      return false
    end
    return backend.dispose_query_async(query_id)
  end

  function workspace.release_query(query_id)
    if not (query_id and backend.dispose_query_async) then
      return false
    end
    local co = coroutine.create(function()
      pcall(workspace.dispose_query_async, query_id)
    end)
    return coroutine.resume(co)
  end

  function workspace.export_result_async(locator, path, format, export_opts)
    return backend.export_result_async(locator, path, format, export_opts)
  end

  function workspace.dispose_async()
    if disposed then
      return
    end
    disposed = true

    if state == M.states.executing then
      pcall(backend.cancel_async)
    end
    if state ~= M.states.starting and backend.dispose_query_async then
      pcall(backend.dispose_query_async)
    end
    if state ~= M.states.disconnected and state ~= M.states.starting then
      pcall(backend.disconnect_async)
    end
    operation_manager.dispose({ phase = "disposed", message = "Operation cancelled" })
    connect_params = nil
    last_connect_params = nil
    set_state(M.states.disconnected)
  end

  local function complete_query(operation_id, result)
    if state == M.states.cancelling then
      if backend.dispose_query_async and result and result._sqlserver_query_id then
        pcall(backend.dispose_query_async, result._sqlserver_query_id)
      end
      set_state(M.states.connected)
      finish_operation(operation_id, "cancelled", "Query cancelled")
      return false
    end

    local summary = query_summary.create(result)
    if summary.has_error and summary.row_count == 0 and backend.is_connected_async then
      local probe_ok, connected = pcall(backend.is_connected_async)
      if not probe_ok or not connected then
        set_state(M.states.disconnected)
        finish_operation(operation_id, "error", "Connection lost", {
          server_duration_ms = summary.server_duration_ms,
        })
        return true
      end
    end
    set_state(M.states.connected)
    if summary.has_error then
      if summary.row_count > 0 then
        finish_operation(
          operation_id,
          "warning",
          string.format("Query completed with errors (%d rows)", summary.row_count),
          { server_duration_ms = summary.server_duration_ms }
        )
      else
        finish_operation(operation_id, "error", "Query failed", { server_duration_ms = summary.server_duration_ms })
      end
    else
      finish_operation(operation_id, "success", string.format("Query completed (%d rows)", summary.row_count), {
        server_duration_ms = summary.server_duration_ms,
      })
    end
    return true
  end

  ---@param request SqlServerQueryRequest
  ---@param execution_opts? { defer_completion?: boolean }
  function workspace.execute_async(request, execution_opts)
    if state ~= M.states.connected then
      error("You are currently " .. state, 0)
    end
    local operation_id = begin_operation("query", "SQL Server query", "Executing query")
    set_state(M.states.executing)
    local ok, result = pcall(backend.execute_async, request)
    if state == M.states.cancelling then
      if backend.dispose_query_async and result and result._sqlserver_query_id then
        pcall(backend.dispose_query_async, result._sqlserver_query_id)
      end
      set_state(M.states.connected)
      finish_operation(operation_id, "cancelled", "Query cancelled")
      return nil
    end
    if not ok then
      set_state(M.states.disconnected)
      if type(result) == "table" and result.diagnostic then
        workspace.record_message(result.diagnostic, false)
      end
      finish_operation(operation_id, "error", type(result) == "table" and result.operation_message or "Connection lost")
      error(type(result) == "table" and result.message or result, 0)
    end
    if not (result and result.batchSummaries) then
      set_state(M.states.connected)
      finish_operation(operation_id, "error", "Query returned no results")
      error("Could not execute query: no results returned", 0)
    end
    local finished = false
    local lifecycle = {}

    function lifecycle.update(phase, message, details)
      if finished or state ~= M.states.executing then
        return false
      end
      local operation = operation_manager.operation(operation_id)
      return operation and operation.update({ phase = phase, message = message, details = details }) or false
    end

    function lifecycle.complete()
      if finished then
        return false
      end
      finished = true
      return complete_query(operation_id, result)
    end

    function lifecycle.fail(message, err)
      if finished then
        return false
      end
      finished = true
      if state == M.states.cancelling then
        return complete_query(operation_id, result)
      end
      set_state(M.states.connected)
      finish_operation(operation_id, "error", message, {
        error = type(err) == "table" and vim.deepcopy(err) or { message = tostring(err) },
      })
      return true
    end

    if execution_opts and execution_opts.defer_completion then
      return result, lifecycle
    end
    lifecycle.complete()
    return result
  end

  function workspace.cancel_async()
    if state ~= M.states.executing then
      error("There is no query being executed in the current buffer", 0)
    end
    set_state(M.states.cancelling)
    local operation = workspace.get_active_operation()
    local operation_id = operation and operation.kind == "query" and operation.id or nil
    update_operation(operation_id, "Cancelling query")
    local ok, err = pcall(backend.cancel_async)
    if not ok then
      finish_operation(operation_id, "error", "Cancellation failed")
      set_state(M.states.connected)
      error(err, 0)
    end
  end

  function workspace.fetch_result_rows_async(locator)
    return backend.fetch_result_rows_async(locator)
  end

  function workspace.connection_changed_async(result)
    if not (result and result.ownerUri == backend.owner_uri and result.connection) then
      return
    end
    connect_params = vim.tbl_deep_extend("force", connect_params or {}, {
      connection = {
        options = {
          user = result.connection.userName,
          database = result.connection.databaseName,
          server = result.connection.serverName,
        },
      },
    })
  end

  function workspace.list_databases_async()
    return backend.list_databases_async()
  end

  function workspace.initialise_objects_async(force, refresh_opts)
    assert(connect_params, "Connect before loading database objects")
    refresh_opts = refresh_opts or {}
    local operation_id
    if not refresh_opts.silent then
      operation_id = begin_operation("metadata", "SQL Server metadata", "Refreshing database objects")
    end
    local ok, result = pcall(objects.initialise_cache_async, backend.client, connect_params.connection.options, force)
    if disposed then
      return { cancelled = true }
    end
    if not ok then
      if operation_id then
        finish_operation(operation_id, "error", "Metadata refresh failed")
      end
      error(result, 0)
    end
    if result and result.cancelled then
      if operation_id then
        finish_operation(operation_id, "cancelled", "Database object refresh cancelled")
      end
      return result
    end
    local message = result and result.count and string.format("Database objects refreshed (%d objects)", result.count)
      or "Database objects refreshed"
    if operation_id then
      finish_operation(operation_id, "success", message)
    end
    return result
  end

  ---@param intent "query"|"definition"
  function workspace.find_object_async(intent)
    assert(connect_params, "Connect before finding database objects")
    local selected, item = pcall(objects.select_async, connect_params.connection.options, intent)
    if disposed then
      return nil
    end
    if not selected then
      error(item, 0)
    end
    if not item then
      return nil
    end

    local operation_id = begin_operation("object", "SQL Server object", "Generating object script", "generating_script")
    local scripted, result = pcall(objects.generate_script_async, item, backend.client, backend.owner_uri, intent)
    if disposed then
      return nil
    end
    if not scripted then
      finish_operation(operation_id, "error", "Object scripting failed")
      error(result, 0)
    end
    finish_operation(operation_id, "success", "Object script ready")
    return result
  end

  function workspace.list_objects(filters)
    assert(connect_params, "Connect before listing database objects")
    return objects.list(connect_params.connection.options, filters)
  end

  function workspace.script_object_async(opts)
    assert(connect_params, "Connect before scripting a database object")
    local operation_id = begin_operation("object", "SQL Server object", "Generating object script", "generating_script")
    local scripted, result =
      pcall(objects.script_async, connect_params.connection.options, backend.client, backend.owner_uri, opts)
    if disposed then
      return nil
    end
    if not scripted then
      finish_operation(operation_id, "error", "Object scripting failed")
      error(result, 0)
    end
    finish_operation(operation_id, "success", "Object script ready")
    return result
  end

  function workspace.is_refreshing()
    return connect_params and objects.is_refreshing(connect_params.connection.options) or false
  end

  function workspace.has_object_cache()
    return connect_params and objects.has_cache(connect_params.connection.options) or false
  end

  function workspace.rebuild_intellisense()
    backend.rebuild_intellisense()
  end

  function workspace.get_backend_client()
    return backend.client
  end

  return workspace
end

return M
