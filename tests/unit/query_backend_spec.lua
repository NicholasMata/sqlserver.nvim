local query_backend = require("sqlserver.adapters.sql_tools_service.query_backend")
local utils = require("sqlserver.utils")

local T = MiniTest.new_set()

T["Query backend should translate execution scopes"] = require("tests.helpers").async(function()
  local original_request = utils.lsp_request_async
  local original_wait = utils.wait_for_notification_async
  local original_get_client = utils.get_lsp_client
  local requests = {}
  utils.lsp_request_async = function(_, method, params)
    table.insert(requests, { method = method, params = params })
    if method == "query/subset" then
      return {
        resultSubset = {
          rows = {
            {
              {
                displayValue = "NULL",
                invariantCultureDisplayValue = vim.NIL,
                isNull = true,
              },
            },
          },
        },
      }
    end
    if method == "connection/listdatabases" then
      return { databaseNames = { "master" } }
    end
    return {}
  end
  utils.get_lsp_client = function()
    return {}
  end
  utils.wait_for_notification_async = function()
    return { batchSummaries = {} }
  end

  local backend = query_backend.create(0, {})
  local first_execution = backend.execute_async({ kind = "statement", position = { line = 3, column = 7 } })
  backend.execute_async({
    kind = "selection",
    text = "SELECT 1",
    range = { startLine = 1, startColumn = 2, endLine = 1, endColumn = 10 },
  })
  backend.execute_async({
    kind = "buffer",
    text = "SELECT 2",
    range = { startLine = 0, startColumn = 0, endLine = 0, endColumn = 8 },
  })
  backend.execute_async({ kind = "selection", text = "SELECT 3" })
  local rows = query_backend.get_result_rows_async({ ownerUri = "file:///query.sql", rowsCount = 1 })
  assert(backend.is_connected_async())

  utils.wait_for_notification_async = function()
    return nil, { message = "Waiting for internal notification timed out" }
  end
  local connected, connection_error = pcall(backend.connect_async, { connection = { options = {} } })
  assert(not connected)
  assert(tostring(connection_error) == "SQL Server connection timed out")
  assert(connection_error.diagnostic == "SQL Tools Service did not send connection/complete within 10 seconds")

  local timed_backend = query_backend.create(0, {}, { connection = 10000, query = 500 })
  local executed, query_error = pcall(timed_backend.execute_async, { kind = "buffer", text = "WAITFOR" })
  assert(not executed and query_error.message == "SQL Server query timed out")
  assert(query_error.diagnostic:find("cancellation was requested", 1, true))
  assert(requests[#requests - 1].method == "query/cancel")
  assert(requests[#requests].method == "query/dispose")

  utils.wait_for_notification_async = function()
    return { errorMessage = "Login failed using Secret123" }
  end
  local secret_backend = query_backend.create(0, {}, { connection = 10000, query = false })
  local secret_connected, secret_error = pcall(secret_backend.connect_async, {
    connection = { options = { password = "Secret123" } },
  })
  assert(not secret_connected)
  assert(secret_error.message == "SQL Server authentication failed")
  assert(secret_error.diagnostic:find("[REDACTED]", 1, true))
  assert(not secret_error.diagnostic:find("Secret123", 1, true))

  local execution_requests = vim.tbl_filter(function(request)
    return request.method:find("query/execute", 1, true) == 1
  end, requests)
  assert(execution_requests[1].method == "query/executedocumentstatement")
  assert(execution_requests[1].params.line == 3 and execution_requests[1].params.column == 7)
  assert(execution_requests[2].method == "query/executeDocumentSelection")
  assert(execution_requests[2].params.querySelection.startLine == 1)
  assert(execution_requests[2].params.query == nil)
  assert(execution_requests[3].method == "query/executeDocumentSelection")
  assert(execution_requests[3].params.querySelection.endColumn == 8)
  assert(execution_requests[4].method == "query/executeString" and execution_requests[4].params.query == "SELECT 3")
  assert(vim.iter(requests):any(function(request)
    return request.method == "query/subset"
  end))
  assert(vim.iter(requests):any(function(request)
    return request.method == "connection/listdatabases"
  end))
  local stale_export, stale_export_error = pcall(backend.export_result_async, {
    ownerUri = "file:///query.sql",
    batchIndex = 0,
    resultSetIndex = 0,
    _sqlserver_query_id = first_execution._sqlserver_query_id,
  }, "/tmp/stale.csv", "csv")
  assert(not stale_export)
  assert(stale_export_error:find("no longer available", 1, true))
  backend.export_result_async(
    { ownerUri = "file:///query.sql", batchIndex = 0, resultSetIndex = 0, _sqlserver_query_id = 4 },
    "/tmp/result.xlsx",
    "xlsx"
  )
  local excel_export = requests[#requests]
  assert(excel_export.method == "query/saveExcel")
  assert(excel_export.params.IncludeHeaders == true)
  local legacy_excel, legacy_excel_error = pcall(
    backend.export_result_async,
    { ownerUri = "file:///query.sql", _sqlserver_query_id = 4 },
    "/tmp/result.xls",
    "xls"
  )
  assert(not legacy_excel and legacy_excel_error:find("Unsupported result export format", 1, true))
  assert(first_execution._sqlserver_query_id == 1)
  assert(
    not backend.dispose_query_async(first_execution._sqlserver_query_id),
    "An old query must not dispose the current query"
  )
  assert(backend.dispose_query_async(), "The current query should be disposed")
  assert(not backend.dispose_query_async(), "A query should only be disposed once")
  assert(requests[#requests].method == "query/dispose")

  utils.lsp_request_async = original_request
  utils.wait_for_notification_async = original_wait
  utils.get_lsp_client = original_get_client

  assert(rows[1][1].display_value == "NULL" and rows[1][1].is_null)
  assert(rows[1][1].invariant_value == nil)
end)

return T
