local M = {}

function M.select(context, callback)
  vim.ui.select(context.items, {
    prompt = context.title,
    format_item = function(item)
      return table.concat({ item.icon or "", item.icon and " " or "", item.path or "", item.label })
    end,
  }, callback)
end

return M
