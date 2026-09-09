local utils = require("sqlserver.utils")
local result_cell = require("sqlserver.results.cell")
local connection_profiles = require("sqlserver.connections.profiles")

local M = {}

local function connection_timeout_error(timeout_ms)
  return setmetatable({
    message = "SQL Server connection timed out",
    operation_message = "Connection timed out",
    diagnostic = string.format(
      "SQL Tools Service did not send connection/complete within %.0f seconds",
      timeout_ms / 1000
    ),
  }, {
    __tostring = function(err)
      return err.message
    end,
  })
end

local function query_timeout_error(timeout_ms, cancellation_error)
  local diagnostic =
    string.format("SQL Tools Service did not send query/complete within %.0f seconds", timeout_ms / 1000)
  if cancellation_error then
    diagnostic = diagnostic .. "; cancellation request failed: " .. cancellation_error.message
  else
    diagnostic = diagnostic .. "; cancellation was requested"
  end
  return {
    message = "SQL Server query timed out",
    diagnostic = diagnostic,
    operation_message = "Query timed out",
  }
end

---@param locator table
---@return SqlServerResultCell[][]
function M.get_result_rows_async(locator)
  if not (locator and locator.rowsCount and locator.rowsCount > 0) then
    return {}
  end

  local client = utils.get_lsp_client(locator.ownerUri)
  local result, err = utils.lsp_request_async(client, "query/subset", locator)
  if err then
    error("Error getting rows: " .. vim.inspect(err), 0)
  end
  if not (result and result.resultSubset and result.resultSubset.rows) then
    error("SQL Tools Service returned no result rows", 0)
  end

  return vim
    .iter(result.resultSubset.rows)
    :map(function(row)
      return vim
        .iter(row)
        :map(function(cell)
          return result_cell.create({
            display_value = cell.displayValue,
            invariant_value = cell.invariantCultureDisplayValue ~= vim.NIL and cell.invariantCultureDisplayValue or nil,
            is_null = cell.isNull,
          })
        end)
        :totable()
    end)
    :totable()
end

local export_methods = {
  csv = "query/saveCsv",
  json = "query/saveJson",
  xml = "query/saveXml",
  xlsx = "query/saveExcel",
}

local function read_file_tail(path, size)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.size == 0 then
    return stat, ""
  end
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return stat, ""
  end
  local length = math.min(size, stat.size)
  local contents = vim.uv.fs_read(fd, length, stat.size - length) or ""
  vim.uv.fs_close(fd)
  return stat, contents
end

local function export_is_complete(locator, path, format)
  local stat, tail = read_file_tail(path, 65557)
  if not stat then
    return false
  end
  if stat.size == 0 then
    return false
  end
  if format == "xlsx" then
    return tail:find("PK\005\006", 1, true) ~= nil
  end
  if format == "json" then
    return tail:match("%]%s*$") ~= nil
  end
  return true
end

---@param locator table
---@param path string
---@param format string
---@param opts? { timeout?: integer|false }
function M.export_result_async(locator, path, format, opts)
  opts = opts or {}
  local method = export_methods[format]
  if not method then
    error("Unsupported result export format: " .. tostring(format), 0)
  end
  local client = utils.get_lsp_client(locator.ownerUri)
  local params = {
    FilePath = path,
    BatchIndex = locator.batchIndex,
    ResultSetIndex = locator.resultSetIndex,
    OwnerUri = locator.ownerUri,
    IncludeHeaders = true,
    Formatted = true,
  }
  if opts.selection then
    params.RowStartIndex = opts.selection.row_start
    params.RowEndIndex = opts.selection.row_end
    params.ColumnStartIndex = opts.selection.column_start
    params.ColumnEndIndex = opts.selection.column_end
  end
  local _, err = utils.lsp_request_async(client, method, params)
  if err then
    error("Could not export query result: " .. err.message, 0)
  end
  -- SQL Tools Service sends the response from inside the writer's scope. Some
  -- formats are not complete until that writer is disposed after the response.
  if locator.rowsCount ~= nil then
    local started_at = vim.uv.hrtime()
    while not export_is_complete(locator, path, format) do
      if opts.timeout and (vim.uv.hrtime() - started_at) / 1e6 >= opts.timeout then
        error("SQL Tools Service did not finish writing the export within the configured timeout", 0)
      end
      utils.defer_async(10)
    end
  end
end

---@param bufnr integer
---@param client vim.lsp.Client
---@param timeouts? table
function M.create(bufnr, client, timeouts)
  local owner_uri = utils.lsp_file_uri(bufnr)
  timeouts = timeouts or { connection = 10000, query = false }
  local next_query_id = 0
  local active_query_id

  local function dispose_query_async(query_id)
    if not active_query_id or (query_id and query_id ~= active_query_id) then
      return false
    end

    local disposing_query_id = active_query_id
    active_query_id = nil
    local _, err = utils.lsp_request_async(client, "query/dispose", { ownerUri = owner_uri })
    if err then
      if active_query_id == nil then
        active_query_id = disposing_query_id
      end
      error("Could not dispose query results: " .. err.message, 0)
    end
    return true
  end

  return {
    owner_uri = owner_uri,
    fetch_result_rows_async = M.get_result_rows_async,

    connect_async = function(connect_params)
      connect_params.ownerUri = owner_uri
      local connection = connect_params.connection and connect_params.connection.options
      local _, request_error = utils.lsp_request_async(client, "connection/connect", connect_params)
      if request_error then
        error(connection_profiles.failure(request_error.message, connection), 0)
      end

      local connection_timeout_ms = timeouts.connection
      local result, notification_error =
        utils.wait_for_notification_async(bufnr, client, "connection/complete", connection_timeout_ms)
      if notification_error then
        if connection_timeout_ms then
          error(connection_timeout_error(connection_timeout_ms), 0)
        end
        error("Could not connect: " .. notification_error.message, 0)
      end
      if result and type(result.errorMessage) == "string" then
        error(connection_profiles.failure(result.errorMessage, connection), 0)
      end
      return result
    end,

    disconnect_async = function()
      pcall(dispose_query_async)
      local _, err = utils.lsp_request_async(client, "connection/disconnect", { ownerUri = owner_uri })
      if err then
        error("Could not disconnect: " .. err.message, 0)
      end
    end,

    execute_async = function(request)
      -- SQL Tools Service stores one query per owner URI. Dispose the previous
      -- query explicitly before replacing it so its result storage is released.
      pcall(dispose_query_async)
      next_query_id = next_query_id + 1
      local query_id = next_query_id

      local method
      local params = { ownerUri = owner_uri }
      if request.kind == "statement" then
        method = "query/executedocumentstatement"
        params.line = request.position.line
        params.column = request.position.column
      elseif (request.kind == "selection" or request.kind == "buffer") and request.range then
        method = "query/executeDocumentSelection"
        params.querySelection = request.range
      elseif request.kind == "selection" or request.kind == "buffer" then
        method = "query/executeString"
        params.query = request.text
      else
        error("Unknown query execution kind: " .. vim.inspect(request.kind), 0)
      end

      -- Passing the owning buffer makes Neovim flush its pending didChange for
      -- this document before SQL Tools Service selects from it.
      local result, request_error = utils.lsp_request_async(client, method, params, bufnr)
      if request_error then
        error("Error executing query: " .. request_error.message, 0)
      end
      if not result then
        error("Could not execute query", 0)
      end
      active_query_id = query_id

      local completed, notification_error =
        utils.wait_for_notification_async(bufnr, client, "query/complete", timeouts.query)
      if notification_error then
        if timeouts.query then
          local _, cancellation_error = utils.lsp_request_async(client, "query/cancel", { ownerUri = owner_uri })
          pcall(dispose_query_async, query_id)
          error(query_timeout_error(timeouts.query, cancellation_error), 0)
        end
        pcall(dispose_query_async, query_id)
        error("Could not execute query: " .. vim.inspect(notification_error), 0)
      end
      completed._sqlserver_query_id = query_id
      return completed
    end,

    cancel_async = function()
      local _, err = utils.lsp_request_async(client, "query/cancel", { ownerUri = owner_uri })
      if err then
        error("Could not cancel query: " .. err.message, 0)
      end
    end,

    dispose_query_async = dispose_query_async,

    export_result_async = function(locator, path, format, opts)
      if not active_query_id or locator._sqlserver_query_id ~= active_query_id then
        error("These query results are no longer available for export; execute the query again", 0)
      end
      return M.export_result_async(locator, path, format, opts)
    end,

    list_databases_async = function()
      local result, err = utils.lsp_request_async(client, "connection/listdatabases", { ownerUri = owner_uri })
      if err then
        error("Error listing databases: " .. err.message, 0)
      end
      if not (result and result.databaseNames) then
        error("Could not list databases", 0)
      end
      return result.databaseNames
    end,

    is_connected_async = function()
      local result, err = utils.lsp_request_async(client, "connection/listdatabases", { ownerUri = owner_uri })
      return err == nil and result ~= nil and result.databaseNames ~= nil
    end,

    rebuild_intellisense = function()
      client:notify("textDocument/rebuildIntelliSense", { ownerUri = owner_uri })
    end,

    client = client,
  }
end

return M
