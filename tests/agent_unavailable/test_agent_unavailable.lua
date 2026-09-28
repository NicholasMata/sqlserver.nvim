local client = require("sqlserver.adapters.sql_tools_service.client")
local helpers = require("tests.helpers")
local integration = require("tests.helpers.integration")
local utils = require("sqlserver.utils")

local T = MiniTest.new_set()

T["Express reports Agent unavailable instead of an empty list"] = helpers.async(function()
  integration.setup()
  local bufnr = integration.new_query_buffer()
  integration.connect(bufnr, "master")

  local ok, failure = xpcall(function()
    local owner_uri = utils.lsp_file_uri(bufnr)
    for _, method in ipairs({ "agent/jobs", "agent/alerts" }) do
      local response, err = utils.lsp_request_async(integration.get_sql_client(bufnr), method, {
        ownerUri = owner_uri,
      }, bufnr)
      assert(not err, method .. " failed at the transport layer")
      assert(response and response.success == false, method .. " did not report Agent unavailable")
      assert(type(response.errorMessage) == "string")
      assert(response.errorMessage:find("not supported on this edition", 1, true))
    end
  end, debug.traceback)

  integration.cleanup()
  client.stop()
  assert(ok, failure)
end)

return T
