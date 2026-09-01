local adapter = require("sqlserver.adapters.sql_tools_service")

return {
  test_name = "SQL Tools Service adapter should isolate LSP callbacks",
  run_test_async = function()
    local original_enable = vim.lsp.enable
    local enabled_name
    vim.lsp.enable = function(name)
      enabled_name = name
    end

    local attached_buffer
    local connection_change
    local query_message
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
    })
    vim.lsp.enable = original_enable

    assert(enabled_name == adapter.client_name)
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
  end,
}
