local utils = require("sqlserver.utils")

local M = {}

M.client_name = "mssql_ls"

local attach_waiters = {}

local sanitize_result_methods = {
	["completionItem/resolve"] = true,
	["textDocument/completion"] = true,
	["textDocument/signatureHelp"] = true,
}

---@param opts table
---@return string
function M.default_executable(opts)
	local path = vim.fs.joinpath(opts.data_dir, "sqltools/MicrosoftSqlToolsServiceLayer")
	if jit.os == "Windows" then
		path = path .. ".exe"
	end
	return path
end

local function sanitize_lsp_results(client)
	if client.sqlserver_sanitizes_lsp_results then
		return
	end
	client.sqlserver_sanitizes_lsp_results = true

	local request = client.request
	client.request = function(self, method, params, handler, ...)
		if sanitize_result_methods[method] and type(handler) == "function" then
			params = utils.remove_lsp_nulls(params)
			local wrapped_handler = function(err, result, ctx, config)
				return handler(err, utils.remove_lsp_nulls(result), ctx, config)
			end
			return request(self, method, params, wrapped_handler, ...)
		end

		return request(self, method, params, handler, ...)
	end
end

local function notify_attach_waiters(bufnr, client)
	local waiters = attach_waiters[bufnr]
	attach_waiters[bufnr] = nil
	if not waiters then
		return
	end

	for _, waiter in ipairs(waiters) do
		waiter(client)
	end
end

---@class SqlServerSqlToolsCallbacks
---@field on_attach? fun(client: vim.lsp.Client, bufnr: integer)
---@field on_connection_changed? fun(result: table)
---@field on_query_message? fun(message: string, is_error: boolean)

---@param opts table
---@param callbacks? SqlServerSqlToolsCallbacks
function M.enable(opts, callbacks)
	callbacks = callbacks or {}

	-- SQL Tools Service can send duplicate readiness notifications together.
	local hide_intellisense_ready = false
	local config = {
		cmd = {
			opts.tools_file or M.default_executable(opts),
			"--enable-connection-pooling",
			"--enable-sql-authentication-provider",
			"--log-file",
			vim.fs.joinpath(opts.data_dir, "sqltools.log"),
			"--application-name",
			"neovim",
			"--data-path",
			vim.fs.joinpath(opts.data_dir, "sql-tools-data"),
		},
		filetypes = { "sql" },
		handlers = {
			["textDocument/intelliSenseReady"] = function(err, result)
				if err then
					utils.log_error("Could not start intellisense: " .. vim.inspect(err))
				elseif not hide_intellisense_ready then
					hide_intellisense_ready = true
					utils.log_info("Intellisense ready")
					vim.defer_fn(function()
						hide_intellisense_ready = false
					end, 1000)
				end
				return result, err
			end,
			["query/message"] = function(_, result)
				local message = result and result.message
				if message and message.message and callbacks.on_query_message then
					callbacks.on_query_message(message.message, message.isError)
				end
			end,
			["connection/connectionchanged"] = function(_, result)
				if result and result.ownerUri and callbacks.on_connection_changed then
					callbacks.on_connection_changed(result)
				end
			end,
		},
		on_attach = function(client, bufnr)
			sanitize_lsp_results(client)
			if callbacks.on_attach then
				callbacks.on_attach(client, bufnr)
			end
			notify_attach_waiters(bufnr, client)
		end,
	}

	if opts.lsp_settings then
		config.settings = { mssql = opts.lsp_settings }
	end

	vim.lsp.config[M.client_name] = config
	vim.lsp.enable(M.client_name)
end

---Wait for SQL Tools Service to attach to a buffer.
---Must be called inside a coroutine.
---@param bufnr integer
---@param timeout integer
---@return vim.lsp.Client?
function M.wait_for_attach_async(bufnr, timeout)
	local client = vim.lsp.get_clients({ name = M.client_name, bufnr = bufnr })[1]
	if client then
		return client
	end

	local coroutine_to_resume = coroutine.running()
	local resumed = false
	local function resume(client_or_nil)
		if resumed then
			return
		end
		resumed = true
		utils.try_resume(coroutine_to_resume, client_or_nil)
	end

	attach_waiters[bufnr] = attach_waiters[bufnr] or {}
	table.insert(attach_waiters[bufnr], resume)

	vim.defer_fn(function()
		if resumed then
			return
		end
		utils.log_error("Waiting for the lsp to attach to buffer " .. bufnr .. " timed out")
		resume(nil)
	end, timeout)

	return coroutine.yield()
end

return M
