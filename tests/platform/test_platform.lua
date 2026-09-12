local client = require("sqlserver.adapters.sql_tools_service.client")
local helpers = require("tests.helpers")
local installer = require("sqlserver.adapters.sql_tools_service.installer")

local T = MiniTest.new_set({
  hooks = {
    post_once = function()
      client.stop()
    end,
  },
})

T["managed SQL Tools Service installs and starts"] = helpers.async(function()
  local data_dir = vim.fn.tempname()
  local setup_complete = false
  local stop_error

  vim.fn.mkdir(data_dir, "p")
  local ok, err = xpcall(function()
    require("sqlserver").setup({
      data_dir = data_dir,
      ui = { presenter = false, winbar = false },
    }, function()
      setup_complete = true
    end)

    assert(
      vim.wait(600000, function()
        return setup_complete
      end, 20),
      "SQL Tools Service installation timed out"
    )

    local executable = client.default_executable({ data_dir = data_dir })
    assert(vim.fn.filereadable(executable) == 1, "SQL Tools Service executable was not installed")
    assert(vim.fn.executable(executable) == 1, "SQL Tools Service file is not executable")

    local config_file = vim.fs.joinpath(data_dir, "config.json")
    local config = vim.json.decode(table.concat(vim.fn.readfile(config_file), "\n"))
    assert(config.tools_version == installer.default_version, "Installed SQL Tools Service version was not recorded")

    vim.cmd("enew")
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".sql")
    vim.bo[bufnr].filetype = "sql"
    local sql_client
    assert(
      vim.wait(60000, function()
        sql_client = vim.lsp.get_clients({ name = client.client_name, bufnr = bufnr })[1]
        return sql_client ~= nil
      end, 20),
      "SQL Tools Service did not attach to a SQL buffer"
    )
  end, debug.traceback)

  client.stop()
  if not vim.wait(30000, function()
    return #vim.lsp.get_clients({ name = client.client_name }) == 0
  end, 20) then
    stop_error = "SQL Tools Service client did not stop"
  end
  vim.fn.delete(data_dir, "rf")

  assert(ok, err)
  assert(not stop_error, stop_error)
end, 720000)

return T
