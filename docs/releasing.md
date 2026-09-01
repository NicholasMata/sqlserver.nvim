# Releasing 1.0

This checklist defines the acceptance bar for `1.0.0`. Do not create the tag
until every required item is complete.

## Repository

- [ ] Move the `CHANGELOG.md` Unreleased entries into a `1.0.0` section dated
  on release day.
- [ ] Confirm `README.md`, configuration, public API, migration, and roadmap
  documentation match the release.
- [ ] Create an annotated `v1.0.0` tag from a clean `main` branch only after CI
  and the manual acceptance pass.

## Automated acceptance

- [ ] Formatting and unit tests pass on Linux, macOS, and Windows.
- [ ] The Docker-backed SQL Server integration suite passes on Linux.
- [ ] CI confirms headless Neovim and SQL Tools Service processes are gone when
  integration tests finish.
- [ ] The repository contains no credentials, local queries, test state, or
  generated service binaries.

Run the complete local check with Docker Desktop running:

```sh
make format-check
make test-unit
make test-integration-local
git diff --check
git status --short
```

## Manual core-loop acceptance

Record the date, operating system, Neovim version, SQL Tools Service version,
and SQL Server version in the release pull request. Perform these steps from a
fresh Neovim data directory:

1. Start Neovim and confirm the pinned SQL Tools Service installs once without
   replacing a valid installation on the next start.
2. Create a query buffer and connect with a profile whose password comes from
   an environment variable. Confirm status reaches `Ready` and no secret is
   present in `:messages`, the activity panel, or the LSP log.
3. Verify completion, diagnostics, hover, signature help, definition lookup,
   and formatting in the connected database.
4. Execute the current statement, a visual selection, and the complete buffer.
   Confirm multiple result sets, SQL messages, partial success, zero-row
   results, truncation indicators, and result navigation.
5. Export a result to CSV and JSON and verify the saved values.
6. Start and cancel a long-running query. Confirm the server operation stops
   and the workspace returns to `Ready`.
7. Search tables, views, procedures, scalar functions, and table-valued
   functions. Open both runnable queries and editable definitions.
8. Switch databases, disconnect, reconnect, delete a connected buffer, and exit
   Neovim. Confirm no SQL Tools Service process remains.
9. Exercise invalid credentials, TLS rejection, an unreachable server, and an
   invalid service executable. Confirm each produces a distinct, secret-safe
   error and leaves Neovim usable.

The manual pass is intentionally not replaced by automated tests: it verifies
the actual buffers, notifications, status presentation, and interactive flow a
user will experience.
