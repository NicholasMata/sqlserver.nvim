local select_picker = require("sqlserver.objects.ui.select")
local snacks_picker = require("sqlserver.objects.ui.snacks")

local T = MiniTest.new_set()

T["Select object picker uses the Neovim UI provider"] = function()
  local previous_select = vim.ui.select
  local context = { title = "Objects", items = { { label = "Person", path = "Tables/", icon = "T" } } }
  local selected
  vim.ui.select = function(items, opts, callback)
    assert(items == context.items and opts.prompt == "Objects")
    assert(opts.format_item(items[1]) == "T Tables/Person")
    callback(items[1])
  end

  select_picker.select(context, function(item)
    selected = item
  end)
  vim.ui.select = previous_select
  assert(selected == context.items[1])
end

T["Snacks object picker completes through its close hook"] = function()
  local previous_snacks = package.loaded.snacks
  local opts
  package.loaded.snacks = {
    picker = {
      pick = function(value)
        opts = value
      end,
    },
  }
  local item = { label = "Person", path = "Tables/", icon = "T" }
  local selected
  snacks_picker.select({ title = "Objects", items = { item } }, function(value)
    selected = value
  end)
  local fake_picker = {
    close = function()
      opts.on_close()
    end,
  }
  opts.confirm(fake_picker, item)
  opts.on_close()
  package.loaded.snacks = previous_snacks
  assert(selected == item)
end

return T
