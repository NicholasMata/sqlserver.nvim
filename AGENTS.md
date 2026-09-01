# Agent Notes

This repo is intended to become `sqlserver.nvim`, a SQL Server-native Neovim
workspace.

Read these before making broad changes:

- `docs/vision.md`
- `docs/roadmap.md`

The starting code is seeded from `mssql.nvim`. Treat inherited code as useful
working material, not as fixed architecture.

Prefer these boundaries:

- connection manager
- SQL Tools Service language adapter
- query executor
- metadata/object explorer
- result model and renderers
- Neovim commands/views
- public Lua API

Do not add broad SSMS-style admin features until the core query/object workflow
is reliable.

