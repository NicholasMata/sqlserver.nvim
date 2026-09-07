local utils = require("sqlserver.utils")
local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

T["Autocomplete should work after new_query()"] = require("tests.helpers").async(function()
  require("sqlserver").new_query()
  vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, 0, false, { "se * from TestTable" })

  test_utils.defer_async(3000)
  assert(#vim.lsp.get_clients({ bufnr = 0 }) == 1, "No lsp clients attached")

  -- move to the first E in SELECT
  vim.api.nvim_win_set_cursor(0, { 1, 1 })
  local items = test_utils.get_completion_items()
  assert(#items > 0, "Neovim didn't provide any completion items")
  assert(utils.contains(items, "SELECT"))
end)

return T
