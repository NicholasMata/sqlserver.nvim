local M = {}

---@param owner_uri string
function M.create(owner_uri)
  local target
  local proxy = { owner_uri = owner_uri }

  function proxy.bind(backend)
    assert(not target, "SQL Tools Service backend is already attached")
    target = backend
  end

  function proxy.is_bound()
    return target ~= nil
  end

  return setmetatable(proxy, {
    __index = function(_, key)
      if not target then
        error("SQL Tools Service is not ready", 0)
      end
      return target[key]
    end,
  })
end

return M
