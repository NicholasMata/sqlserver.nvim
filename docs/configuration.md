# Configuration

Call `setup()` once from your plugin manager or Neovim configuration:

```lua
require("sqlserver").setup({
  keymap_prefix = "<leader>s",
})
```

Setup is asynchronous because SQL Tools Service may need to be downloaded. An
optional callback runs after initialization:

```lua
require("sqlserver").setup({}, function()
  print("sqlserver.nvim is ready")
end)
```

## Options

### Keymaps

`keymap_prefix` defaults to `nil`, which creates no mappings. When set, the
plugin creates mappings below that prefix and registers a group with which-key
when it is available.

Use `require("sqlserver").set_keymaps(prefix)` to install mappings separately
when another distribution would otherwise overwrite them.

### Results

`open_results_in` controls where the result area opens:

- `"split"` opens a horizontal split;
- `"vsplit"` opens a vertical split;
- `"current_window"` replaces the current window's buffer;
- `function(bufnr)` provides complete control over opening the first result
  buffer.

Queries with multiple result sets create one buffer per result set in one
results window. Use `]r`, `[r`, `:SQLServer NextResult`, or
`:SQLServer PreviousResult` to move between them. Each result can be saved
independently.

Result buffers use the dedicated `sqlserver-result` filetype. Retrieval and
rendering limits are configured separately:

```lua
results = {
  max_rows = 100,
  max_cell_width = 100,
}
```

When `max_rows` is reached, the result buffer reports how many rows are shown.
Cell-width truncation changes only the rendered table, not the underlying
plugin-owned result model.

Database `NULL` is tracked separately from its displayed text, so a string whose
value is literally `NULL` is not treated as a null value. Unicode, decimal,
datetime, and binary display values are preserved at the SQL Tools Service
adapter boundary together with invariant-culture values when the service
provides them.

### Messages and activity

`view_messages_in` controls SQL Server messages:

- `"activity"` records them in the workspace activity view;
- `"notification"` uses `vim.notify`;
- `"buffer"` writes them to a messages buffer;
- `function(message, is_error)` provides custom handling.

Open the default activity view with `:SQLServer Activity` or the `a` mapping
suffix. Press `q` in the activity window to close it.

The `ui` object configures persistent presentation:

```lua
ui = {
  presenter = "default",
  winbar = true,
  native_progress = true,
  height = 12,
}
```

- `presenter = "default"` enables the built-in winbar, progress, and activity
  view.
- `presenter = false` disables primary presentation.
- `presenter = function(workspace, event)` installs a custom primary
  subscriber.
- `native_progress = false` prevents the default UI from publishing Neovim
  progress messages.
- `height` controls the default activity split height.

The presenter receives structured events with fields including `kind`,
`status`, `title`, `message`, `operation_id`, `duration_ms`, and `time`.

### Winbar

`winbar = true` uses the default split layout: server and database on the left,
with state on the right. Set it to `false` to disable the winbar.

Use an object for layout control:

```lua
winbar = {
  layout = "compact", -- "compact" or "split"
  alignment = "right", -- "left", "center", or "right"
}
```

The state icon uses highlight groups that link to standard Neovim groups by
default. Define them in a colorscheme or configuration to customize colors:

```lua
vim.api.nvim_set_hl(0, "SqlServerReady", { fg = "#98c379" })
vim.api.nvim_set_hl(0, "SqlServerWorking", { fg = "#61afef" })
vim.api.nvim_set_hl(0, "SqlServerCancelling", { fg = "#e5c07b" })
vim.api.nvim_set_hl(0, "SqlServerDisconnected", { fg = "#5c6370" })
```

### Statuslines and secondary subscribers

`require("sqlserver").status()` returns the active workspace's status text or
`nil`. It can be used by lualine or another statusline without coupling the
plugin to that implementation:

```lua
function()
  return require("sqlserver").status() or ""
end
```

Secondary consumers can subscribe independently:

```lua
local unsubscribe = require("sqlserver").subscribe_activity(function(workspace, event)
  -- Observe or present the event.
end)

unsubscribe()
```

### SQL buffers and language service

`sql_buffer_options` contains Neovim options applied to SQL buffers. The
defaults use four-space indentation:

```lua
sql_buffer_options = {
  expandtab = true,
  tabstop = 4,
  shiftwidth = 4,
  softtabstop = 4,
}
```

`lsp_settings` is passed to SQL Tools Service. See
[LSP Settings](Lsp-Settings.md) for supported formatting settings.

SQL Tools Service attaches as a standard Neovim LSP client. The plugin relies
on Neovim's built-in LSP interfaces for completion, diagnostics, hover,
signature help, definitions, and document formatting instead of introducing a
second set of SQL-specific UI abstractions. Existing LSP mappings and completion
plugins therefore continue to work.

For example, these mappings use only Neovim APIs:

```lua
vim.keymap.set("n", "K", vim.lsp.buf.hover)
vim.keymap.set("n", "gd", vim.lsp.buf.definition)
vim.keymap.set("i", "<C-s>", vim.lsp.buf.signature_help)
vim.keymap.set("n", "<leader>f", function()
  vim.lsp.buf.format({ async = true })
end)
```

Schema-aware results become available after the query buffer connects and SQL
Tools Service reports that IntelliSense is ready. `:SQLServer RefreshCache`
rebuilds IntelliSense metadata for the current connection. The integration
suite verifies completion, diagnostics, hover, signature help, definitions, and
formatting after switching databases.

`execute_generated_select_statements` defaults to `true`. When enabled, choosing
a table or view in the object finder immediately executes its generated
`SELECT` statement. Set it to `false` to open the generated SQL without running
it.

### Paths

- `connections_file` overrides the connections JSON path.
- `tools_file` uses an existing SQL Tools Service executable.
- `data_dir` controls downloaded tools and internal plugin data.

When unset, files are stored under `sqlserver.nvim` inside
`vim.fn.stdpath("data")`.

## Query execution

Successful result sets are retained even when another statement in the same
batch raises an error. In that case the result buffers remain available, the SQL
error is recorded in workspace activity, and the query operation finishes with
an error state and the total number of rows that were returned.

Cancellation remains in progress until SQL Tools Service reports query
completion. Once cancellation completes, the same connected query buffer can
execute another statement without reconnecting.

| Default suffix | Command | Behavior |
| --- | --- | --- |
| `x` | `ExecuteQuery` | Execute the statement under the cursor |
| visual `x` | `ExecuteQuery` | Execute the selected text |
| `X` | `ExecuteBuffer` | Execute the complete buffer |
| `l` | `CancelQuery` | Cancel the active query |

Current-statement parsing is delegated to SQL Tools Service. If a disconnected
query is executed, the plugin attempts to connect with the profile named
`default`.

## Object scripting

The object picker has two consistent actions:

| Default suffix | Command | Behavior |
| --- | --- | --- |
| `f` | `Find` | Build `SELECT` SQL for a table/view or `EXEC` SQL for a procedure |
| `o` | `ObjectDefinition` | Script the selected object's definition |

When `execute_generated_select_statements` is enabled, generated table and view
queries execute immediately. Procedure calls are inserted into a query buffer
but are never executed automatically because they may have side effects.

Definitions use `CREATE` scripting for tables, views, stored procedures, and
supported functions. They are always opened as editable SQL and never executed.

## Commands

Commands use the form `:SQLServer <command>`:

| Command | Purpose |
| --- | --- |
| `Activity` | Toggle workspace activity |
| `Connect` | Connect the current query buffer |
| `Disconnect` | Disconnect the current query buffer |
| `ExecuteQuery` | Execute the statement under the cursor |
| `ExecuteBuffer` | Execute the complete buffer |
| `CancelQuery` | Cancel the active query |
| `NewQuery` | Open a query buffer |
| `NewDefaultQuery` | Open a query using the `default` profile |
| `SwitchDatabase` | Change database on the current server |
| `Find` | Build a runnable query for a database object |
| `ObjectDefinition` | Script a database object's definition |
| `RefreshCache` | Refresh metadata and IntelliSense caches |
| `EditConnections` | Edit connection profiles |
| `SaveQueryResults` | Export the current result set |
| `NextResult` | Display the next result set |
| `PreviousResult` | Display the previous result set |
| `BackupDatabase` | Insert a database backup command |
| `RestoreDatabase` | Insert a database restore command |

Command completion only includes actions valid for the current workspace state.
