local helpers = require("tests.helpers")
local integration = require("tests.helpers.integration")
local shards = require("tests.integration.shards")
local shard = vim.env.SQLSERVER_INTEGRATION_SHARD

local T = MiniTest.new_set({
  hooks = {
    pre_once = helpers.async(function()
      for _, name in ipairs({ "DbServer", "DbDatabase", "DbUser", "DbPassword" }) do
        assert(vim.env[name] and vim.env[name] ~= "", name .. " is required for integration tests")
      end
      integration.setup()
    end),
    post_once = function()
      require("sqlserver.adapters.sql_tools_service.client").stop()
    end,
  },
})

T["environment"] = MiniTest.new_set({
  hooks = { post_case = helpers.async(integration.cleanup) },
})
for _, module in ipairs(shards.modules("environment", shard)) do
  T["environment"][module] = require("tests.integration.specs." .. module)
end

T["connected workspace"] = MiniTest.new_set({ hooks = integration.connected_hooks() })
for _, module in ipairs(shards.modules("connected", shard)) do
  T["connected workspace"][module] = require("tests.integration.specs." .. module)
end

return T
