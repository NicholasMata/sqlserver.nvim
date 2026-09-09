local M = {}

local configured_suffixes = { "s", "n", "p", "d", "y" }

function M.attach(bufnr)
  local view = require("sqlserver.results.ui.view")
  local mappings = {
    { "]r", view.next_result, "Next SQL result" },
    { "[r", view.previous_result, "Previous SQL result" },
    { "]c", view.next_column, "Next SQL result column" },
    { "[c", view.previous_column, "Previous SQL result column" },
    { "K", view.show_column_info, "Show SQL result column type" },
  }
  for _, mapping in ipairs(mappings) do
    vim.keymap.set("n", mapping[1], mapping[2], { buffer = bufnr, desc = mapping[3] })
  end
end

local function attach_configured(prefix, handlers, bufnr)
  local previous_prefix = vim.b[bufnr].sqlserver_result_keymap_prefix
  if previous_prefix and previous_prefix ~= prefix then
    for _, suffix in ipairs(configured_suffixes) do
      pcall(vim.keymap.del, "n", previous_prefix .. suffix, { buffer = bufnr })
    end
    pcall(vim.keymap.del, "x", previous_prefix .. "s", { buffer = bufnr })
    pcall(vim.keymap.del, "x", previous_prefix .. "y", { buffer = bufnr })
  end
  -- Remove the pre-1.0 raw-cell mapping when reconfiguring an existing buffer.
  pcall(vim.keymap.del, "n", prefix .. "y", { buffer = bufnr })

  local mappings = {
    { "s", handlers.export_query_results, "Export SQL result" },
    { "n", handlers.next_execution, "Next SQL execution" },
    { "p", handlers.previous_execution, "Previous SQL execution" },
    { "d", handlers.remove_result, "Remove SQL result" },
  }
  for _, mapping in ipairs(mappings) do
    vim.keymap.set("n", prefix .. mapping[1], mapping[2], { buffer = bufnr, desc = mapping[3] })
  end
  vim.keymap.set("x", prefix .. "s", function()
    handlers.export_query_results({ selection = true })
  end, { buffer = bufnr, desc = "Export selected SQL result cells" })
  vim.keymap.set("x", prefix .. "y", handlers.copy_result_selection, {
    buffer = bufnr,
    desc = "Copy selected SQL result cells as HTML",
  })
  vim.b[bufnr].sqlserver_result_keymap_prefix = prefix
end

function M.setup(prefix, handlers)
  if not prefix then
    return
  end
  local group = vim.api.nvim_create_augroup("sqlserver-result-keymaps", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "sqlserver-result",
    callback = function(args)
      attach_configured(prefix, handlers, args.buf)
    end,
  })
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "sqlserver-result" then
      attach_configured(prefix, handlers, bufnr)
    end
  end
end

function M.which_key_items(handlers)
  return {
    { "s", handlers.export_query_results, desc = "Export Query Result", icon = { icon = "", color = "green" } },
    { "n", handlers.next_execution, desc = "Next Execution" },
    { "p", handlers.previous_execution, desc = "Previous Execution" },
    { "d", handlers.remove_result, desc = "Remove Result", icon = { icon = "󰆴", color = "red" } },
  }
end

function M.which_key_visual_items(handlers)
  return {
    {
      "s",
      function()
        handlers.export_query_results({ selection = true })
      end,
      desc = "Export Selected Cells",
      icon = { icon = "", color = "green" },
    },
    {
      "y",
      handlers.copy_result_selection,
      desc = "Copy Selected Cells as HTML",
    },
  }
end

return M
