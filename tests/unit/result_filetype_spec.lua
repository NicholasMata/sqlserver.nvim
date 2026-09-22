local T = MiniTest.new_set()

T["Result filetype should install buffer-local mappings"] = require("tests.helpers").async(function()
  local original_list = vim.wo.list
  local opened = false
  local shown = require("sqlserver.results.ui.view").show({}, {
    open_results_in = function()
      opened = true
    end,
  })
  assert(not shown and not opened, "Empty result collections should not invoke the result opener")

  local result_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(result_buffer)
  vim.wo.list = true
  vim.api.nvim_set_option_value("filetype", "sqlserver-result", { buf = result_buffer })
  assert(not vim.wo.list, "Result windows should hide alignment padding markers")

  local mappings = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(result_buffer, "n")) do
    mappings[mapping.lhs] = mapping.desc
  end

  assert(mappings["]r"] == "Next SQL result")
  assert(mappings["[r"] == "Previous SQL result")
  assert(mappings["]c"] == "Next SQL result column")
  assert(mappings["[c"] == "Previous SQL result column")
  assert(mappings["K"] == "Show SQL result column type")
  assert(mappings["h"] == "Previous SQL result cell")
  assert(mappings["j"] == "Next SQL result row")
  assert(mappings["k"] == "Previous SQL result row")
  assert(mappings["l"] == "Next SQL result cell")

  local visual_cell_mappings = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(result_buffer, "x")) do
    visual_cell_mappings[mapping.lhs] = mapping.desc
  end
  assert(visual_cell_mappings["h"] == "Previous SQL result cell")
  assert(visual_cell_mappings["j"] == "Next SQL result row")
  assert(visual_cell_mappings["k"] == "Previous SQL result row")
  assert(visual_cell_mappings["l"] == "Next SQL result cell")

  local noop = function() end
  local handlers = setmetatable({ export_query_results = noop }, {
    __index = function()
      return noop
    end,
  })
  require("sqlserver.ui.keymaps").set_keymaps("<leader>d", handlers)
  assert(vim.fn.maparg("<leader>di", "n", false, true).desc == "Connection Information")

  local prefixed_mappings = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(result_buffer, "n")) do
    prefixed_mappings[mapping.desc] = true
  end
  assert(prefixed_mappings["Export SQL result"], "The configured prefix should add a result-local export mapping")
  assert(prefixed_mappings["Next SQL execution"])
  assert(prefixed_mappings["Previous SQL execution"])
  assert(prefixed_mappings["Remove SQL result"])
  assert(not prefixed_mappings["Copy raw SQL result cell"])
  local visual_mappings = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(result_buffer, "x")) do
    visual_mappings[mapping.desc] = true
  end
  assert(visual_mappings["Export selected SQL result cells"])
  assert(visual_mappings["Copy selected SQL result cells as HTML"])

  vim.keymap.set("n", "h", "0", { buffer = result_buffer, desc = "User result motion" })
  require("sqlserver.results.ui.keymaps").configure({ cell_navigation = false })
  for _, mode in ipairs({ "n", "x" }) do
    for _, key in ipairs({ "h", "j", "k", "l" }) do
      local mapping = vim.fn.maparg(key, mode, false, true)
      if mode == "n" and key == "h" then
        assert(mapping.desc == "User result motion", "Disabling cell navigation removed a user mapping")
      else
        assert(mapping.buffer ~= 1, "Disabled cell navigation retained " .. mode .. key)
      end
    end
  end
  require("sqlserver.results.ui.keymaps").configure({ cell_navigation = true })
  vim.wo.list = original_list
end)

return T
