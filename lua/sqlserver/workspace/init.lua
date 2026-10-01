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
  local connection_info
  local backend = opts.backend
  local objects = opts.objects
  local activity = {}
  local disposed = false
  local explorer_sessions = {}
  local active_object_script
  local agent_backend = opts.agent
  local agent_timeout = opts.agent_timeout == nil and 10000 or opts.agent_timeout
  local agent_slots = {}
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
      event.message = operation.details.activity_message or event.message
      event.activity_status = nil
      event.activity_message = nil
    end
    emit(event)
  end)

  local function begin_operation(kind, title, message, phase, details)
    return operation_manager.start({
      kind = kind,
      title = title,
      message = message,
      phase = phase or kind,
      source_bufnr = opts.bufnr,
      details = details,
    }).id
  end

  local function update_operation(operation_id, message, phase, details)
    local operation = operation_manager.operation(operation_id)
    if not operation then
      return
    end
    operation.update({ message = message, phase = phase, details = details })
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

  local cancel_agent_requests
  local function set_state(next_state)
    if next_state == M.states.disconnected then
      cancel_agent_requests(true)
    end
    state = next_state
  end

  local function agent_slot(kind)
    if not agent_slots[kind] then
      agent_slots[kind] = { status = "idle", data = nil, error = nil, loading = false, generation = 0 }
    end
    return agent_slots[kind]
  end

  local function cancel_agent_slot(slot)
    slot.generation = slot.generation + 1
    local request = slot.request
    slot.request = nil
    slot.loading = false
    if request then
      local operation = operation_manager.operation(request.operation_id)
      if operation then
        operation.cancel({ phase = "cancelled", message = "SQL Agent request cancelled" })
      end
      if request.control.cancel then
        request.control.cancel()
      end
    end
    if slot.status == "loading" then
      slot.status = slot.data and "ready" or "idle"
    end
  end

  cancel_agent_requests = function(clear)
    for _, slot in pairs(agent_slots) do
      cancel_agent_slot(slot)
      if clear then
        slot.data = nil
        slot.error = nil
        slot.status = "idle"
        slot.job = nil
      end
    end
  end

  local function object_script_control(operation_id)
    local control = {}
    function control.on_operation(protocol_operation_id, cancel)
      active_object_script = {
        operation_id = operation_id,
        protocol_operation_id = protocol_operation_id,
        cancel = cancel,
      }
    end
    function control.on_progress(progress)
      if
        not active_object_script
        or active_object_script.operation_id ~= operation_id
        or active_object_script.cancel_requested
      then
        return
      end
      local completed = tonumber(progress.completedCount)
      local total = tonumber(progress.totalCount or progress.count)
      local message = "Generating object script"
      if completed and total and total > 0 then
        message = string.format("Generating object script (%d/%d)", completed, total)
      elseif total and total > 0 then
        message = string.format("Preparing object script (%d objects)", total)
      end
      update_operation(operation_id, message, "generating_script", {
        completed_count = completed,
        total_count = total,
        scripting_status = progress.status,
      })
    end
    return control
  end

  local function finish_object_script(operation_id, scripted, result)
    if active_object_script and active_object_script.operation_id == operation_id then
      active_object_script = nil
    end
    if not scripted then
      if type(result) == "table" and result.code == "cancelled" then
        finish_operation(operation_id, "cancelled", result.message or "Object scripting cancelled")
        return nil, true
      end
      finish_operation(operation_id, "error", "Object scripting failed")
      error(result, 0)
    end
    finish_operation(operation_id, "success", "Object script ready")
    return result, false
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
    cancel_agent_requests(true)
    operation_manager.cancel_all({
      phase = "cancelled",
      message = "Operation cancelled because SQL Tools Service stopped",
    })
    connect_params = nil
    connection_info = nil
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

  function workspace.get_connection_info()
    return connection_info and vim.deepcopy(connection_info) or nil
  end

  function workspace.set_agent_backend(value, timeout)
    agent_backend = value
    if timeout ~= nil then
      assert(timeout == false or (type(timeout) == "number" and timeout > 0), "Invalid SQL Agent timeout")
      agent_timeout = timeout
    end
  end

  function workspace.get_agent_state(kind)
    assert(kind == "jobs" or kind == "details" or kind == "alerts", "Unknown SQL Agent state")
    local slot = agent_slot(kind)
    return vim.deepcopy({
      status = slot.status,
      data = slot.data,
      error = slot.error,
      loading = slot.loading,
      job = slot.job,
    })
  end

  function workspace.cancel_agent_request(kind)
    assert(kind == "jobs" or kind == "details" or kind == "alerts", "Unknown SQL Agent request")
    cancel_agent_slot(agent_slot(kind))
  end

  function workspace.close_agent_view(kind)
    workspace.cancel_agent_request(kind)
    agent_slots[kind] = nil
  end

  local function run_agent_request(kind, job)
    local slot = agent_slot(kind)
    cancel_agent_slot(slot)
    if state ~= M.states.connected or not agent_backend then
      local err = { code = "agent_not_connected", message = "Connect to SQL Server before inspecting SQL Agent" }
      slot.error = err
      slot.status = "error"
      return nil, vim.deepcopy(err)
    end
    if kind == "details" then
      if not (type(job) == "table" and type(job.id) == "string" and type(job.name) == "string") then
        local err = { code = "agent_invalid_job", message = "Select a SQL Agent job before loading its details" }
        slot.error = err
        slot.status = "error"
        return nil, vim.deepcopy(err)
      end
      if not slot.job or slot.job.id ~= job.id then
        slot.data = nil
      end
      slot.job = { id = job.id, name = job.name }
    end
    local generation = slot.generation
    local labels = { jobs = "jobs", details = "job details", alerts = "alerts" }
    local label = labels[kind]
    local operation_id =
      begin_operation("agent", "SQL Agent " .. label, "Loading SQL Agent " .. label, "loading_" .. kind)
    local control = {}
    slot.request = { operation_id = operation_id, control = control }
    slot.loading = true
    slot.status = "loading"
    slot.error = nil
    local method = ({ jobs = "list_jobs_async", details = "get_job_details_async", alerts = "list_alerts_async" })[kind]
    local ok, result
    if kind == "details" then
      ok, result = pcall(agent_backend[method], job, control, agent_timeout)
    else
      ok, result = pcall(agent_backend[method], control, agent_timeout)
    end
    if disposed or slot.generation ~= generation or state == M.states.disconnected then
      return nil
    end
    slot.request = nil
    slot.loading = false
    local operation = operation_manager.operation(operation_id)
    if not ok or type(result) ~= "table" then
      local err = not ok
          and type(result) == "table"
          and result.code
          and result.message
          and { code = result.code, message = result.message }
        or { code = "agent_request_failed", message = "Could not load SQL Agent " .. label }
      slot.error = err
      slot.status = slot.data and "ready" or "error"
      operation.fail(err, { phase = "failed", message = err.message })
      return nil, vim.deepcopy(err)
    end
    slot.data = vim.deepcopy(result)
    slot.status = kind ~= "details" and #result == 0 and "empty" or "ready"
    operation.succeed({ phase = "ready", message = "SQL Agent " .. label .. " loaded" })
    return vim.deepcopy(slot.data)
  end

  function workspace.list_agent_jobs_async()
    return run_agent_request("jobs")
  end

  function workspace.get_agent_job_details_async(job)
    return run_agent_request("details", job)
  end

  function workspace.list_agent_alerts_async()
    return run_agent_request("alerts")
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
    connection_info = nil
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
      local summary = result.connectionSummary
      if summary.databaseName ~= nil then
        connect_params.connection.options.database = summary.databaseName
        connect_params.connection.options.DatabaseDisplayName = summary.databaseName
      end
      if summary.serverName ~= nil then
        connect_params.connection.options.server = summary.serverName
      end
      if summary.userName ~= nil then
        connect_params.connection.options.user = summary.userName
        connect_params.connection.options.username = summary.userName
      end
    end
    if result then
      local summary = result.connectionSummary or {}
      local server = result.serverInfo or {}
      connection_info = {
        username = summary.userName,
        server = summary.serverName,
        database = summary.databaseName,
        connection_id = result.connectionId,
        server_connection_id = result.serverConnectionId,
        is_supported_version = result.isSupportedVersion,
        type = result.type,
        server_info = {
          version = server.serverVersion,
          major_version = server.serverMajorVersion,
          minor_version = server.serverMinorVersion,
          release_version = server.serverReleaseVersion,
          level = server.serverLevel,
          edition = server.serverEdition,
          engine_edition_id = server.engineEditionId,
          is_cloud = server.isCloud,
          azure_version = server.azureVersion,
          os_version = server.osVersion,
          machine_name = server.machineName,
          cpu_count = server.cpuCount,
          physical_memory_mb = server.physicalMemoryInMB,
          options = server.options,
        },
      }
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
      connection_info = nil
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
    cancel_agent_requests(true)
    local operation_id = begin_operation("connection", "SQL Server connection", "Disconnecting")
    local ok, err = pcall(backend.disconnect_async)
    if not ok then
      finish_operation(operation_id, "error", "Disconnect failed")
      error(err, 0)
    end
    connect_params = nil
    connection_info = nil
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
    export_opts = export_opts or {}
    local operation_id = begin_operation("export", "SQL Server export", "Exporting query results", "exporting")
    local backend_opts = vim.deepcopy(export_opts)
    backend_opts.defer_completion = nil
    local ok, result = pcall(backend.export_result_async, locator, path, format, backend_opts)
    if disposed then
      return nil, false
    end
    if not ok then
      finish_operation(operation_id, "error", "Export failed", {
        error = type(result) == "table" and vim.deepcopy(result) or { message = tostring(result) },
      })
      error(result, 0)
    end

    local finished = false
    local lifecycle = {}
    function lifecycle.update(phase, message)
      if finished or disposed then
        return false
      end
      local operation = operation_manager.operation(operation_id)
      return operation and operation.update({ phase = phase, message = message }) or false
    end
    function lifecycle.complete()
      if finished or disposed then
        return false
      end
      finished = true
      local operation = operation_manager.operation(operation_id)
      return operation and operation.succeed({ phase = "ready", message = "Export ready" }) or false
    end
    function lifecycle.fail(message, err)
      if finished or disposed then
        return false
      end
      finished = true
      local operation = operation_manager.operation(operation_id)
      return operation
          and operation.fail({ code = "export_failed", message = message }, {
            phase = "failed",
            message = message,
            details = {
              error = type(err) == "table" and vim.deepcopy(err) or { message = tostring(err) },
            },
          })
        or false
    end
    function lifecycle.cancel(message)
      if finished or disposed then
        return false
      end
      finished = true
      local operation = operation_manager.operation(operation_id)
      return operation and operation.cancel({ phase = "cancelled", message = message or "Export cancelled" }) or false
    end

    if export_opts.defer_completion then
      return result, lifecycle
    end
    if not lifecycle.complete() then
      return result, false
    end
    return result
  end

  function workspace.dispose_async()
    if disposed then
      return
    end
    disposed = true
    cancel_agent_requests(true)

    if active_object_script then
      pcall(active_object_script.cancel)
      active_object_script = nil
    end

    for session in pairs(explorer_sessions) do
      session.close()
    end
    explorer_sessions = {}

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
    connection_info = nil
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
        connection_info = nil
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
      connection_info = nil
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
    if state == M.states.executing then
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
      return
    end

    if active_object_script then
      active_object_script.cancel_requested = true
      update_operation(active_object_script.operation_id, "Cancelling object script", "cancelling_script")
      local ok, requested = pcall(active_object_script.cancel)
      if not ok or requested == false then
        finish_operation(active_object_script.operation_id, "error", "Object script cancellation failed")
        active_object_script = nil
        error(ok and "SQL Tools Service rejected object script cancellation" or requested, 0)
      end
      return
    end

    error("There is no cancellable operation in the current buffer", 0)
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
          username = result.connection.userName,
          database = result.connection.databaseName,
          server = result.connection.serverName,
        },
      },
    })
    connection_info = vim.tbl_deep_extend("force", connection_info or {}, {
      username = result.connection.userName,
      database = result.connection.databaseName,
      server = result.connection.serverName,
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
    local scripted, result = pcall(
      objects.generate_script_async,
      item,
      backend.client,
      backend.owner_uri,
      intent,
      object_script_control(operation_id)
    )
    if disposed then
      return nil
    end
    return (finish_object_script(operation_id, scripted, result))
  end

  function workspace.list_objects(filters)
    assert(connect_params, "Connect before listing database objects")
    return objects.list(connect_params.connection.options, filters)
  end

  function workspace.list_object_children_async(object)
    assert(connect_params, "Connect before expanding a database object")
    local operation_id = begin_operation(
      "metadata",
      "SQL Server Object Explorer",
      "Loading database object details",
      "loading_object_details"
    )
    local loaded, result =
      pcall(objects.list_children_async, backend.client, connect_params.connection.options, object.id)
    if disposed then
      return nil
    end
    if not loaded then
      finish_operation(operation_id, "error", "Database object details failed", {
        object_id = object.id,
      })
      error(result, 0)
    end
    finish_operation(operation_id, "success", "Database object details loaded", {
      object_id = object.id,
      node_count = #result,
    })
    return result
  end

  function workspace.open_object_explorer_async()
    assert(connect_params, "Connect before opening Object Explorer")
    local operation_id =
      begin_operation("metadata", "SQL Server Object Explorer", "Loading Object Explorer", "loading_object_explorer")
    local opened, session, root = pcall(objects.open_explorer_async, backend.client, connect_params.connection.options)
    if disposed then
      if opened and session then
        session.close()
      end
      return nil
    end
    if not opened then
      finish_operation(operation_id, "error", "Object Explorer failed")
      error(session, 0)
    end
    explorer_sessions[session] = true
    finish_operation(operation_id, "success", "Object Explorer ready")
    return session, root
  end

  function workspace.close_object_explorer_session(session)
    if not explorer_sessions[session] then
      return false
    end
    explorer_sessions[session] = nil
    return session.close()
  end

  function workspace.expand_object_explorer_async(session, node_path, refresh, node_label, activity_path)
    if not explorer_sessions[session] then
      error("Object Explorer session is not active", 0)
    end
    local display_name = node_label or node_path:match("[^/]+$") or node_path
    local display_path = activity_path or display_name
    local operation_id = begin_operation(
      "metadata",
      "SQL Server Object Explorer",
      refresh and "Refreshing database object" or "Loading database object",
      refresh and "refreshing_object" or "loading_object",
      {
        activity_message = display_path .. (refresh and " · Refreshing" or " · Loading"),
        node_path = node_path,
        node_label = display_name,
      }
    )
    local expanded, result = pcall(session.expand_async, node_path, refresh)
    if not expanded then
      finish_operation(
        operation_id,
        "error",
        refresh and "Database object refresh failed" or "Database object load failed",
        {
          activity_message = display_path .. (refresh and " · Refresh failed" or " · Load failed"),
          node_path = node_path,
          node_label = display_name,
        }
      )
      error(result, 0)
    end
    finish_operation(operation_id, "success", refresh and "Database object refreshed" or "Database object loaded", {
      activity_message = display_path .. (refresh and " · Refreshed" or " · Loaded"),
      node_path = node_path,
      node_label = display_name,
      node_count = #result,
    })
    return result
  end

  function workspace.script_object_async(opts)
    assert(connect_params, "Connect before scripting a database object")
    local operation_id = begin_operation("object", "SQL Server object", "Generating object script", "generating_script")
    local scripted, result = pcall(
      objects.script_async,
      connect_params.connection.options,
      backend.client,
      backend.owner_uri,
      opts,
      object_script_control(operation_id)
    )
    if disposed then
      return nil
    end
    return (finish_object_script(operation_id, scripted, result))
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
