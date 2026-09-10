local M = {}

---@class SqlServerResultSet
---@field columns string[]
---@field column_metadata SqlServerResultColumn[]
---@field rows SqlServerResultCell[][]
---@field row_count integer
---@field duration_ms? number
---@field displayed_row_count integer
---@field truncated boolean
---@field locator table
---@field ordinal integer

---@param opts { columns: string[], column_metadata?: SqlServerResultColumn[], rows: SqlServerResultCell[][], row_count: integer, duration_ms?: number, locator: table, ordinal?: integer }
---@return SqlServerResultSet
function M.create(opts)
  assert(type(opts.columns) == "table", "Result columns are required")
  assert(type(opts.rows) == "table", "Result rows are required")
  assert(type(opts.row_count) == "number", "Result row count is required")
  assert(type(opts.locator) == "table", "Result locator is required")

  return {
    columns = vim.deepcopy(opts.columns),
    column_metadata = vim.deepcopy(opts.column_metadata or {}),
    rows = vim.deepcopy(opts.rows),
    row_count = opts.row_count,
    duration_ms = opts.duration_ms,
    displayed_row_count = #opts.rows,
    truncated = #opts.rows < opts.row_count,
    locator = vim.deepcopy(opts.locator),
    ordinal = opts.ordinal or 1,
  }
end

return M
