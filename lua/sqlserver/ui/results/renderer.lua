local M = {}

local function truncate(value, limit)
	local text = tostring(value):gsub("\r", ""):gsub("\n", "\\n")
	if vim.fn.strdisplaywidth(text) <= limit then
		return text, false
	end

	local available = math.max(limit - 1, 0)
	local length = vim.fn.strchars(text)
	local shortened = vim.fn.strcharpart(text, 0, math.min(length, available))
	while shortened ~= "" and vim.fn.strdisplaywidth(shortened) > available do
		length = vim.fn.strchars(shortened) - 1
		shortened = vim.fn.strcharpart(shortened, 0, length)
	end
	return shortened .. "…", true
end

local function pad(value, width)
	return value .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(value), 0))
end

---@param result_set SqlServerResultSet
---@param opts { max_cell_width: integer }
---@return { lines: string[], decorations: table[] }
function M.render(result_set, opts)
	local rows = {}
	local truncated = {}
	for row_index, row in ipairs(result_set.rows) do
		rows[row_index] = {}
		truncated[row_index] = {}
		for column_index, value in ipairs(row) do
			rows[row_index][column_index], truncated[row_index][column_index] = truncate(value, opts.max_cell_width)
		end
	end

	local widths = {}
	for column_index, column in ipairs(result_set.columns) do
		widths[column_index] = math.min(vim.fn.strdisplaywidth(column), opts.max_cell_width)
		for _, row in ipairs(rows) do
			widths[column_index] = math.max(widths[column_index], vim.fn.strdisplaywidth(row[column_index] or ""))
		end
	end

	local function render_row(values)
		local cells = {}
		for index, width in ipairs(widths) do
			table.insert(cells, pad(values[index] or "", width))
		end
		return table.concat(cells, " │ ")
	end

	local headers = {}
	for index, column in ipairs(result_set.columns) do
		headers[index] = truncate(column, opts.max_cell_width)
	end
	local divider = vim.iter(widths)
		:map(function(width)
			return string.rep("─", width)
		end)
		:join("───")
	local lines = { render_row(headers), divider }
	local decorations = {
		{ line = 0, start_col = 0, end_col = -1, highlight = "SqlServerResultHeader" },
		{ line = 1, start_col = 0, end_col = -1, highlight = "SqlServerResultBorder" },
	}

	for row_index, row in ipairs(rows) do
		local line = render_row(row)
		table.insert(lines, line)
		local byte_col = 0
		for column_index, value in ipairs(row) do
			local end_col = byte_col + #value
			if truncated[row_index][column_index] then
				table.insert(decorations, {
					line = row_index + 1,
					start_col = byte_col,
					end_col = end_col,
					highlight = "SqlServerResultTruncated",
				})
			elseif value == "NULL" then
				table.insert(decorations, {
					line = row_index + 1,
					start_col = byte_col,
					end_col = end_col,
					highlight = "SqlServerResultNull",
				})
			end
			byte_col = byte_col + #pad(value, widths[column_index]) + 3
		end
	end

	if result_set.truncated then
		table.insert(lines, "")
		table.insert(
			lines,
			string.format("Showing %d of %d rows", result_set.displayed_row_count, result_set.row_count)
		)
		table.insert(decorations, {
			line = #lines - 1,
			start_col = 0,
			end_col = -1,
			highlight = "SqlServerResultTruncated",
		})
	end

	return { lines = lines, decorations = decorations }
end

return M
