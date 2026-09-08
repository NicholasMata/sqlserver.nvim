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
    for column_index, cell in ipairs(row) do
      rows[row_index][column_index], truncated[row_index][column_index] =
        truncate(cell.display_value, opts.max_cell_width)
    end
  end

  local widths = {}
  for column_index, column in ipairs(result_set.columns) do
    widths[column_index] = math.min(vim.fn.strdisplaywidth(column), opts.max_cell_width)
    for _, row in ipairs(rows) do
      widths[column_index] = math.max(widths[column_index], vim.fn.strdisplaywidth(row[column_index] or ""))
    end
  end

  local function render_row(values, separator)
    separator = separator or " │ "
    local parts = {}
    local ranges = {}
    local byte_col = 0
    for index, width in ipairs(widths) do
      local cell = pad(values[index] or "", width)
      ranges[index] = { start_col = byte_col, end_col = byte_col + #cell }
      table.insert(parts, cell)
      byte_col = byte_col + #cell
      if index < #widths then
        table.insert(parts, separator)
        byte_col = byte_col + #separator
      end
    end
    return table.concat(parts), ranges
  end

  local headers = {}
  for index, column in ipairs(result_set.columns) do
    headers[index] = truncate(column, opts.max_cell_width)
  end
  local divider_cells = vim
    .iter(widths)
    :map(function(width)
      return string.rep("─", width)
    end)
    :totable()
  local header, header_ranges = render_row(headers)
  local divider, divider_ranges = render_row(divider_cells, "───")
  local lines = { header, divider }
  local cell_ranges = { header_ranges, divider_ranges }
  local decorations = {
    { line = 0, start_col = 0, end_col = -1, highlight = "SqlServerResultHeader" },
    { line = 1, start_col = 0, end_col = -1, highlight = "SqlServerResultBorder" },
  }

  for row_index, row in ipairs(rows) do
    local line, ranges = render_row(row)
    table.insert(lines, line)
    cell_ranges[row_index + 2] = ranges
    for column_index, value in ipairs(row) do
      local start_col = ranges[column_index].start_col
      local end_col = start_col + #value
      if truncated[row_index][column_index] then
        table.insert(decorations, {
          line = row_index + 1,
          start_col = start_col,
          end_col = end_col,
          highlight = "SqlServerResultTruncated",
        })
      elseif result_set.rows[row_index][column_index].is_null then
        table.insert(decorations, {
          line = row_index + 1,
          start_col = start_col,
          end_col = end_col,
          highlight = "SqlServerResultNull",
        })
      end
    end
  end

  if result_set.truncated then
    table.insert(lines, "")
    table.insert(lines, string.format("Showing %d of %d rows", result_set.displayed_row_count, result_set.row_count))
    table.insert(decorations, {
      line = #lines - 1,
      start_col = 0,
      end_col = -1,
      highlight = "SqlServerResultTruncated",
    })
  end

  return { lines = lines, decorations = decorations, cell_ranges = cell_ranges }
end

return M
