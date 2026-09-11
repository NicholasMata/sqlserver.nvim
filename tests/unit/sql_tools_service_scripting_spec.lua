local scripting = require("sqlserver.adapters.sql_tools_service.scripting")

local function fake_client(response, completion, request_error, completion_after_response)
  local client = { handlers = {} }
  client.request = function(_, method, _, callback)
    assert(method == "scripting/script")
    vim.schedule(function()
      if completion and not completion_after_response then
        client.handlers["scripting/scriptComplete"](nil, completion)
      end
      callback(request_error, response)
      if completion and completion_after_response then
        vim.schedule(function()
          client.handlers["scripting/scriptComplete"](nil, completion)
        end)
      end
    end)
  end
  return client
end

local T = MiniTest.new_set()

T["Scripting should correlate completion sent before the response"] = require("tests.helpers").async(function()
  local response = { operationId = "before", script = "CREATE TABLE dbo.Car (ID int)" }
  local result = scripting.script_async(
    fake_client(response, {
      operationId = "before",
      success = true,
      hasError = false,
    }),
    {},
    100
  )
  assert(result == response)
end)

T["Scripting should wait for completion sent after the response"] = require("tests.helpers").async(function()
  local response = { operationId = "after", script = "CREATE VIEW dbo.CarView AS SELECT 1" }
  local result = scripting.script_async(
    fake_client(response, {
      operationId = "after",
      success = true,
      hasError = false,
    }, nil, true),
    {},
    100
  )
  assert(result == response)
end)

T["Scripting should surface completion errors"] = require("tests.helpers").async(function()
  local response = { operationId = "failed" }
  local valid, err = pcall(
    scripting.script_async,
    fake_client(response, {
      operationId = "failed",
      success = false,
      hasError = true,
      errorMessage = "An error occurred while scripting the objects.",
    }),
    {},
    100
  )
  assert(not valid)
  assert(err:find("An error occurred while scripting the objects", 1, true))
end)

T["Scripting should reject missing completion notifications"] = require("tests.helpers").async(function()
  local valid, err = pcall(scripting.script_async, fake_client({ operationId = "missing" }), {}, 10)
  assert(not valid)
  assert(err:find("did not complete", 1, true))
end)

return T
