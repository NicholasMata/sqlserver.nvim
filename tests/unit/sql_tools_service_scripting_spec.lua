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
  local cancelled
  local client = fake_client({ operationId = "missing" })
  local request = client.request
  client.request = function(self, method, params, callback)
    if method == "scripting/scriptCancel" then
      cancelled = params.operationId
      callback(nil, {})
      return true
    end
    return request(self, method, params, callback)
  end
  local valid, err = pcall(scripting.script_async, client, {}, 10)
  assert(not valid)
  assert(err:find("did not complete", 1, true))
  assert(cancelled == "missing")
end)

T["Scripting should cancel the SQL Tools Service operation"] = require("tests.helpers").async(function()
  local client = { handlers = {}, requested = {} }
  client.request = function(_, method, params, callback)
    client.requested[#client.requested + 1] = { method = method, params = params }
    if method == "scripting/script" then
      vim.schedule(function()
        callback(nil, { operationId = "cancel-me" })
      end)
    elseif method == "scripting/scriptCancel" then
      callback(nil, {})
    end
    return true
  end
  local cancel
  local result
  local workflow = coroutine.create(function()
    result = {
      pcall(scripting.script_async, client, {}, 1000, {
        on_operation = function(_, cancel_operation)
          cancel = cancel_operation
        end,
      }),
    }
  end)
  assert(coroutine.resume(workflow))
  assert(vim.wait(1000, function()
    return cancel ~= nil
  end))
  assert(cancel())
  assert(client.requested[2].method == "scripting/scriptCancel")
  assert(client.requested[2].params.operationId == "cancel-me")
  client.handlers["scripting/scriptComplete"](nil, {
    operationId = "cancel-me",
    canceled = true,
  })
  assert(vim.wait(1000, function()
    return coroutine.status(workflow) == "dead"
  end))
  assert(result[1] == false and result[2].code == "cancelled")
end)

T["Scripting should report plan and object progress"] = require("tests.helpers").async(function()
  local progress = {}
  local response = { operationId = "progress", script = "CREATE TABLE dbo.Car (ID int)" }
  local client = fake_client(response, {
    operationId = "progress",
    success = true,
    hasError = false,
  }, nil, true)
  local request = client.request
  client.request = function(self, method, params, callback)
    return request(self, method, params, function(err, result)
      callback(err, result)
      vim.schedule(function()
        client.handlers["scripting/scriptPlanNotification"](nil, { operationId = "progress", count = 2 })
        client.handlers["scripting/scriptProgressNotification"](nil, {
          operationId = "progress",
          completedCount = 1,
          totalCount = 2,
          status = "Progress",
        })
      end)
    end)
  end
  scripting.script_async(client, {}, 1000, {
    on_progress = function(event)
      progress[#progress + 1] = event
    end,
  })
  assert(#progress == 2)
  assert(progress[1].count == 2)
  assert(progress[2].completedCount == 1 and progress[2].status == "Progress")
end)

return T
