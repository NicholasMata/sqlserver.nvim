local picker = require("sqlserver.objects.ui.picker")
local adapter = require("sqlserver.adapters.sql_tools_service.object_explorer")

local T = MiniTest.new_set()

local function client_for(root, expansions)
  local client = { handlers = {}, expanded = {}, closed = 0 }
  function client:request(method, params, callback)
    if method == "objectexplorer/createsession" then
      vim.schedule(function()
        callback(nil, {})
        vim.schedule(function()
          self.handlers["objectexplorer/sessioncreated"](nil, { sessionId = "session", rootNode = root })
        end)
      end)
    elseif method == "objectexplorer/expand" then
      self.expanded[#self.expanded + 1] = params.nodePath
      vim.schedule(function()
        callback(nil, {})
        vim.schedule(function()
          self.handlers["objectexplorer/expandCompleted"](nil, {
            sessionId = "session",
            nodes = assert(expansions[params.nodePath]),
          })
        end)
      end)
    elseif method == "objectexplorer/closesession" then
      self.closed = self.closed + 1
      callback(nil, {})
    end
  end
  return client
end

local connection = { server = "localhost", database = "TestDb", user = "sa" }

T["Database roots expand only the service root"] = require("tests.helpers").async(function()
  local root = { nodePath = "server/TestDb", label = "TestDb", objectType = "Database", isLeaf = false }
  local client = client_for(root, {
    [root.nodePath] = {
      { nodePath = root.nodePath .. "/Tables", label = "Tables", objectType = "Tables", isLeaf = false },
      { nodePath = root.nodePath .. "/Security", label = "Security", objectType = "Security", isLeaf = false },
    },
    [root.nodePath .. "/Tables"] = {
      { nodePath = root.nodePath .. "/Tables/dbo.Person", label = "dbo.Person", objectType = "Table", isLeaf = false },
    },
    [root.nodePath .. "/Security"] = {},
  })

  local session, tree = picker.open_explorer_async(client, connection)
  assert(tree.nodePath == root.nodePath and tree.label == "TestDb")
  assert(#tree.children == 2 and tree.children[1].label == "Tables")
  assert(tree.children[1].children == nil and not tree.children[1].loaded)
  assert(vim.deep_equal(client.expanded, { root.nodePath }))
  assert(session.close() and client.closed == 1)
end)

T["Server roots remain unexpanded"] = require("tests.helpers").async(function()
  local root = { nodePath = "server", label = "localhost", objectType = "Server", isLeaf = false }
  local client = client_for(root, {})
  local session, tree = picker.open_explorer_async(client, connection)
  assert(tree.nodePath == "server" and tree.children == nil and not tree.expanded)
  assert(#client.expanded == 0)
  session.close()
end)

T["Object Explorer serializes concurrent expansions"] = require("tests.helpers").async(function()
  local client = { handlers = {}, requested = {} }
  function client:request(method, params, callback)
    if method == "objectexplorer/createsession" then
      vim.schedule(function()
        callback(nil, {})
        vim.schedule(function()
          self.handlers["objectexplorer/sessioncreated"](nil, {
            sessionId = "queued",
            rootNode = { nodePath = "database", label = "TestDb", objectType = "Database", isLeaf = false },
          })
        end)
      end)
    elseif method == "objectexplorer/expand" then
      self.requested[#self.requested + 1] = params.nodePath
      vim.schedule(function()
        callback(nil, {})
      end)
    elseif method == "objectexplorer/closesession" then
      callback(nil, {})
    end
  end

  local session = adapter.open_async(client, connection)
  local results = {}
  local function request(path)
    local co = coroutine.create(function()
      local ok, value = pcall(session.expand_async, path)
      results[path] = { ok = ok, value = value }
    end)
    assert(coroutine.resume(co))
  end
  request("database/Tables")
  request("database/Views")
  assert(vim.wait(1000, function()
    return client.handlers["objectexplorer/expandCompleted"] ~= nil
  end, 10))
  assert(vim.deep_equal(client.requested, { "database/Tables" }))

  client.handlers["objectexplorer/expandCompleted"](nil, { sessionId = "queued", nodes = { { label = "table" } } })
  assert(vim.wait(1000, function()
    return results["database/Tables"] and #client.requested == 2 and session.cancel_active ~= nil
  end, 10))
  assert(vim.deep_equal(client.requested, { "database/Tables", "database/Views" }))

  client.handlers["objectexplorer/expandCompleted"](nil, { sessionId = "queued", nodes = { { label = "view" } } })
  assert(vim.wait(1000, function()
    return results["database/Views"] ~= nil
  end, 10))
  assert(results["database/Tables"].ok and results["database/Tables"].value[1].label == "table")
  assert(results["database/Views"].ok and results["database/Views"].value[1].label == "view")
end)

T["Closing Object Explorer rejects active and queued expansions"] = require("tests.helpers").async(function()
  local client = { handlers = {}, requested = {} }
  function client:request(method, params, callback)
    if method == "objectexplorer/createsession" then
      vim.schedule(function()
        callback(nil, {})
        vim.schedule(function()
          self.handlers["objectexplorer/sessioncreated"](nil, {
            sessionId = "closing",
            rootNode = { nodePath = "server", label = "localhost", objectType = "Server", isLeaf = false },
          })
        end)
      end)
    elseif method == "objectexplorer/expand" then
      self.requested[#self.requested + 1] = params.nodePath
      vim.schedule(function()
        callback(nil, {})
      end)
    elseif method == "objectexplorer/closesession" then
      callback(nil, {})
    end
  end
  local session = adapter.open_async(client, connection)
  local errors = {}
  for _, path in ipairs({ "server/Databases", "server/Security" }) do
    assert(coroutine.resume(coroutine.create(function()
      local ok, err = pcall(session.expand_async, path)
      assert(not ok)
      errors[path] = tostring(err)
    end)))
  end
  assert(vim.wait(1000, function()
    return session.cancel_active ~= nil
  end, 10))
  session.close()
  assert(vim.wait(1000, function()
    return errors["server/Databases"] and errors["server/Security"]
  end, 10))
  assert(errors["server/Databases"]:find("closed", 1, true))
  assert(errors["server/Security"]:find("closed", 1, true))
  assert(vim.deep_equal(client.requested, { "server/Databases" }))
end)

return T
