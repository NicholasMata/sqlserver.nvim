local T = MiniTest.new_set()

T["setup reports failures through its callback"] = function()
  local callback_count = 0
  local result
  local setup_error

  require("sqlserver").setup({
    tools_file = vim.fs.joinpath(vim.fn.tempname(), "missing-sql-tools-service"),
    ui = { presenter = false, winbar = false },
  }, function(value, err)
    callback_count = callback_count + 1
    result = value
    setup_error = err
  end)

  assert(callback_count == 1, "Setup callback was not called exactly once")
  assert(result == nil, "Failed setup returned a result")
  assert(type(setup_error) == "string", "Failed setup did not return an error")
  assert(setup_error:find("SQL Tools Service executable was not found", 1, true), setup_error)
end

return T
