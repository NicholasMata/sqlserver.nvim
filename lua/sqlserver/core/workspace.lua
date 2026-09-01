local M = {}
local uv = vim.uv or vim.loop

M.states = {
	disconnected = "disconnected",
	cancelling = "cancelling a query",
	connecting = "connecting",
	connected = "connected",
	executing = "executing a query",
}

---@class SqlServerWorkspace
---@field bufnr integer
---@field owner_uri string

---@param opts { bufnr: integer, backend: table, objects: table, activity_stream?: SqlServerActivityStream }
---@return SqlServerWorkspace
function M.create(opts)
	local state = M.states.disconnected
	local connect_params
	local backend = opts.backend
	local objects = opts.objects
	local activity = {}
	local active_operations = {}
	local next_operation_id = 0
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

	local function begin_operation(kind, title, message)
		next_operation_id = next_operation_id + 1
		local operation = {
			id = next_operation_id,
			kind = kind,
			title = title,
			message = message,
			started_at_ns = uv.hrtime(),
		}
		active_operations[operation.id] = operation
		emit({
			kind = kind,
			title = title,
			message = message,
			status = "running",
			operation_id = operation.id,
		})
		return operation.id
	end

	local function update_operation(operation_id, message)
		local operation = active_operations[operation_id]
		if not operation then
			return
		end
		operation.message = message
		emit({
			kind = operation.kind,
			title = operation.title,
			message = message,
			status = "running",
			operation_id = operation.id,
		})
	end

	local function finish_operation(operation_id, status, message)
		local operation = active_operations[operation_id]
		if not operation then
			return
		end
		active_operations[operation_id] = nil
		emit({
			kind = operation.kind,
			title = operation.title,
			message = message,
			status = status,
			operation_id = operation.id,
			duration_ms = (uv.hrtime() - operation.started_at_ns) / 1e6,
		})
	end

	local function set_state(next_state)
		state = next_state
	end

	workspace = {
		bufnr = opts.bufnr,
		owner_uri = backend.owner_uri,
	}

	function workspace.get_state()
		return state
	end

	function workspace.get_active_operation()
		local latest
		for _, operation in pairs(active_operations) do
			if not latest or operation.id > latest.id then
				latest = operation
			end
		end
		return latest and vim.deepcopy(latest) or nil
	end

	function workspace.get_activity()
		return vim.deepcopy(activity)
	end

	function workspace.record_message(message, is_error)
		emit({
			kind = "message",
			message = message,
			status = is_error and "error" or "info",
		})
	end

	function workspace.get_connect_params()
		return connect_params and vim.deepcopy(connect_params) or nil
	end

	function workspace.get_connection()
		return connect_params and connect_params.connection and vim.deepcopy(connect_params.connection.options) or nil
	end

	function workspace.connect_async(params)
		if state ~= M.states.disconnected then
			error("You are currently " .. state, 0)
		end
		connect_params = vim.deepcopy(params)
		connect_params.ownerUri = backend.owner_uri
		local operation_id = begin_operation("connection", "SQL Server connection", "Connecting")
		set_state(M.states.connecting)
		local ok, result = pcall(backend.connect_async, params)
		if not ok then
			connect_params = nil
			set_state(M.states.disconnected)
			finish_operation(operation_id, "error", "Connection failed")
			error(result, 0)
		end

		if result and result.connectionSummary then
			local database = result.connectionSummary.databaseName
			connect_params.connection.options.database = database
			connect_params.connection.options.DatabaseDisplayName = database
		end
		set_state(M.states.connected)
		finish_operation(operation_id, "success", "Connected")
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

	function workspace.execute_async(query)
		if state ~= M.states.connected then
			error("You are currently " .. state, 0)
		end
		local operation_id = begin_operation("query", "SQL Server query", "Executing query")
		set_state(M.states.executing)
		local ok, result = pcall(backend.execute_async, query)
		local was_cancelled = state == M.states.cancelling
		set_state(M.states.connected)
		if not ok then
			finish_operation(operation_id, "error", "Query failed")
			error(result, 0)
		end
		if was_cancelled then
			finish_operation(operation_id, "cancelled", "Query cancelled")
			return nil
		end
		if not (result and result.batchSummaries) then
			finish_operation(operation_id, "error", "Query returned no results")
			error("Could not execute query: no results returned", 0)
		end
		local rows = vim.iter(result.batchSummaries):fold(0, function(total, batch)
			return total
				+ vim.iter(batch.resultSetSummaries or {}):fold(0, function(batch_total, result_set)
					return batch_total + (result_set.rowCount or 0)
				end)
		end)
		finish_operation(operation_id, "success", string.format("Query completed (%d rows)", rows))
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
		objects.initialise_cache_async(backend.client, connect_params.connection.options)
	end

	function workspace.list_databases_async()
		return backend.list_databases_async()
	end

	function workspace.initialise_objects_async(force)
		assert(connect_params, "Connect before loading database objects")
		if objects.is_refreshing(connect_params.connection.options) and not force then
			return
		end
		local operation_id = begin_operation("metadata", "SQL Server metadata", "Refreshing database objects")
		local ok, result =
			pcall(objects.initialise_cache_async, backend.client, connect_params.connection.options, force)
		if not ok then
			finish_operation(operation_id, "error", "Metadata refresh failed")
			error(result, 0)
		end
		finish_operation(operation_id, "success", "Database objects refreshed")
		return result
	end

	function workspace.find_object_async()
		assert(connect_params, "Connect before finding database objects")
		return objects.find_async(connect_params.connection.options, backend.client)
	end

	function workspace.is_refreshing()
		return connect_params and objects.is_refreshing(connect_params.connection.options) or false
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
