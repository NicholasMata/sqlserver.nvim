# sqlserver.nvim

A SQL Server-native workspace for Neovim.

This project starts from the practical lessons in `mssql.nvim`, but the goal is
not to remain backward compatible with it or to clone SQL Server Management
Studio. The goal is to make the core SQL Server loop reliable inside Neovim:

- connect to SQL Server and Azure SQL
- browse databases, schemas, tables, views, procedures, and functions
- write T-SQL with language intelligence
- execute and cancel queries
- inspect messages, errors, and multiple result sets
- script database objects into editable buffers
- expose Lua APIs that can later support MCP and agent workflows

Queries that return multiple result sets create one buffer per set while using
one results window. The first result is shown initially; use `]r` and `[r` from
a result buffer, or `:SQLServer NextResult` and `:SQLServer PreviousResult`, to
move between them. Each result uses the dedicated `sqlserver-result` filetype
and can be saved independently. The renderer highlights headers and truncation
without embedding presentation markup in the result data.

Result retrieval and display limits can be configured independently:

```lua
require("sqlserver").setup({
  results = {
    max_rows = 100,
    max_cell_width = 100,
  },
})
```

When `max_rows` is reached, the result buffer says how many rows are shown.
Cell truncation only affects the rendered table, leaving the plugin-owned
result model available for future renderers and exporters.

## Status

This is a starter repo. The initial codebase is seeded from the existing
`mssql.nvim` plugin and should be treated as a base for refactoring, not a
finished architecture.

## Direction

See [docs/vision.md](docs/vision.md) for the product direction and
[docs/roadmap.md](docs/roadmap.md) for the initial milestones. The intended
module boundaries and migration strategy are described in
[docs/architecture.md](docs/architecture.md).

## Workspace status and activity

Each SQL query buffer has a workspace status shown in its winbar. It includes
the server, database, and current state, such as connecting, ready, executing,
cancelling, or refreshing metadata. Active operations include elapsed time.

Long-running work also uses Neovim's native progress messages. Routine state
changes and SQL Server messages are kept out of transient notifications and
recorded in an expandable activity split instead. Open or close it with:

```vim
:SQLServer Activity
```

Press `q` in the activity split to close it. If `keymap_prefix` is configured,
`a` under that prefix opens the same view. For example, the configuration below
uses `<leader>sa`.

```lua
require("sqlserver").setup({
  keymap_prefix = "<leader>s",
  view_messages_in = "activity",
  ui = {
    presenter = "default",
    winbar = true,
    native_progress = true,
    height = 12,
  },
})
```

The default winbar keeps the server and database on the left and status on the
right. Set `winbar = false` to disable it. Use an object for a compact layout:

```lua
winbar = {
  layout = "compact",
  alignment = "right", -- "left", "center", or "right"
}
```

The object form also accepts `layout = "split"`, which is what `winbar = true`
uses. Set `ui.native_progress` to `false` to let another UI own progress
presentation.
`require("sqlserver").status()` returns the same status string for any
statusline implementation without coupling the plugin to one. The older
`"notification"` and `"buffer"` values for `view_messages_in` remain available,
as does a custom message function.

The winbar colors only its state icon. Its default highlight groups link to
standard Neovim groups, and user or colorscheme definitions take precedence:

```lua
vim.api.nvim_set_hl(0, "SqlServerReady", { fg = "#98c379" })
vim.api.nvim_set_hl(0, "SqlServerWorking", { fg = "#61afef" })
vim.api.nvim_set_hl(0, "SqlServerCancelling", { fg = "#e5c07b" })
vim.api.nvim_set_hl(0, "SqlServerDisconnected", { fg = "#5c6370" })
```

Internally, workspaces publish structured activity events to a subscriber
stream. Neovim progress and the activity split are consumers of that stream,
not workspace dependencies. This keeps presentation replaceable if Neovim's UI
APIs change and allows future consumers to be added independently.

Configure one primary custom presenter directly in `setup()`:

```lua
require("sqlserver").setup({
  ui = {
    presenter = function(workspace, event)
      -- event.kind, event.status, event.title, event.message,
      -- event.operation_id, event.duration_ms, and event.time
    end,
  },
})
```

Use `ui.presenter = false` to disable primary presentation completely. The
default is `"default"`, which enables the included winbar, native progress, and
activity split.

The stream is also part of the public Lua API for optional secondary consumers:

```lua
local unsubscribe = require("sqlserver").subscribe_activity(function(workspace, event)
  -- Log or observe activity independently of the primary presenter.
end)

unsubscribe()
```

This API intentionally exposes events rather than integrations for individual
statusline or notification plugins. Custom UIs can translate the same event
shape into any presentation they choose.

## Development

Load the plugin from a local checkout:

```lua
vim.opt.rtp:prepend("/path/to/sqlserver.nvim")
require("sqlserver").setup({
  keymap_prefix = "<leader>s",
})
```

Run the isolated unit suite:

```sh
make test
```

Unit tests do not download SQL Tools Service or require a database. All Neovim
configuration, data, state, and cache files created by tests are isolated under
`.tests/`.

Run the full integration suite against a disposable SQL Server 2022 Developer
container:

```sh
make test-integration-local
```

This requires Docker with the Compose plugin. The target starts SQL Server,
waits for it to become healthy, recreates the fixture databases, downloads SQL
Tools Service into `.tests/`, and runs the integration tests. Stop and remove
the database container with:

```sh
make test-env-down
```

Microsoft supports its SQL Server Linux container images only on x86-64 Linux
hosts. The Compose configuration requests `linux/amd64`, but running it through
emulation on an ARM host is not officially supported. On ARM systems, use a
reachable SQL Server instance if the container does not run reliably. See
[Microsoft's SQL Server container prerequisites](https://learn.microsoft.com/en-us/sql/linux/install-upgrade/quickstart-install-docker).

To use an existing SQL Server instead, provide the connection environment
variables and run the integration suite directly:

```sh
DbServer=localhost \
DbDatabase=master \
DbUser=sa \
DbPassword='your-password' \
make test-integration
```

Use `SQLSERVER_PORT` to change the local container's host port. When using a
non-default port, also set `DbServer` to the server value expected by SQL Server
clients, such as `localhost,14330`.

## Contributing

Follow [Tim Pope's commit message guidance](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html): use an imperative, capitalized subject of
about 50 characters without a trailing period. Separate the body with a blank
line, wrap it at approximately 72 characters, and explain what changed and why.

Agents and AI coding tools should also follow the repository instructions in
[AGENTS.md](AGENTS.md).
