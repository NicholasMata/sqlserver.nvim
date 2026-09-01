# Agent Notes

This repo is intended to become `sqlserver.nvim`, a SQL Server-native Neovim
workspace.

Read these before making broad changes:

- `docs/vision.md`
- `docs/roadmap.md`
- `docs/architecture.md`

The starting code is seeded from `mssql.nvim`. Treat inherited code as useful
working material, not as fixed architecture.

Backward compatibility with `mssql.nvim` is not a goal. Preserve proven SQL
Server behavior and protocol knowledge, but freely replace inherited modules,
commands, configuration, and APIs when doing so creates a stronger foundation.
Do not add compatibility shims unless they serve a documented `sqlserver.nvim`
use case.

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

## Testing

- Run `make test` for changes that can be covered without SQL Server.
- Add focused unit tests for core logic and adapter contracts.
- Run `make test-integration-local` for connection, query, metadata, or SQL
  Tools Service behavior when Docker is available.
- Keep test state isolated under `.tests/`; tests must not modify a user's
  normal Neovim data or configuration directories.
- Report any integration suite that could not be run.

## Git commit messages

Follow [Tim Pope's commit message guidance](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html):

- Use an imperative, capitalized subject line.
- Keep the subject around 50 characters.
- Do not end the subject with a period.
- Separate the subject from the body with a blank line.
- Wrap body text at approximately 72 characters.
- Use the body to explain what changed and why.
