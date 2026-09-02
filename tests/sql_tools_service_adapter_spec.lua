local adapter = require("sqlserver.adapters.sql_tools_service")
local constants = require("sqlserver.adapters.sql_tools_service.constants")

return {
  test_name = "SQL Tools Service adapter should isolate LSP callbacks",
  run_test_async = function()
    assert(constants.client_name == "mssql_ls", "The public Neovim LSP client name should remain stable")
    assert(adapter.client_name == constants.client_name)

    local original_enable = vim.lsp.enable
    local enabled_name
    vim.lsp.enable = function(name)
      enabled_name = name
    end

    local attached_buffer
    local connection_change
    local query_message
    local service_exit
    adapter.enable({ data_dir = "/tmp/sqlserver.nvim-test" }, {
      on_attach = function(_, bufnr)
        attached_buffer = bufnr
      end,
      on_connection_changed = function(result)
        connection_change = result
      end,
      on_query_message = function(message, is_error, owner_uri)
        query_message = { message = message, is_error = is_error, owner_uri = owner_uri }
      end,
      on_exit = function(code, signal, client_id)
        service_exit = { code = code, signal = signal, client_id = client_id }
      end,
    })
    vim.lsp.enable = original_enable

    assert(enabled_name == constants.client_name)
    local config = vim.lsp.config[adapter.client_name]
    assert(config)

    local fake_client = {
      request = function(_, _, _, handler)
        handler(nil, { value = vim.NIL })
      end,
    }
    config.on_attach(fake_client, 42)
    assert(attached_buffer == 42)

    local sanitized
    fake_client:request("textDocument/completion", {}, function(_, result)
      sanitized = result
    end)
    assert(sanitized.value == nil)

    config.handlers["connection/connectionchanged"](nil, { ownerUri = "file:///query.sql" })
    assert(connection_change.ownerUri == "file:///query.sql")

    config.handlers["query/message"](nil, {
      ownerUri = "file:///query.sql",
      message = { message = "Done", isError = false },
    })
    assert(query_message.message == "Done")
    assert(query_message.is_error == false)
    assert(query_message.owner_uri == "file:///query.sql")

    config.on_exit(1, 9, 123)
    assert(service_exit.code == 1)
    assert(service_exit.signal == 9)
    assert(service_exit.client_id == 123)

    local original_get_clients = vim.lsp.get_clients
    local stopped = false
    vim.lsp.get_clients = function()
      return {
        {
          stop = function(_, force)
            stopped = force
          end,
        },
      }
    end
    adapter.stop()
    vim.lsp.get_clients = original_get_clients
    assert(stopped, "SQL Tools Service clients should be force-stopped during cleanup")
  end,
}
