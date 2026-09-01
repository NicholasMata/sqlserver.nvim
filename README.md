# sqlserver.nvim

A SQL Server-native workspace for Neovim.

This project starts from the practical lessons in `mssql.nvim`, but the goal is
not to clone SQL Server Management Studio. The goal is to make the core SQL
Server loop reliable inside Neovim:

- connect to SQL Server and Azure SQL
- browse databases, schemas, tables, views, procedures, and functions
- write T-SQL with language intelligence
- execute and cancel queries
- inspect messages, errors, and multiple result sets
- script database objects into editable buffers
- expose Lua APIs that can later support MCP and agent workflows

## Status

This is a starter repo. The initial codebase is seeded from the existing
`mssql.nvim` plugin and should be treated as a base for refactoring, not a
finished architecture.

## Direction

See [docs/vision.md](docs/vision.md) for the product direction and
[docs/roadmap.md](docs/roadmap.md) for the initial milestones.

## Development

Load the plugin from a local checkout:

```lua
vim.opt.rtp:prepend("/path/to/sqlserver.nvim")
require("sqlserver").setup({
  keymap_prefix = "<leader>s",
})
```

Run the lightweight test runner:

```sh
nvim --headless --clean -u tests/load-plugin.lua -l runtests.lua
```

Some integration tests require SQL Tools Service and a reachable SQL Server.

