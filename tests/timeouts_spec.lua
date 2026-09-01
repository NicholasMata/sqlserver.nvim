local timeouts = require("sqlserver.core.timeouts")

return {
  test_name = "Operational timeouts should normalize public configuration",
  run_test_async = function()
    local defaults = timeouts.normalize()
    assert(defaults.lsp_attach == 10000)
    assert(defaults.connection == 10000)
    assert(defaults.object_explorer == 10000)
    assert(defaults.query == false)

    local configured = timeouts.normalize({ connection = 25000, query = 60000 })
    assert(configured.connection == 25000 and configured.query == 60000)
    assert(configured.lsp_attach == 10000)

    local disabled = timeouts.normalize({ connection = false, object_explorer = false })
    assert(disabled.connection == false and disabled.object_explorer == false)

    local valid, err = pcall(timeouts.normalize, { query = 0 })
    assert(not valid and err:find("positive number", 1, true))
    valid, err = pcall(timeouts.normalize, { unknown = 1000 })
    assert(not valid and err:find("Unknown timeout option", 1, true))
  end,
}
