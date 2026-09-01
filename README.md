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

## Status

This is a starter repo. The initial codebase is seeded from the existing
`mssql.nvim` plugin and should be treated as a base for refactoring, not a
finished architecture.

## Direction

See [docs/vision.md](docs/vision.md) for the product direction and
[docs/roadmap.md](docs/roadmap.md) for the initial milestones. The intended
module boundaries and migration strategy are described in
[docs/architecture.md](docs/architecture.md).

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
