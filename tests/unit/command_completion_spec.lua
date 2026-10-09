local commands = require("sqlserver.ui.commands")
local workspace_module = require("sqlserver.workspace")
local registry = require("sqlserver.workspace.registry")
local results = require("sqlserver.results.ui.view")

local workspace
local original_get, original_has_results
local original_result_info

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      original_get, original_has_results = registry.get, results.has_results
      original_result_info = vim.b.query_result_info
      workspace = nil
      registry.get = function()
        return workspace
      end
      results.has_results = function()
        return false
      end
      vim.b.query_result_info = nil
      commands.setup({})
    end,
    post_case = function()
      registry.get, results.has_results = original_get, original_has_results
      vim.b.query_result_info = original_result_info
      vim.api.nvim_del_user_command("SQLServer")
    end,
  },
})

local function expect_completion(prefix, expected)
  MiniTest.expect.equality(vim.fn.getcompletion("SQLServer " .. prefix, "cmdline"), expected)
end

T["Empty prefixes preserve all available suggestions and their order"] = function()
  expect_completion("", { "NewQuery", "NewDefaultQuery", "EditConnections" })
end

T["Prefixes match without case sensitivity and retain canonical spelling"] = function()
  expect_completion("New", { "NewQuery", "NewDefaultQuery" })
  expect_completion("nEw", { "NewQuery", "NewDefaultQuery" })
  expect_completion("newquery", { "NewQuery" })
end

T["Unmatched and pattern-like prefixes return no suggestions"] = function()
  expect_completion("unknown", {})
  expect_completion("NewQueryExtra", {})
  expect_completion("N.*", {})
end

T["Filtering retains workspace-dependent command availability"] = function()
  local state = workspace_module.states.connected
  workspace = {
    get_state = function()
      return state
    end,
    get_active_operation = function()
      return nil
    end,
  }
  expect_completion("ex", { "ExecuteQuery", "ExecuteBuffer" })
  expect_completion("ca", {})

  state = workspace_module.states.executing
  expect_completion("ex", {})
  expect_completion("ca", { "CancelOperation" })
end

T["Result buffers retain their own completion candidates"] = function()
  vim.b.query_result_info = {}
  expect_completion("next", { "NextResult", "NextExecution" })
  expect_completion("ex", { "ExportQueryResults" })
  expect_completion("connect", {})
end

return T
