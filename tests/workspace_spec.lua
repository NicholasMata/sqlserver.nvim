local workspace_module = require("sqlserver.core.workspace")
local registry = require("sqlserver.core.workspace_registry")

local function create_objects_fake()
	return {
		initialise_cache_async = function() end,
		find_async = function()
			return { script = "SELECT 1", select = true }
		end,
		is_refreshing = function()
			return false
		end,
	}
end

return {
	test_name = "Workspace should own connection and query state",
	run_test_async = function()
		local workspace
		local initialized_connection
		local objects = create_objects_fake()
		objects.initialise_cache_async = function(_, connection)
			initialized_connection = vim.deepcopy(connection)
		end
		local backend = {
			owner_uri = "file:///workspace.sql",
			client = {},
			connect_async = function()
				workspace.connection_changed_async({
					ownerUri = "file:///workspace.sql",
					connection = {
						userName = "sa",
						databaseName = "ApplicationDb",
						serverName = "localhost",
					},
				})
				return { connectionSummary = { databaseName = "ApplicationDb" } }
			end,
			disconnect_async = function() end,
			execute_async = function()
				return coroutine.yield()
			end,
			cancel_async = function() end,
			list_databases_async = function()
				return { "ApplicationDb" }
			end,
			rebuild_intellisense = function() end,
		}
		workspace = workspace_module.create({
			bufnr = 99,
			backend = backend,
			objects = objects,
		})

		registry.attach(99, workspace)
		assert(registry.get(99) == workspace)
		assert(registry.find_by_owner_uri(backend.owner_uri) == workspace)
		assert(workspace.get_state() == workspace_module.states.disconnected)

		workspace.connect_async({
			connection = {
				options = { server = "localhost", database = "master", trustServerCertificate = true },
			},
		})
		assert(workspace.get_state() == workspace_module.states.connected)
		assert(workspace.get_connection().database == "ApplicationDb")
		assert(initialized_connection.trustServerCertificate == true)

		local execution = coroutine.create(function()
			local result = workspace.execute_async("WAITFOR DELAY '00:00:01'")
			assert(result == nil)
		end)
		assert(coroutine.resume(execution))
		assert(workspace.get_state() == workspace_module.states.executing)
		workspace.cancel_async()
		assert(workspace.get_state() == workspace_module.states.cancelling)
		assert(coroutine.resume(execution, { batchSummaries = {} }))
		assert(workspace.get_state() == workspace_module.states.connected)

		workspace.disconnect_async()
		assert(workspace.get_state() == workspace_module.states.disconnected)
		assert(workspace.get_connection() == nil)
		assert(registry.detach(99) == workspace)
	end,
}
