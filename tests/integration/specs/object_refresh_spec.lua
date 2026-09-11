local sqlserver = require("sqlserver")
local integration = require("tests.helpers.integration")
local utils = require("sqlserver.utils")

local T = MiniTest.new_set()

local function execute(bufnr, text)
  local execution = integration.await(function(callback)
    sqlserver.execute({ bufnr = bufnr, text = text }, callback)
  end)
  execution.dispose()
end

local function connect_test_database(bufnr)
  integration.await(function(callback)
    sqlserver.disconnect(bufnr, callback)
  end)
  integration.connect(bufnr, "TestDbB")
end

local function list(bufnr, name)
  return integration.await(function(callback)
    sqlserver.list_objects({ bufnr = bufnr, name = name, schema = "dbo", type = "Table" }, callback)
  end)
end

local function refresh(bufnr)
  local result = integration.await(function(callback)
    sqlserver.refresh_objects(bufnr, callback)
  end)
  assert(result and result.cancelled == false, "Object refresh did not complete")
  return result
end

local function script_definition(bufnr, name)
  local result
  local failure
  sqlserver.script_object(
    { bufnr = bufnr, name = name, schema = "dbo", type = "Table", intent = "definition" },
    function(value, err)
      result = value
      failure = err
    end
  )
  assert(
    vim.wait(30000, function()
      return result ~= nil or failure ~= nil
    end, 10),
    "Object scripting did not complete"
  )
  return result, failure
end

T["Refresh replaces created and deleted object metadata"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  local name = "RefreshCacheProbe"
  connect_test_database(bufnr)

  execute(bufnr, "DROP TABLE IF EXISTS dbo." .. name .. ";")
  refresh(bufnr)
  assert(#list(bufnr, name) == 0)

  local ok, failure = xpcall(function()
    execute(bufnr, "CREATE TABLE dbo." .. name .. " (ID int NOT NULL);")
    assert(#list(bufnr, name) == 0, "Object cache changed without an explicit refresh")

    refresh(bufnr)
    assert(#list(bufnr, name) == 1, "Created table was absent after refreshing object metadata")

    execute(bufnr, "DROP TABLE dbo." .. name .. ";")
    assert(#list(bufnr, name) == 1, "Object cache changed without an explicit refresh")

    refresh(bufnr)
    assert(#list(bufnr, name) == 0, "Dropped table remained after refreshing object metadata")
  end, debug.traceback)

  execute(bufnr, "DROP TABLE IF EXISTS dbo." .. name .. ";")
  assert(ok, failure)
end, 120000)

T["Object caches remain isolated by database"] = require("tests.helpers").async(function()
  local database_b_bufnr = vim.api.nvim_get_current_buf()
  local name = "RefreshIsolationProbe"
  connect_test_database(database_b_bufnr)
  execute(database_b_bufnr, "DROP TABLE IF EXISTS dbo." .. name .. "; CREATE TABLE dbo." .. name .. " (ID int);")

  local database_a_bufnr = integration.new_query_buffer()
  integration.connect(database_a_bufnr, "TestDbA")

  local ok, failure = xpcall(function()
    refresh(database_b_bufnr)
    refresh(database_a_bufnr)
    assert(#list(database_b_bufnr, name) == 1)
    assert(#list(database_a_bufnr, name) == 0, "TestDbB metadata leaked into the TestDbA cache")
  end, debug.traceback)

  execute(database_b_bufnr, "DROP TABLE IF EXISTS dbo." .. name .. ";")
  assert(ok, failure)
end, 120000)

T["Refresh applies object permission changes"] = require("tests.helpers").async(function()
  local admin_bufnr = vim.api.nvim_get_current_buf()
  connect_test_database(admin_bufnr)
  local restricted_bufnr = integration.new_query_buffer()
  integration.connect_with(restricted_bufnr, {
    database = "TestDbB",
    user = "sqlserver_nvim_restricted",
    password = "Restricted_Password_123",
  })

  local function set_permissions(sql)
    execute(admin_bufnr, sql .. " ON OBJECT::dbo.Car TO sqlserver_nvim_restricted;")
  end

  local function restore_permissions()
    set_permissions("GRANT SELECT")
    set_permissions("GRANT VIEW DEFINITION")
  end

  restore_permissions()
  refresh(restricted_bufnr)
  local ok, failure = xpcall(function()
    assert(#list(restricted_bufnr, "Car") == 1)
    local definition, script_error = script_definition(restricted_bufnr, "Car")
    assert(definition and not script_error)

    set_permissions("DENY SELECT")
    set_permissions("DENY VIEW DEFINITION")
    refresh(restricted_bufnr)
    assert(#list(restricted_bufnr, "Car") == 0, "Revoked object remained visible after refresh")

    set_permissions("GRANT SELECT")
    set_permissions("GRANT VIEW DEFINITION")
    refresh(restricted_bufnr)
    assert(#list(restricted_bufnr, "Car") == 1, "Granted object remained hidden after refresh")
    definition, script_error = script_definition(restricted_bufnr, "Car")
    assert(definition and not script_error, "Granted definition remained inaccessible after refresh")
  end, debug.traceback)

  restore_permissions()
  assert(ok, failure)
end, 120000)

T["A newer refresh cancels and replaces an older refresh"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  connect_test_database(bufnr)
  local name = "RefreshOverlapProbe"
  execute(bufnr, "DROP TABLE IF EXISTS dbo." .. name .. "; CREATE TABLE dbo." .. name .. " (ID int);")

  local results = {}
  sqlserver.refresh_objects(bufnr, function(result, err)
    table.insert(results, { result = result, error = err })
  end)
  sqlserver.refresh_objects(bufnr, function(result, err)
    table.insert(results, { result = result, error = err })
  end)

  local ok, failure = xpcall(function()
    assert(
      vim.wait(30000, function()
        return #results == 2
      end, 10),
      "Overlapping refreshes did not both complete"
    )
    assert(not results[1].error and not results[2].error)
    assert(
      vim.iter(results):any(function(item)
        return item.result and item.result.cancelled == true
      end),
      "The superseded refresh was not cancelled"
    )
    assert(
      vim.iter(results):any(function(item)
        return item.result and item.result.cancelled == false
      end),
      "The newest refresh did not complete"
    )
    assert(#list(bufnr, name) == 1, "The newest refresh did not replace the cache")
  end, debug.traceback)

  execute(bufnr, "DROP TABLE IF EXISTS dbo." .. name .. ";")
  assert(ok, failure)
end, 120000)

T["A failed refresh retains the previous object cache"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  connect_test_database(bufnr)
  local picker = require("sqlserver.objects.ui.picker")
  assert(#list(bufnr, "Car") == 1)

  picker.setup({ object_explorer = 1 })
  local _, refresh_error
  sqlserver.refresh_objects(bufnr, function(_, err)
    refresh_error = err
  end)
  assert(
    vim.wait(30000, function()
      return refresh_error ~= nil
    end, 10),
    "Deliberately timed-out refresh did not fail"
  )
  picker.setup({ object_explorer = 10000 })

  assert(#list(bufnr, "Car") == 1, "A failed refresh discarded the previous object cache")
end, 120000)

T["Refresh cache updates objects and IntelliSense"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  connect_test_database(bufnr)
  local client = integration.get_sql_client(bufnr)
  local name = "RefreshIntelliSenseProbe"
  execute(bufnr, "DROP TABLE IF EXISTS dbo." .. name .. "; CREATE TABLE dbo." .. name .. " (ID int);")

  local ready
  local ready_error
  integration.wait_for_all_async({
    function()
      ready, ready_error = utils.wait_for_notification_async(bufnr, client, "textDocument/intelliSenseReady", 30000)
    end,
    function()
      sqlserver.refresh_cache()
    end,
  })

  local ok, failure = xpcall(function()
    assert(ready and not ready_error, ready_error and ready_error.message)
    assert(
      vim.wait(30000, function()
        return #list(bufnr, name) == 1
      end, 10),
      "refresh_cache did not replace object metadata"
    )
  end, debug.traceback)

  execute(bufnr, "DROP TABLE IF EXISTS dbo." .. name .. ";")
  assert(ok, failure)
end, 120000)

return T
