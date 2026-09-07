local utils = require("sqlserver.utils")

local T = MiniTest.new_set()

T["LSP null values should be removed from nested tables"] = require("tests.helpers").async(function()
  local result = {
    isIncomplete = false,
    items = {
      {
        label = "SELECT",
        sortText = vim.NIL,
        filterText = vim.NIL,
        textEdit = {
          newText = "SELECT",
          insert = vim.NIL,
        },
      },
    },
    itemDefaults = {
      commitCharacters = vim.NIL,
    },
    signatureHelp = {
      signatures = vim.NIL,
    },
  }

  local sanitized = utils.remove_lsp_nulls(result)

  assert(sanitized == result)
  assert(sanitized.items[1].label == "SELECT")
  assert(sanitized.items[1].sortText == nil)
  assert(sanitized.items[1].filterText == nil)
  assert(sanitized.items[1].textEdit.insert == nil)
  assert(sanitized.itemDefaults.commitCharacters == nil)
  assert(sanitized.signatureHelp.signatures == nil)
end)

return T
