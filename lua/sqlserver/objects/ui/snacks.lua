local M = {}

function M.select(context, callback)
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    error("ui.object_picker is 'snacks', but snacks.nvim is not available", 0)
  end

  local selected
  local completed = false
  local function complete()
    if completed then
      return
    end
    completed = true
    callback(selected)
  end

  snacks.picker.pick({
    title = context.title,
    layout = "select",
    items = context.items,
    format = function(item)
      return {
        { item.icon, "SnacksPickerIcon" },
        { " " },
        { item.label },
        { " " },
        { item.path, "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      selected = item
      picker:close()
    end,
    on_close = complete,
  })
end

return M
