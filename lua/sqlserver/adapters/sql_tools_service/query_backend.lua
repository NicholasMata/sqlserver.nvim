local utils = require("sqlserver.utils")

local M = {}

---@param bufnr integer
---@param client vim.lsp.Client
function M.create(bufnr, client)
  local owner_uri = utils.lsp_file_uri(bufnr)

  return {
    owner_uri = owner_uri,

    connect_async = function(connect_params)
      connect_params.ownerUri = owner_uri
      local _, request_error = utils.lsp_request_async(client, "connection/connect", connect_params)
      if request_error then
        error("Could not connect: " .. request_error.message, 0)
      end

      local result, notification_error = utils.wait_for_notification_async(bufnr, client, "connection/complete", 10000)
      if notification_error then
        error("Error in connecting: " .. notification_error.message, 0)
      end
      if result and type(result.errorMessage) == "string" then
        error("Error in connecting: " .. result.errorMessage, 0)
      end
      return result
    end,

    disconnect_async = function()
      local _, err = utils.lsp_request_async(client, "connection/disconnect", { ownerUri = owner_uri })
      if err then
        error("Could not disconnect: " .. err.message, 0)
      end
    end,

    execute_async = function(request)
      local method
      local params = { ownerUri = owner_uri }
      if request.kind == "statement" then
        method = "query/executedocumentstatement"
        params.line = request.position.line
        params.column = request.position.column
      elseif request.kind == "selection" or request.kind == "buffer" then
        method = "query/executeString"
        params.query = request.text
      else
        error("Unknown query execution kind: " .. vim.inspect(request.kind), 0)
      end

      local result, request_error = utils.lsp_request_async(client, method, params)
      if request_error then
        error("Error executing query: " .. request_error.message, 0)
      end
      if not result then
        error("Could not execute query", 0)
      end

      local completed, notification_error = utils.wait_for_notification_async(bufnr, client, "query/complete", 360000)
      if notification_error then
        error("Could not execute query: " .. vim.inspect(notification_error), 0)
      end
      return completed
    end,

    cancel_async = function()
      local _, err = utils.lsp_request_async(client, "query/cancel", { ownerUri = owner_uri })
      if err then
        error("Could not cancel query: " .. err.message, 0)
      end
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

    rebuild_intellisense = function()
      client:notify("textDocument/rebuildIntelliSense", { ownerUri = owner_uri })
    end,

    client = client,
  }
end

return M
