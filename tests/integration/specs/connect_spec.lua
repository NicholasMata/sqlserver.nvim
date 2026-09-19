local test_utils = require("tests.helpers.integration")
local sqlserver = require("sqlserver")
local workspace_registry = require("sqlserver.workspace.registry")

local T = MiniTest.new_set()

T["Connect to database should work"] = require("tests.helpers").async(function()
  local bufnr = test_utils.new_query_buffer()
  local connection = test_utils.connect(bufnr)
  assert(connection.database == vim.env.DbDatabase)
  assert(connection.username == vim.env.DbUser)
  local connection_info = workspace_registry.get(bufnr).get_connection_info()
  assert(connection_info.username == vim.env.DbUser)
  assert(connection_info.database == vim.env.DbDatabase)
  assert(connection_info.connection_id and connection_info.connection_id ~= "")
  assert(connection_info.server_connection_id and connection_info.server_connection_id ~= "")
  assert(connection_info.server_info.version and connection_info.server_info.version ~= "")
  assert(connection_info.server_info.edition and connection_info.server_info.edition ~= "")
  assert(test_utils.get_sql_client(bufnr), "No SQL Tools Service client attached")
end)

T["Cancelling connection selection should stop cleanly"] = require("tests.helpers").async(function()
  local bufnr = test_utils.new_query_buffer()
  local notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end
  test_utils.ui_select_fake(nil)

  sqlserver.connect()
  local cancellation_reported = vim.wait(5000, function()
    return vim.iter(notifications):any(function(notification)
      return notification.message == "No connection chosen"
    end)
  end, 10)
  vim.wait(100, function()
    return false
  end, 10)
  vim.notify = original_notify

  assert(cancellation_reported, "Connection cancellation was not reported")
  assert(not vim.iter(notifications):any(function(notification)
    return notification.level == vim.log.levels.ERROR
  end), "Connection cancellation produced an error: " .. vim.inspect(notifications))
  assert(require("sqlserver").current_connection(bufnr) == nil)
end)

return T
