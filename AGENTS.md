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

## Writing commits

Treat every commit as an operation whose message must be correct before it is
created. Before writing any commit:

- Prepare the exact final subject and body as real multiline text and inspect
  the rendered message.
- Apply all commit-message rules above.
- Never pass escaped newline text such as `\n` as the commit body. Use an input
  file or another mechanism that preserves actual newline characters.
- Check that the body contains no literal escape sequences and that its lines
  wrap at approximately 72 characters.
- Do not create a commit with the intention of repairing its message through a
  later amend. If the commit mechanism cannot preserve the reviewed message,
  stop before creating the commit.

Inspect the resulting message immediately after every commit.

## Merging pull requests

Apply the writing procedure above before every squash merge. Retain the
`(#<number>)` suffix so the squash commit remains visibly associated with its
pull request. Treat a GitHub-created merge commit as immutable and never plan
to amend or force-push it afterward.

If the merge tool cannot produce the reviewed message exactly, stop before
merging. Amending the result breaks the commit association recorded by the
pull request.

Use squash merges only for ordinary pull requests targeting `next`. Never
rebase `next` after it contains merged pull requests. When `main` receives a
direct change, merge `main` into `next` with a merge commit so existing commit
IDs and pull request associations remain intact. Promote `next` to `main` with
a merge commit as well; do not squash or rebase a release promotion.
