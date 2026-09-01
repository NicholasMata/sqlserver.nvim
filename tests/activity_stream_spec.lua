local activity_stream_module = require("sqlserver.core.activity_stream")

return {
	test_name = "Activity stream should isolate replaceable subscribers",
	run_test_async = function()
		local sqlserver = require("sqlserver")
		assert(type(sqlserver.subscribe_activity) == "function")
		assert(type(sqlserver.status) == "function")
		assert(require("sqlserver.default_opts").ui.presenter == "default")
		local errors = {}
		local received = {}
		local stream = activity_stream_module.create({
			on_error = function(message)
				table.insert(errors, message)
			end,
		})
		local unsubscribe = stream.subscribe(function(workspace, event)
			table.insert(received, { workspace = workspace, event = event })
		end)
		stream.subscribe(function()
			error("broken presenter")
		end)

		local workspace = { bufnr = 42 }
		local event = { status = "running", message = "Executing query" }
		stream.publish(workspace, event)
		assert(#received == 1)
		assert(received[1].workspace == workspace)
		assert(received[1].event ~= event)
		assert(received[1].event.message == event.message)
		assert(#errors == 1 and errors[1]:find("broken presenter", 1, true))

		unsubscribe()
		stream.publish(workspace, event)
		assert(#received == 1)
		assert(#errors == 2)
	end,
}
