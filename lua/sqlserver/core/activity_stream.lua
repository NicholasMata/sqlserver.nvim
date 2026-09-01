local M = {}

---@class SqlServerActivityEvent
---@field kind string
---@field status "running"|"success"|"error"|"cancelled"|"info"
---@field message string
---@field title? string
---@field operation_id? integer
---@field duration_ms? number
---@field time string

---@class SqlServerActivityStream
---@field publish fun(workspace: SqlServerWorkspace, event: SqlServerActivityEvent)
---@field subscribe fun(subscriber: fun(workspace: SqlServerWorkspace, event: SqlServerActivityEvent)): fun()

---@param opts? { on_error?: fun(message: string) }
---@return SqlServerActivityStream
function M.create(opts)
	opts = opts or {}
	local subscribers = {}
	local next_subscriber_id = 0

	local stream = {}

	function stream.publish(workspace, event)
		local snapshot = {}
		for _, subscriber in pairs(subscribers) do
			table.insert(snapshot, subscriber)
		end
		for _, subscriber in ipairs(snapshot) do
			local ok, err = pcall(subscriber, workspace, vim.deepcopy(event))
			if not ok and opts.on_error then
				opts.on_error("SQL Server activity subscriber failed: " .. tostring(err))
			end
		end
	end

	function stream.subscribe(subscriber)
		assert(type(subscriber) == "function", "An activity subscriber function is required")
		next_subscriber_id = next_subscriber_id + 1
		local subscriber_id = next_subscriber_id
		subscribers[subscriber_id] = subscriber
		local subscribed = true

		return function()
			if subscribed then
				subscribers[subscriber_id] = nil
				subscribed = false
			end
		end
	end

	return stream
end

return M
