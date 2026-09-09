local M = {}

local function column_at(ranges, byte_col)
  local column = 1
  for index, range in ipairs(ranges) do
    if byte_col < range.start_col then
      break
    end
    column = index
  end
  return column
end

---@class SqlServerResultSelection
---@field row_start integer Zero-based inclusive result row
---@field row_end integer Zero-based inclusive result row
---@field column_start integer Zero-based inclusive result column
---@field column_end integer Zero-based inclusive result column

---@param result_set SqlServerResultSet
---@param cell_ranges table<integer, table[]>
---@param first { line: integer, col: integer }
---@param last { line: integer, col: integer }
---@param mode string
---@return SqlServerResultSelection?
---@return string? error
function M.create(result_set, cell_ranges, first, last, mode)
  if first.line > last.line or (first.line == last.line and first.col > last.col) then
    first, last = last, first
  end

  local first_row = first.line - 2
  local last_row = last.line - 2
  if first_row < 1 or last_row > #result_set.rows then
    return nil, "Select only query result data cells"
  end

  local first_column = 1
  local last_column = #result_set.columns
  if mode ~= "V" then
    local first_ranges = cell_ranges[first.line]
    local last_ranges = cell_ranges[last.line]
    if not first_ranges or not last_ranges then
      return nil, "Select only query result data cells"
    end
    first_column = column_at(first_ranges, first.col)
    last_column = column_at(last_ranges, last.col)
    if first_column > last_column then
      first_column, last_column = last_column, first_column
    end
  end

  return {
    row_start = first_row - 1,
    row_end = last_row - 1,
    column_start = first_column - 1,
    column_end = last_column - 1,
  }
end

return M
