# Releasing 1.0

This checklist defines the acceptance bar for `1.0.0`. Do not create the tag
until every required item is complete.

A release candidate may be published after the automated acceptance checks
pass. Use the candidate period to complete and record the manual core-loop pass
and to fix release-blocking defects. Promote the latest candidate to `1.0.0`
only when the complete checklist passes.

## Release branches

`main` represents the latest released state. `next` integrates work for the
next release, and ordinary pull requests target `next`. The active
`Unreleased` changelog is therefore maintained on `next`, not `main`.

Prepare and validate a release on `next`. Once its changelog entries have been
promoted to a dated version section and the release checklist passes, open a
pull request from `next` to `main`. Tag the merge commit on `main`, publish the
GitHub release, then restore an empty `Unreleased` section on `next` for the
following release.

An urgent fix for the currently released version may target `main` directly.
Release that fix promptly and bring the resulting commit into `next` so the
branches do not diverge.

## Release identity

- Use `v<version>` for the Git tag, such as `v1.0.0-rc.3`.
- Use `<version>` for the GitHub release title, such as `1.0.0-rc.3`.
- Use `sqlserver.nvim v<version>` for the annotated tag message.
- Mark release candidates as GitHub prereleases. Do not mark a stable release
  as a prerelease.

## Release notes

Write curated, user-facing release notes instead of publishing a raw commit
list. Use the changelog as the exhaustive record and the release description as
an approachable summary of the release.

Follow this structure and omit any empty section:

```markdown
A short paragraph describing the release's overall purpose.

## Highlights

- Three to seven of the most important user-facing changes.

## Added

- New capabilities not already covered by the highlights.

## Changed

- Behavior, defaults, dependencies, or workflow changes.

## Fixed

- User-visible defects corrected by the release.

## Testing

- Important automated and manual validation completed for the release.

See the [full comparison](COMPARISON_URL) for implementation details.
```

Keep `Highlights` selective and avoid repeating its details in the remaining
sections. Include internal work only when it affects compatibility, reliability,
or contributors. The `Testing` section must describe checks that were actually
completed rather than offer a general assurance.

## Repository

- [ ] Promote the release-candidate entries in the `next` branch's
  `CHANGELOG.md` to a `1.0.0` section dated on release day.
- [ ] Confirm `README.md`, configuration, usage, public API, migration, and
  roadmap documentation match the release.
- [ ] Update the commented `version` in the README installation example to the
  release tag so users can opt into an exact, reproducible pin.
- [ ] Merge the validated `next` release into `main`, then create an annotated
  `v1.0.0` tag from the clean merge commit only after CI and the manual
  acceptance pass.

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
5. Export a result to CSV, JSON, XML, and XLSX. Verify their saved values and
   the XLSX archive integrity.
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
