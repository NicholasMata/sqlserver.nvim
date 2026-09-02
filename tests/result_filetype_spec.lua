return {
  test_name = "Result filetype should install buffer-local mappings",
  run_test_async = function()
    local result_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(result_buffer)
    vim.api.nvim_set_option_value("filetype", "sqlserver-result", { buf = result_buffer })

    local mappings = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(result_buffer, "n")) do
      mappings[mapping.lhs] = mapping.desc
    end

    assert(mappings["]r"] == "Next SQL result")
    assert(mappings["[r"] == "Previous SQL result")

    local noop = function() end
    local handlers = setmetatable({ save_query_results = noop }, {
      __index = function()
        return noop
      end,
    })
    require("sqlserver.interface").set_keymaps("<leader>d", handlers)

    local has_save_mapping = false
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(result_buffer, "n")) do
      if mapping.desc == "Save SQL result" then
        has_save_mapping = true
        break
      end
    end
    assert(has_save_mapping, "The configured prefix should add a result-local save mapping")
  end,
}
