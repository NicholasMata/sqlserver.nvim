<p align="center">
  <img src="docs/assets/sqlserver-logo.png" alt="sqlserver.nvim logo" width="160">
</p>

<h1 align="center">sqlserver.nvim</h1>

<div align="center">

[![Neovim](https://img.shields.io/badge/Neovim-0.11.7%2B-57A143?style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![Platforms](https://img.shields.io/badge/Platforms-Linux_%7C_macOS_%7C_Windows-blue?style=flat-square)](#installation)
[![Release](https://img.shields.io/github/v/release/NicholasMata/sqlserver.nvim?include_prereleases&style=flat-square&label=release)](https://github.com/NicholasMata/sqlserver.nvim/releases)
[![Tests](https://github.com/NicholasMata/sqlserver.nvim/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/NicholasMata/sqlserver.nvim/actions/workflows/test.yml)
[![License](https://img.shields.io/github/license/NicholasMata/sqlserver.nvim?style=flat-square)](LICENSE.md)

</div>

<p align="center">
  <a href="docs/usage.md">Usage</a>
  ·
  <a href="#configuration">Configuration</a>
  ·
  <a href="https://github.com/users/NicholasMata/projects/1/views/2">Roadmap</a>
  ·
  <a href="https://github.com/NicholasMata/sqlserver.nvim/milestones">Planned Releases</a>
  ·
  <a href="https://github.com/NicholasMata/sqlserver.nvim/releases">Releases</a>
  ·
  <a href="https://github.com/NicholasMata/sqlserver.nvim/blob/next/CHANGELOG.md">Unreleased Changes</a>
</p>

<p align="center">
  <img src="docs/assets/sqlserver-showcase.gif" alt="sqlserver.nvim showcase" width="900">
</p>

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
- Search, browse, and script tables, views, procedures, and functions in the
  connected database. The [hierarchical Object Explorer](docs/object-explorer.md)
  is available when `snacks.nvim` is installed with its picker enabled.
- Execute the statement under the cursor, a visual selection, or the complete
  buffer.
- Cancel active queries and inspect persistent workspace activity.
- Revisit recent executions and navigate their result sets in dedicated
  `sqlserver-result` buffers.
- Open CSV, JSON, and XML exports as editable buffers, or save Excel `.xlsx`.
- Copy selected result ranges as rich HTML tables for apps such as Teams.
- Display workspace state and result-history position in a configurable winbar.

Switching from `mssql.nvim` requires configuration and workflow changes. See
[Migrating from mssql.nvim](docs/migrating-from-mssql.md) for a compatibility
guide and checklist.

## Installation

Requires Neovim 0.11.7 or newer. With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "NicholasMata/sqlserver.nvim",
  -- version = "v1.0.0", -- Pin a release
  -- branch = "next", -- Follow unreleased development
  opts = {
    keymap_prefix = "<leader>s",
  },
}
```

The tested SQL Tools Service release is pinned and installed automatically on
first setup unless `tools_file` points to an existing executable. Override
`tools_version` only when intentionally testing another upstream release.
`snacks.nvim` is optional; only `:SQLServer ObjectExplorer` requires it.
Create or edit connection profiles with:

```vim
:SQLServer EditConnections
```

See [Connections JSON](docs/connections-json.md) for the supported connection
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
    column_icons = true,
    sticky_header = true,
    history_limit = 10,
    max_rows = 1000,
    max_cell_width = 100,
  },
  timeouts = {
    lsp_attach = 10000,
    connection = 10000,
    export = 10000,
    object_explorer = 10000,
    query = false,
  },
  ui = {
    presenter = "default",
    winbar = true,
    native_progress = true,
    activity = {
      height = 12,
    },
    connection_info = {
      height = "auto",
    },
  },
})
```

See the [full configuration reference](docs/configuration.md) for every
supported option and default.

Operational timeouts use milliseconds or `false` to wait indefinitely. Queries
have no client-side timeout by default and can be stopped with `CancelQuery`.

With the prefix above, use `<leader>sx` for the statement under the cursor or a
visual selection, and `<leader>sX` for the complete buffer. Commands are also
available through `:SQLServer`.

## SQL Tools Service Coverage
**Status**: ✅ Complete · 🟡 Partial · 🔵 Planned · ⚪ Not currently on the roadmap
```
                         SQL Tools Service
                                │
           ┌────────────────────┼────────────────────┐
           │                    │                    │
      Development          Administration       Diagnostics
           │                    │                    │
      ✅ Connections        🔵 SQL Agent          ⚪ Profiler
      ✅ IntelliSense       ⚪ Backup             ⚪ Query Store
      ✅ Query              ⚪ Restore            🔵 Query Plans
      ✅ Objects            🔵 Edit Data          ⚪ Assessment
      ⚪ Schema Compare     ⚪ Security
      ⚪ Table Design
```

The [coverage definitions](docs/sql-tools-service-coverage.md) explain each
term and status. GitHub [issues](https://github.com/NicholasMata/sqlserver.nvim/issues)
and [release milestones](https://github.com/NicholasMata/sqlserver.nvim/milestones)
track planned scope and delivery.

## Contributing

Run `make test` for unit tests and `make lint` for formatting verification before
submitting changes. See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete local
test environment, Docker integration workflow, coding style, and commit-message
rules. The [architecture](docs/architecture.md) explains module ownership, and
the [public Lua API](docs/public-api.md) documents UI-independent integration.
Maintainers use the [release checklist](docs/releasing.md) for automated and
manual `1.0.0` acceptance.

The logo adapts the [Neovim logo](https://neovim.io/) by Jason Long
([CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)).
