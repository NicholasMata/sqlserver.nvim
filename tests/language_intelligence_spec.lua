local utils = require("sqlserver.utils")
local test_utils = require("tests.utils")

local function request_async(client, method, params)
  local result, err = utils.lsp_request_async(client, method, params)
  assert(not err, method .. " failed: " .. vim.inspect(err))
  return result
end

return {
  test_name = "SQL language intelligence should be available",
  run_test_async = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local client = utils.get_lsp_client()
    local capabilities = client.server_capabilities

    assert(capabilities.completionProvider, "SQL Tools Service did not advertise completion")
    assert(capabilities.hoverProvider, "SQL Tools Service did not advertise hover")
    assert(capabilities.signatureHelpProvider, "SQL Tools Service did not advertise signature help")
    assert(capabilities.definitionProvider, "SQL Tools Service did not advertise definitions")
    assert(capabilities.documentFormattingProvider, "SQL Tools Service did not advertise formatting")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "select * from dbo.Car" })
    vim.api.nvim_win_set_cursor(0, { 1, 19 })
    utils.defer_async(500)

    local position = { line = 0, character = 19 }
    local text_document = { uri = utils.lsp_file_uri(bufnr) }
    local hover = request_async(client, "textDocument/hover", {
      textDocument = text_document,
      position = position,
    })
    assert(hover and hover.contents, "SQL Tools Service returned no hover information for dbo.Car")

    local definition = request_async(client, "textDocument/definition", {
      textDocument = text_document,
      position = position,
    })
    assert(definition and (definition.uri or definition[1]), "SQL Tools Service returned no definition for dbo.Car")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "select id,make from dbo.Car" })
    utils.defer_async(500)
    local formatted = request_async(client, "textDocument/formatting", {
      textDocument = text_document,
      options = { tabSize = 4, insertSpaces = true },
    })
    assert(formatted and formatted[1] and formatted[1].newText, "SQL Tools Service returned no formatting edits")
    assert(formatted[1].newText:find("SELECT", 1, true), "Formatting settings did not uppercase SELECT")

    local procedure = "EXEC dbo.GetCar "
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { procedure })
    utils.defer_async(500)
    local signature = request_async(client, "textDocument/signatureHelp", {
      textDocument = text_document,
      position = { line = 0, character = #procedure },
      -- LSP SignatureHelpTriggerKind.Invoked. Neovim 0.11 does not export this enum.
      context = { triggerKind = 1 },
    })
    assert(
      signature and signature.signatures and signature.signatures[1],
      "SQL Tools Service returned no signature help for dbo.GetCar"
    )

    local diagnostics
    local diagnostics_err
    test_utils.wait_for_all_async({
      function()
        diagnostics, diagnostics_err =
          utils.wait_for_notification_async(bufnr, client, "textDocument/publishDiagnostics", 10000)
      end,
      function()
        utils.defer_async(100)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT * FORM dbo.Car" })
      end,
    })
    assert(not diagnostics_err, diagnostics_err and diagnostics_err.message or "Diagnostics failed")
    assert(diagnostics and diagnostics.diagnostics[1], "SQL Tools Service returned no diagnostics for invalid SQL")
  end,
}
