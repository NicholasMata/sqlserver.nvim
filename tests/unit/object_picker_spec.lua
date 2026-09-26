local select_picker = require("sqlserver.objects.ui.select")
local snacks_picker = require("sqlserver.objects.ui.snacks")

local T = MiniTest.new_set()

for _, title in ipairs({ "Find Query", "Object Definition" }) do
  T[title .. " uses the Neovim UI provider"] = function()
    local previous_select = vim.ui.select
    local context = { title = title, items = { { label = "Person", path = "Tables/", icon = "T" } } }
    local selected
    vim.ui.select = function(items, opts, callback)
      assert(items == context.items and opts.prompt == title)
      assert(opts.format_item(items[1]) == "T Tables/Person")
      callback(items[1])
    end

    select_picker.select(context, function(item)
      selected = item
    end)
    vim.ui.select = previous_select
    assert(selected == context.items[1])
  end
end

for _, title in ipairs({ "Find Query", "Object Definition" }) do
  T[title .. " provides searchable items to Snacks"] = function()
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
    snacks_picker.select({ title = title, items = { item } }, function(value)
      selected = value
    end)
    assert(opts.title == title)
    assert(opts.items[1].text == "Person Tables/")
    local action_format = opts.format({ label = "Show definition" })
    assert(action_format[1][1] == "" and action_format[5][1] == "")
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
end

return T
