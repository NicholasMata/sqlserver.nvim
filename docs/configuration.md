# Configuration

Call `setup()` once from your plugin manager or Neovim configuration. Setup is
asynchronous because SQL Tools Service may need to be installed; an optional
second argument runs after initialization.

## Defaults

Every supported option and its default is shown below. You only need to include
values you want to change.

```lua
require("sqlserver").setup({
  keymap_prefix = nil,
  open_results_in = "split",
  view_messages_in = "activity",

  ui = {
    presenter = "default",
    winbar = true,
    native_progress = true,
    height = 12,
  },

  results = {
    max_rows = 100,
    max_cell_width = 100,
  },

  timeouts = {
    lsp_attach = 10000,
    connection = 10000,
    object_explorer = 10000,
    query = false,
  },

  execute_generated_select_statements = true,

  lsp_settings = {
    format = {
      placeSelectStatementReferencesOnNewLine = true,
      keywordCasing = "Uppercase",
      datatypeCasing = "Uppercase",
      alignColumnDefinitionsInColumns = true,
    },
  },

  sql_buffer_options = {
    expandtab = true,
    tabstop = 4,
    shiftwidth = 4,
    softtabstop = 4,
  },

  connections_file = nil,
  tools_file = nil,
  tools_version = "5.0.20250530.2",
  data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "sqlserver.nvim"),
}, function()
  -- sqlserver.nvim is ready.
end)
```

## Option reference

Durations are expressed in milliseconds. A timeout value of `false` waits
indefinitely.

| Option | Default | Description |
| --- | --- | --- |
| `keymap_prefix` | `nil` | Prefix for the default mappings. `nil` creates no mappings. |
| `open_results_in` | `"split"` | Opens results in `"split"`, `"vsplit"`, `"current_window"`, or with `function(bufnr)`. |
| `view_messages_in` | `"activity"` | Sends SQL messages to `"activity"`, `"notification"`, `"buffer"`, or `function(message, is_error)`. |
| `ui.presenter` | `"default"` | Uses the built-in presenter, `false` for none, or `function(workspace, event)` for a custom primary subscriber. |
| `ui.winbar` | `true` | Enables the default winbar. Use `false` or a table with `layout` and `alignment` to customize it. |
| `ui.winbar.layout` | `"split"` | With the object form, uses `"split"` or `"compact"` content. |
| `ui.winbar.alignment` | `"right"` | With the compact layout, aligns content `"left"`, `"center"`, or `"right"`. |
| `ui.native_progress` | `true` | Publishes active and completed operations through Neovim's built-in progress messages. |
| `ui.height` | `12` | Height of the built-in activity split. |
| `results.max_rows` | `100` | Maximum rows fetched for each result set. |
| `results.max_cell_width` | `100` | Maximum displayed cell width. The underlying value remains unchanged. |
| `timeouts.lsp_attach` | `10000` | Maximum wait for SQL Tools Service to attach to a SQL buffer. |
| `timeouts.connection` | `10000` | Maximum wait for a connection or disconnection operation. |
| `timeouts.object_explorer` | `10000` | Maximum wait for an object metadata refresh or scripting request. |
| `timeouts.query` | `false` | Maximum query duration before server-side cancellation is requested. |
| `execute_generated_select_statements` | `true` | Immediately executes generated table and view queries. Procedures are never executed automatically. |
| `lsp_settings` | See defaults above | Settings passed directly to SQL Tools Service. |
| `sql_buffer_options` | See defaults above | Neovim buffer options applied to SQL buffers. |
| `connections_file` | `nil` | Connection-profile JSON path. `nil` uses `data_dir/connections.json`. |
| `tools_file` | `nil` | Existing SQL Tools Service executable. `nil` uses the managed installation. |
| `tools_version` | `"5.0.20250530.2"` | Pinned managed SQL Tools Service release. Changing it triggers a staged reinstall. |
| `data_dir` | `stdpath("data") .. "/sqlserver.nvim"` | Stores the managed service, connection profiles, logs, and internal state. |

When another distribution overwrites mappings after setup, install them later
with `require("sqlserver").set_keymaps(prefix)`. Connection profile fields and
environment-variable references are documented in
[Connections JSON](connections-json.md).

## Presentation

`ui.winbar = true` uses the split layout, with server and database on the left
and status on the right. The object form provides layout control:

```lua
ui = {
  winbar = {
    layout = "compact", -- "compact" or "split"
    alignment = "right", -- "left", "center", or "right"
  },
}
```

The state icon links to standard Neovim highlight groups. Override its colors
with `SqlServerReady`, `SqlServerWorking`, `SqlServerCancelling`, and
`SqlServerDisconnected`:

```lua
vim.api.nvim_set_hl(0, "SqlServerReady", { fg = "#98c379" })
vim.api.nvim_set_hl(0, "SqlServerWorking", { fg = "#61afef" })
vim.api.nvim_set_hl(0, "SqlServerCancelling", { fg = "#e5c07b" })
vim.api.nvim_set_hl(0, "SqlServerDisconnected", { fg = "#5c6370" })
```

Statusline integrations can call `require("sqlserver").status()`. Independent
secondary consumers can subscribe without replacing the primary presenter:

```lua
local unsubscribe = require("sqlserver").subscribe_activity(function(workspace, event)
  -- Observe or present the structured event.
end)

unsubscribe()
```

## SQL Tools Service

`lsp_settings` is passed directly to SQL Tools Service. See
[LSP Settings](lsp-settings.md) for the available formatting configuration.
Neovim options in `sql_buffer_options` are applied to every SQL buffer.

Managed service updates are extracted and validated in staging before replacing
the active version, so a failed update preserves the previous working
installation. A custom `tools_file` must be readable and executable.

See [Usage](usage.md) for commands, mappings, query execution, result
navigation, activity, language features, and object workflows.
