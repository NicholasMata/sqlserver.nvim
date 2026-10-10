# Changelog

This file tracks unreleased changes to `sqlserver.nvim`. For published release
history, see [GitHub Releases](https://github.com/NicholasMata/sqlserver.nvim/releases).
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
releases use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Add user-visible changes under `Unreleased` on `next`. Remove entries only after
the corresponding GitHub release is published, preserving changes intended for
later releases.

## [Unreleased]

### Added

- Add read-only SQL Agent Jobs to Object Explorer and a callback API for
  jobs. Inspect steps, schedules, and linked alerts in a scrollable Job
  Properties window, and search job history in a separate picker that opens
  selected runs in a scrollable float. Refresh actions report failures without
  discarding cached details.
- Mark result views with an eye icon `󰈈` when their source query is visible
  in the current tab, or `󰈉` when hidden, keeping winbar spacing stable.
  Customize the hidden icon through `SqlServerSourceHidden`, which defaults
  to `DiagnosticWarn`.
  Use `ShowQuery` or the result-local
  `<keymap_prefix>o` to return to it.
- Restore a hidden source query in its original window with `ShowQuery`, or
  recreate the window opposite the preferred result split if it has closed.
- Capture estimated and actual execution plans for statements, selections,
  and complete SQL buffers. Retain original XML with execution history, open
  syntax-highlighted XML views using a configured Neovim XML formatter,
  and save byte-preserving `.sqlplan` files.
- Add plan capture options to `execute()` and `open_plan()`/`export_plan()`
  public API workflows.
- Focus the captured XML plan after `EstimatedPlan` and `EstimatedPlanBuffer`,
  while respecting Neovim's split placement preferences.
- Disable spell checking in execution-plan windows by default; users can
  enable it locally with `:setlocal spell`.
- Show `Plan` or `Est. plan` beside the source query and use a shared position
  counter for table results and plans, followed by the execution counter.
- Support configured execution navigation, source-query restoration, and
  removal shortcuts in plan buffers without changing XML cursor movement.
- Show plan actions in WhichKey and use `ExportPlan` or the result export
  shortcut to export the original XML as `.sqlplan`, suggesting a filename
  based on the source query, plan kind, and plan number.

### Fixed

- Filter `:SQLServer` command completion by the typed prefix, ignoring case
  while preserving context-sensitive suggestions and command capitalization.

[Unreleased]: https://github.com/NicholasMata/sqlserver.nvim/compare/v1.0.0...next
