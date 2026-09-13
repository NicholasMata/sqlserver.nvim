# Changelog

All notable changes to `sqlserver.nvim` will be documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
releases use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Ongoing development for the next release is recorded in the
[`next` branch changelog](https://github.com/NicholasMata/sqlserver.nvim/blob/next/CHANGELOG.md).
This `main` changelog contains released versions only.

## [1.0.0-rc.4] - 2026-09-13

### Fixed

- Pass download and extraction values through PowerShell environment variables
  so managed SQL Tools Service installation supports paths containing shell
  metacharacters on Windows.
- Return asynchronous installation and configuration failures through the
  `setup()` callback instead of only displaying an error notification.
- Wait for SQL Tools Service object-scripting completion so failed or empty
  definition scripts report an error instead of opening a definition buffer.
- Refresh Object Explorer metadata from the server so explicit refreshes
  reflect schema and permission changes without retaining stale cache data.

## [1.0.0-rc.3] - 2026-09-09

### Added

- Added deterministic disposal of SQL Tools Service query storage when result
  executions are released.
- Added `[c` and `]c` navigation between rendered result columns.
- Added `K` inspection of SQL column types, nullability, precision, scale, and
  available source-object metadata from result buffers.
- Added `:SQLServer CopyResultCell` for copying complete, untruncated cell
  values, including multiline content.
- Added visual result-range export with selected rows, columns, and headings.
- Added visual `<keymap_prefix>y` copying of selected result ranges as rich HTML
  tables for supported system clipboards.
- Added a confirmed result-local action that removes the current result set and
  automatically removes its execution when no result sets remain.
- Added an optional sticky column header for result windows while preserving
  normal- and visual-mode access to the real header row.
- Added result winbar row counts and SQL Tools Service batch durations, with
  limited results showing both displayed and total rows.

### Changed

- Increase the default result limit from 100 to 1,000 rows.
- Limit Excel export to `.xlsx` because SQL Tools Service produces OOXML rather
  than the legacy `.xls` binary format.
- Replace the custom Lua test harness with pinned `mini.test` runners, focused
  case filtering, and isolated SQL integration fixtures.
- Pin SQL Tools Service 6.0.20260902.1 and install its .NET 10 artifacts.
- Preserve SQL Tools Service error text and expose its structured, absolute
  `errorSelection` to activity events and custom message viewers.
- Execute visual selections and complete SQL buffers as synchronized document
  ranges so SQL Tools Service retains their source context. Arbitrary SQL text
  supplied through the public API continues to use string execution.
- Reorganized connection, query, result, object, workspace, configuration, and
  SQL Tools Service modules by product capability, with normalized metadata at
  the adapter boundary.
- Open SQL Tools Service CSV, JSON, and XML exports in editable, unsaved Neovim
  buffers; keep binary XLSX as a direct file export.
- Rename the interactive `SaveQueryResults` command to `ExportQueryResults`.
- Require and test against Neovim 0.11.7 to include later 0.11 crash fixes.
- Standardize result-history terminology on "execution" and keep changing
  result metadata separate from right-aligned history navigation.
- Expand usage documentation with an annotated workspace guide, buffer-specific
  workflows, and an embedded showcase GIF.
- Skip GitHub Actions when a push or pull request changes documentation only.

### Fixed

- Include the final selected character when executing visual selections and
  complete buffers through SQL Tools Service document ranges.
- Reject exports from stale or disposed result locators instead of allowing a
  historical result to address newer SQL Tools Service query storage.
- Assign unique temporary names to directly-created unnamed SQL buffers so
  their LSP documents, connections, and executions remain isolated.
- Stop cleanly when connection selection is cancelled instead of attempting to
  load database objects and reporting an error.

## [1.0.0-rc.2] - 2026-09-02

### Added

- Added a result-specific winbar showing the source buffer, retained execution,
  and result-set position.
- Added per-source result history with configurable retention and navigation
  between successful executions.
- Added a buffer-local `<keymap_prefix>s` mapping to export the current
  `sqlserver-result` buffer when default mappings are enabled.
- Added schema-qualified object-definition buffer names, secret-free object
  metadata, and focus-or-duplicate handling for name collisions.
- Added `<keymap_prefix>v` and `:SQLServer ShowResults` to focus or reopen the
  latest result session at its last viewed result set.

### Changed

- Centralized the `mssql_ls` Neovim LSP client identifier so adapter startup,
  client lookup, and integration tests use the same value.
- Limited the result-buffer which-key group to result actions and clarified the
  export filename prompt and validation messages.
- Added overwrite confirmation to interactive result exports while preserving
  explicit overwrite behavior in the public Lua API.

### Fixed

- Prevented error-only query executions from opening an empty result split.

## [1.0.0-rc.1] - 2026-09-01

### Added

- A SQL Server-native public Lua API for connections, queries, cancellation,
  object discovery and scripting, and result export.
- Statement, visual-selection, and complete-buffer query execution.
- Dedicated result models, renderers, buffers, navigation, and CSV/JSON export.
- Multiple and partial result-set handling with per-error notifications.
- Query cancellation, configurable operation timeouts, and connection recovery.
- Searchable table, view, procedure, scalar-function, and table-valued-function
  metadata with query and definition scripting.
- Replaceable structured activity presentation with a configurable winbar.
- Environment-backed, validated, and secret-safe connection profiles.
- Pinned, staged, and validated SQL Tools Service installation.
- Docker-backed integration tests for the complete query and object workflow.
- Cross-platform unit CI, Linux integration CI, process-leak assertions, and a
  documented `1.0.0` release and manual-acceptance checklist.

### Changed

- Reorganized the inherited `mssql.nvim` implementation around workspace,
  adapter, model, public API, and Neovim view boundaries.
- Made compatibility with `mssql.nvim` explicitly outside the public contract.

### Removed

- Inherited public API and configuration compatibility that conflicted with the
  `sqlserver.nvim` architecture.

[1.0.0-rc.4]: https://github.com/NicholasMata/sqlserver.nvim/compare/v1.0.0-rc.3...v1.0.0-rc.4
[1.0.0-rc.3]: https://github.com/NicholasMata/sqlserver.nvim/compare/v1.0.0-rc.2...v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/NicholasMata/sqlserver.nvim/compare/v1.0.0-rc.1...v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/NicholasMata/sqlserver.nvim/releases/tag/v1.0.0-rc.1
