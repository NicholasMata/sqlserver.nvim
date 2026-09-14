local picker = require("sqlserver.objects.ui.picker")

local T = MiniTest.new_set()

local function client_for(opts)
  opts = opts or {}
  local client = { handlers = {}, closed = 0, expanded = {} }
  function client:request(method, params, callback)
    if method == "objectexplorer/createsession" then
      vim.schedule(function()
        callback(opts.create_error, {})
        if not opts.create_error then
          vim.schedule(function()
            self.handlers["objectexplorer/sessioncreated"](nil, opts.session, {})
          end)
        end
      end)
    elseif method == "objectexplorer/expand" then
      self.expanded[#self.expanded + 1] = params.nodePath
      local response = assert(opts.expansions[params.nodePath], "Unexpected expansion: " .. params.nodePath)
      vim.schedule(function()
        callback(response.request_error, {})
        if not response.request_error then
          vim.schedule(function()
            self.handlers["objectexplorer/expandCompleted"](response.error, response.result, {})
          end)
        end
      end)
    elseif method == "objectexplorer/closesession" then
      self.closed = self.closed + 1
      vim.schedule(function()
        callback(nil, {})
      end)
    end
  end
  return client
end

local function load(client, target)
  return picker.list_children_async(client, {
    server = "localhost",
    database = "TestDb",
    user = "sa",
  }, target)
end

T["Object Explorer child loading returns normalized children"] = require("tests.helpers").async(function()
  local target = "server/Databases/TestDb/Tables/dbo.Person"
  local client = client_for({
    session = {
      sessionId = "session-1",
      rootNode = { objectType = "Database", nodePath = target },
    },
    expansions = {
      [target] = {
        result = {
          sessionId = "session-1",
          nodes = {
            { nodePath = target .. "/Columns", label = "Columns", objectType = "Folder", isLeaf = false },
            { nodePath = target .. "/Triggers", label = "Triggers", nodeType = "Folder", isLeaf = true },
          },
        },
      },
    },
  })

  local children = load(client, target)
  assert(vim.deep_equal(children, {
    { id = target .. "/Columns", label = "Columns", type = "Folder", expandable = true },
    { id = target .. "/Triggers", label = "Triggers", type = "Folder", expandable = false },
  }))
  assert(vim.deep_equal(client.expanded, { target }))
  assert(client.closed == 1)
end)

T["Object Explorer child loading traverses a system database session"] = require("tests.helpers").async(function()
  local root = "server"
  local database = root .. "/Databases/System Databases/TestDb"
  local target = database .. "/Tables/dbo.Person"
  local client = client_for({
    session = { sessionId = "session-2", rootNode = { objectType = "Server", nodePath = root } },
    expansions = {
      [root] = { result = { sessionId = "session-2", nodes = { { nodePath = database } } } },
      [database] = { result = { sessionId = "session-2", nodes = { { nodePath = database .. "/Tables" } } } },
      [database .. "/Tables"] = {
        result = { sessionId = "session-2", nodes = { { nodePath = target } } },
      },
      [target] = { result = { sessionId = "session-2", nodes = {} } },
    },
  })

  assert(vim.deep_equal(load(client, target), {}))
  assert(vim.deep_equal(client.expanded, { root, database, database .. "/Tables", target }))
  assert(client.closed == 1)
end)

T["Object Explorer child loading reports protocol failures"] = require("tests.helpers").async(function()
  local target = "server/database/table"
  local cases = {
    {
      expected = "could not start object exploration",
      client = client_for({ create_error = { message = "unavailable" } }),
    },
    {
      expected = "invalid object explorer session",
      client = client_for({ session = {}, expansions = {} }),
    },
    {
      expected = "expand failed",
      client = client_for({
        session = { sessionId = "request-error", rootNode = { objectType = "Database", nodePath = target } },
        expansions = { [target] = { request_error = { message = "expand failed" } } },
      }),
    },
    {
      expected = "invalid object expansion",
      client = client_for({
        session = { sessionId = "invalid", rootNode = { objectType = "Database", nodePath = target } },
        expansions = { [target] = { result = { sessionId = "invalid" } } },
      }),
    },
    {
      expected = "could not locate the selected object",
      client = client_for({
        session = { sessionId = "missing", rootNode = { objectType = "Database", nodePath = "server" } },
        expansions = { server = { result = { sessionId = "missing", nodes = {} } } },
      }),
    },
  }

  for _, case in ipairs(cases) do
    local ok, err = pcall(load, case.client, target)
    assert(not ok)
    assert(tostring(err):find(case.expected, 1, true), tostring(err))
  end
end)

T["Object Explorer child loading has a bounded session timeout"] = require("tests.helpers").async(function()
  local client = { handlers = {} }
  function client:request(method, _, callback)
    if method == "objectexplorer/createsession" then
      vim.schedule(function()
        callback(nil, {})
      end)
    elseif method == "objectexplorer/closesession" then
      vim.schedule(function()
        callback(nil, {})
      end)
    end
  end

  picker.setup({ object_explorer = 1 })
  local ok, err = pcall(picker.list_children_async, client, {
    server = "localhost",
    database = "TestDb",
  }, "server/database/Tables/Person")
  picker.setup({ object_explorer = 10000 })

  assert(not ok)
  assert(tostring(err):find("SQL Server object exploration timed out", 1, true))
end)

return T
