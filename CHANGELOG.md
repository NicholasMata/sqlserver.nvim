# Changelog

All notable changes to `sqlserver.nvim` will be documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
releases use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/NicholasMata/sqlserver.nvim/compare/v1.0.0-rc.1...HEAD
[1.0.0-rc.1]: https://github.com/NicholasMata/sqlserver.nvim/releases/tag/v1.0.0-rc.1
