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

T["UI options should normalize object picker providers"] = function()
  local previous_loaded = package.loaded.snacks
  local previous_preload = package.preload.snacks
  package.loaded.snacks = nil
  package.preload.snacks = function()
    return { picker = {} }
  end
  assert(
    ui_options.normalize_object_picker("auto") == require("sqlserver.objects.ui.snacks").select,
    "Auto should prefer the dedicated Snacks adapter"
  )
  package.loaded.snacks = nil
  package.preload.snacks = function()
    error("unavailable")
  end
  assert(
    ui_options.normalize_object_picker("auto") == require("sqlserver.objects.ui.select").select,
    "Auto should fall back to vim.ui.select"
  )
  package.loaded.snacks = previous_loaded
  package.preload.snacks = previous_preload

  assert(type(ui_options.normalize_object_picker("select")) == "function")
  assert(type(ui_options.normalize_object_picker("snacks")) == "function")

  local custom = function() end
  assert(ui_options.normalize_object_picker(custom) == custom)

  local ok, err = pcall(ui_options.normalize_object_picker, "telescope")
  assert(not ok and err:find("'auto'", 1, true))
end

return T
