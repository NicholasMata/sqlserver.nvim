local MiniTest = require("mini.test")

local suite = vim.env.SQLSERVER_TEST_SUITE or "unit"
local path = vim.fs.joinpath("tests", suite)
local filter = vim.env.SQLSERVER_TEST_FILTER

MiniTest.execute(MiniTest.collect({
  find_files = function()
    return vim.fn.globpath(path, "test_*.lua", true, true)
  end,
  filter_cases = function(case)
    return not filter or table.concat(case.desc, " "):find(filter, 1, true) ~= nil
  end,
}))
