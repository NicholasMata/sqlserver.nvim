local ui_options = require("sqlserver.config.ui")

local T = MiniTest.new_set()

T["UI options should normalize winbar configuration"] = require("tests.helpers").async(function()
  local defaults = ui_options.normalize_winbar(true)
  assert(defaults.enabled and defaults.layout == "split" and defaults.alignment == "right")

  local disabled = ui_options.normalize_winbar(false)
  assert(not disabled.enabled and disabled.layout == "split")

  local configured = ui_options.normalize_winbar({ layout = "compact", alignment = "left" })
  assert(configured.enabled and configured.layout == "compact" and configured.alignment == "left")

  local ok, err = pcall(ui_options.normalize_winbar, { alignment = "diagonal" })
  assert(not ok and err:find("left", 1, true))
  ok, err = pcall(ui_options.normalize_winbar, { layout = "stacked" })
  assert(not ok and err:find("split", 1, true))
end)

return T
