local sqlserver = require("sqlserver")

function iif(cond, true_value, false_value)
  if cond then
    return true_value
  else
    return false_value
  end
end

local tools_folder = vim.fs.joinpath(vim.fn.stdpath("data"), "sqlserver.nvim/sqltools")
local tools_file = iif(jit.os == "Windows", "MicrosoftSqlToolsServiceLayer.exe", "MicrosoftSqlToolsServiceLayer")

local function tools_file_exists()
  local f = io.open(vim.fs.joinpath(tools_folder, tools_file), "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function installed_version()
  local config_file = vim.fs.joinpath(vim.fn.stdpath("data"), "sqlserver.nvim/config.json")
  local lines = vim.fn.readfile(config_file)
  return vim.json.decode(table.concat(lines, "\n")).tools_version
end

local T = MiniTest.new_set()

T["Setup should provision SQL Tools Service"] = require("tests.helpers").async(function()
  local download_finished = false
  vim.defer_fn(function()
    assert(download_finished, "Download did not complete")
  end, 120000)

  download_finished = true
  assert(tools_file_exists(), "The sql server tools file does not exist among the downloads")
  assert(installed_version() == require("sqlserver.tools_downloader").default_version)
end)

return T
