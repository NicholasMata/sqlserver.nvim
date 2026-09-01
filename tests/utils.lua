local utils = require("sqlserver.utils")

return {
	defer_async = utils.defer_async,
	get_completion_items = function()
		local client = utils.get_lsp_client()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local result, err = utils.lsp_request_async(client, "textDocument/completion", {
			textDocument = { uri = utils.lsp_file_uri() },
			-- Normal-mode cursor columns point at a character. Completion is
			-- requested at the insertion point immediately after it.
			position = { line = cursor[1] - 1, character = cursor[2] + 1 },
			context = { triggerKind = vim.lsp.protocol.CompletionTriggerKind.Invoked },
		})
		assert(not err, err and err.message or "Completion request failed")

		local items = result and (result.items or result) or {}
		return vim.iter(items)
			:map(function(item)
				return item.label
			end)
			:totable()
	end,

	ui_select_fake = function(item)
		local original_select = vim.ui.select
		---@diagnostic disable-next-line: duplicate-set-field
		vim.ui.select = function(items, _, on_choice)
			vim.ui.select = original_select
			local index
			if type(item) == "string" then
				index = vim.fn.index(items, item) + 1
				if index == nil or index == 0 then
					error("You tried to choose " .. item .. "when prompted but this wasn't an option", 0)
				end
			elseif type(item) == "number" then
				index = item
				if not items[index] then
					error("The index " .. index .. " is out of range in the items: " .. vim.inspect(items))
				end
				item = items[index]
			end
			vim.defer_fn(function()
				on_choice(item, index)
			end, 3000)
		end
	end,

	-- Takes a list of functions that should be run inside a coroutine,
	-- runs each one and waits for all of them to finish. Must be
	-- run inside a coroutine
	wait_for_all_async = function(async_functions)
		local finished_count = 0
		local co = coroutine.running()

		for _, f in ipairs(async_functions) do
			coroutine.resume(coroutine.create(function()
				f()
				finished_count = finished_count + 1
				if finished_count == #async_functions then
					coroutine.resume(co)
				end
			end))
		end
		coroutine.yield()
	end,
}
