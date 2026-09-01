# sqlserver.nvim

https://github.com/user-attachments/assets/d7838d49-58e5-44c0-8a71-c649a2b2df34

Stay in Neovim for the daily SQL Server workflow—from connecting and exploring
objects to executing T-SQL and inspecting results.

`sqlserver.nvim` is a SQL Server-native workspace built around Neovim rather
than an attempt to reproduce SQL Server Management Studio. It uses Microsoft
SQL Tools Service for SQL Server-aware language intelligence and query
execution while keeping protocol, workspace, result, and UI concerns separate.

## Features

- Connect query buffers to SQL Server and Azure SQL profiles.
- Complete, diagnose, format, hover, navigate, and inspect T-SQL signatures
  through Neovim's built-in LSP support and SQL Tools Service.
- Search and script tables, views, procedures, and functions in the connected
  database.
- Execute the statement under the cursor, a visual selection, or the complete
  buffer.
- Cancel active queries and inspect persistent workspace activity.
- Navigate multiple result sets in dedicated `sqlserver-result` buffers.
- Save individual results as CSV, JSON, Excel, or XML.
- Display server, database, and execution state in a configurable winbar.

Switching from `mssql.nvim` requires configuration and workflow changes. See
[Migrating from mssql.nvim](docs/migrating-from-mssql.md) for a compatibility
guide and checklist.

## Installation

Requires Neovim 0.11 or newer. With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "NicholasMata/sqlserver.nvim",
  opts = {
    keymap_prefix = "<leader>s",
  },
}
```

SQL Tools Service is downloaded automatically on first setup unless
`tools_file` points to an existing executable. Create or edit connection
profiles with:

```vim
:SQLServer EditConnections
```

See [Connections JSON](docs/Connections-Json.md) for the supported connection
properties and `${ENVIRONMENT_VARIABLE}` credential references.

## Configuration

The defaults provide a split result view, persistent activity, native progress,
and a winbar showing the current server, database, and state:

```lua
require("sqlserver").setup({
  keymap_prefix = "<leader>s",
  open_results_in = "split",
  view_messages_in = "activity",
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
  ui = {
    presenter = "default",
    winbar = true,
    native_progress = true,
    height = 12,
  },
})
```

Operational timeouts use milliseconds or `false` to wait indefinitely. Queries
have no client-side timeout by default and can be stopped with `CancelQuery`.

With the prefix above, use `<leader>sx` for the statement under the cursor or a
visual selection, and `<leader>sX` for the complete buffer. Commands are also
available through `:SQLServer`.

See [Configuration](docs/configuration.md) for all options, commands, keymaps,
result navigation, statusline usage, and custom activity presenters. See the
[Public Lua API](docs/public-api.md) for UI-independent connection, execution,
object, cancellation, and export operations.

## Contributing

Run `make test` for unit tests and `make lint` for formatting verification before
submitting changes. See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete local
test environment, Docker integration workflow, coding style, and commit-message
rules.
