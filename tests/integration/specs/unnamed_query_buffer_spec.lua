local sqlserver = require("sqlserver")
local test_utils = require("tests.helpers.integration")

local T = MiniTest.new_set()

local function unnamed_sql_buffer(value)
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  assert(vim.api.nvim_buf_get_name(bufnr) == "", "The regression requires an unnamed buffer")
  vim.cmd("set ft=sql")
  assert(vim.api.nvim_buf_get_name(bufnr):match("untitled%-" .. bufnr .. "%.sql$"))
  assert(
    vim.wait(10000, function()
      return test_utils.get_sql_client(bufnr) ~= nil
    end, 10),
    "SQL Tools Service did not attach to the unnamed SQL buffer"
  )
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { ("SELECT %d AS Answer;"):format(value) })
  return bufnr
end

local function execute(bufnr)
  local execution = test_utils.await(function(callback)
    sqlserver.execute({ bufnr = bufnr, scope = "buffer" }, callback)
  end)
  assert(#execution.result_sets == 1, "Executing an unnamed SQL buffer returned no result set")
  return execution
end

T["Unnamed SQL buffers should have isolated connections and documents"] = require("tests.helpers").async(function()
  local first = unnamed_sql_buffer(41)
  local second = unnamed_sql_buffer(42)
  assert(vim.api.nvim_buf_get_name(first) ~= vim.api.nvim_buf_get_name(second))

  test_utils.connect(first)
  test_utils.connect(second)
  local first_execution = execute(first)
  local second_execution = execute(second)

  assert(first_execution.result_sets[1].rows[1][1].display_value == "41")
  assert(second_execution.result_sets[1].rows[1][1].display_value == "42")
  assert(first_execution.dispose())
  assert(second_execution.dispose())
end)

return T
