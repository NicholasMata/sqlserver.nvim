return {
  -- Set up keymaps with this prefix. If which-key is found, this will be a which-key group.
  keymap_prefix = nil,

  --[[ How to open a buffer containing sql results.
  Valid options are: 
  "split"                   - Open results in a horizontal split
  "vsplit"                  - Open results in a vertical split
  "current_window"          - Open results in the current window
  function (bufnr) ... end  - Function which takes the buffer number of the results buffer to open 
                              (called once with the first result set). Use this to open the results area
  --]]
  open_results_in = "split",

  --[[ Where to view messages sent from sql server (eg when executing queries)
  Valid options are: 
  "activity"                            - Store messages in the SQL Server activity panel
  "notification"                        - View as a vim notification
  "buffer"                              - View in a messages buffer
  function(message, is_error) ...       - Function which takes the message string and is_error boolean
                                          (called for each message). Use this to view messages in a custom way
  --]]
  view_messages_in = "activity",

  -- Persistent workspace status and expandable activity UI.
  ui = {
    presenter = "default",
    winbar = true,
    native_progress = true,
    height = 12,
  },

  -- Result retrieval and rendering limits.
  results = {
    -- Limit fetched rows so large result sets do not overwhelm Neovim.
    max_rows = 100,
    -- Truncate cells wider than this while preserving the underlying result model.
    max_cell_width = 100,
  },

  -- Operational waits in milliseconds. false disables a timeout.
  timeouts = {
    lsp_attach = 10000,
    connection = 10000,
    object_explorer = 10000,
    query = false,
  },

  -- When choosing a table/view in the finder, immediately execute the generated SELECT statement
  execute_generated_select_statements = true,

  -- Settings passed to the SQL Server language server. See docs/Lsp-Settings.md
  lsp_settings = {
    format = {
      placeSelectStatementReferencesOnNewLine = true,
      keywordCasing = "Uppercase",
      datatypeCasing = "Uppercase",
      alignColumnDefinitionsInColumns = true,
    },
  },

  -- Options that will be set on buffers of sql file type (see https://neovim.io/doc/user/options.html)
  sql_buffer_options = {
    expandtab = true,
    tabstop = 4,
    shiftwidth = 4,
    softtabstop = 4,
  },

  -- Path to a json connections file (see docs/Connections-Json.md)
  -- If nil, it's stored in the data_dir
  connections_file = nil,

  -- Path to an existing SQL tools service binary (see https://github.com/microsoft/sqltoolsservice/releases).
  -- If nil, then the binary is auto downloaded to data_dir
  tools_file = nil,

  -- Directory to store download tools and internal config options
  data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "/sqlserver.nvim"):gsub("[/\\]+$", ""),
}
