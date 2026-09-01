local M = {}

---@class SqlServerResultSet
---@field columns string[]
---@field rows any[][]
---@field row_count integer
---@field displayed_row_count integer
---@field truncated boolean
---@field locator table

---@param opts { columns: string[], rows: any[][], row_count: integer, locator: table }
---@return SqlServerResultSet
function M.create(opts)
	assert(type(opts.columns) == "table", "Result columns are required")
	assert(type(opts.rows) == "table", "Result rows are required")
	assert(type(opts.row_count) == "number", "Result row count is required")
	assert(type(opts.locator) == "table", "Result locator is required")

	return {
		columns = vim.deepcopy(opts.columns),
		rows = vim.deepcopy(opts.rows),
		row_count = opts.row_count,
		displayed_row_count = #opts.rows,
		truncated = #opts.rows < opts.row_count,
		locator = vim.deepcopy(opts.locator),
	}
end

return M
