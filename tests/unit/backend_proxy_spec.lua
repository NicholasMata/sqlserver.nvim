local backend_proxy = require("sqlserver.adapters.sql_tools_service.backend_proxy")

local T = MiniTest.new_set()

T["SQL Tools Service backend proxy waits for attachment"] = function()
  local proxy = backend_proxy.create("file:///pending.sql")
  assert(proxy.owner_uri == "file:///pending.sql")
  assert(not proxy.is_bound())

  local ready, err = pcall(function()
    return proxy.client
  end)
  assert(not ready and err == "SQL Tools Service is not ready")

  local client = {}
  proxy.bind({
    client = client,
    connect_async = function()
      return "connected"
    end,
  })
  assert(proxy.is_bound())
  assert(proxy.client == client)
  assert(proxy.connect_async() == "connected")

  local rebound = pcall(proxy.bind, {})
  assert(not rebound)
end

return T
