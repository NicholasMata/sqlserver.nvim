local utils = require("sqlserver.utils")

local M = {}

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

---@param opts { bufnr: integer, backend: table, objects: table }
---@return SqlServerWorkspace
function M.create(opts)
	local state = M.states.disconnected
	local connect_params
	local backend = opts.backend
	local objects = opts.objects

	local function set_state(next_state)
		state = next_state
		vim.cmd("redrawstatus")
	end

	local workspace = {
		bufnr = opts.bufnr,
		owner_uri = backend.owner_uri,
	}

	function workspace.get_state()
		return state
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
		set_state(M.states.connecting)
		local ok, result = pcall(backend.connect_async, params)
		if not ok then
			connect_params = nil
			set_state(M.states.disconnected)
			error(result, 0)
		end

		if result and result.connectionSummary then
			local database = result.connectionSummary.databaseName
			connect_params.connection.options.database = database
			connect_params.connection.options.DatabaseDisplayName = database
		end
		set_state(M.states.connected)
	end

	function workspace.disconnect_async()
		if state ~= M.states.connected then
			error("You are currently " .. state, 0)
		end
		backend.disconnect_async()
		connect_params = nil
		set_state(M.states.disconnected)
	end

	function workspace.execute_async(query)
		if state ~= M.states.connected then
			error("You are currently " .. state, 0)
		end
		set_state(M.states.executing)
		local ok, result = pcall(backend.execute_async, query)
		local was_cancelled = state == M.states.cancelling
		set_state(M.states.connected)
		if not ok then
			error(result, 0)
		end
		if was_cancelled then
			utils.log_info("Query was cancelled.")
			return nil
		end
		if not (result and result.batchSummaries) then
			error("Could not execute query: no results returned", 0)
		end
		return result
	end

	function workspace.cancel_async()
		if state ~= M.states.executing then
			error("There is no query being executed in the current buffer", 0)
		end
		set_state(M.states.cancelling)
		backend.cancel_async()
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
		return objects.initialise_cache_async(backend.client, connect_params.connection.options, force)
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
