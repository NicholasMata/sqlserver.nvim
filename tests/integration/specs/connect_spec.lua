local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

T["Connect to database should work"] = require("tests.helpers").async(function()
  local bufnr = test_utils.new_query_buffer()
  local connection = test_utils.connect(bufnr)
  assert(connection.database == vim.env.DbDatabase)
  assert(test_utils.get_sql_client(bufnr), "No SQL Tools Service client attached")
end)

return T
