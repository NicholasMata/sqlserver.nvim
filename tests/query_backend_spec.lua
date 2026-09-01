local query_backend = require("sqlserver.adapters.sql_tools_service.query_backend")
local utils = require("sqlserver.utils")

return {
  test_name = "Query backend should translate execution scopes",
  run_test_async = function()
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
      return {}
    end
    utils.get_lsp_client = function()
      return {}
    end
    utils.wait_for_notification_async = function()
      return { batchSummaries = {} }
    end

    local backend = query_backend.create(0, {})
    backend.execute_async({ kind = "statement", position = { line = 3, column = 7 } })
    backend.execute_async({ kind = "selection", text = "SELECT 1" })
    backend.execute_async({ kind = "buffer", text = "SELECT 2" })
    local rows = query_backend.get_result_rows_async({ ownerUri = "file:///query.sql", rowsCount = 1 })

    utils.lsp_request_async = original_request
    utils.wait_for_notification_async = original_wait
    utils.get_lsp_client = original_get_client

    assert(requests[1].method == "query/executedocumentstatement")
    assert(requests[1].params.line == 3 and requests[1].params.column == 7)
    assert(requests[2].method == "query/executeString" and requests[2].params.query == "SELECT 1")
    assert(requests[3].method == "query/executeString" and requests[3].params.query == "SELECT 2")
    assert(requests[4].method == "query/subset")
    assert(rows[1][1].display_value == "NULL" and rows[1][1].is_null)
    assert(rows[1][1].invariant_value == nil)
  end,
}
