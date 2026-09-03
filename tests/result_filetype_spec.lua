return {
  test_name = "Result filetype should install buffer-local mappings",
  run_test_async = function()
    local opened = false
    local shown = require("sqlserver.ui.results.view").show({}, {
      open_results_in = function()
        opened = true
      end,
    })
    assert(not shown and not opened, "Empty result collections should not invoke the result opener")

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

    local prefixed_mappings = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(result_buffer, "n")) do
      prefixed_mappings[mapping.desc] = true
    end
    assert(prefixed_mappings["Save SQL result"], "The configured prefix should add a result-local save mapping")
    assert(prefixed_mappings["Next SQL execution"])
    assert(prefixed_mappings["Previous SQL execution"])
  end,
}
