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

- Highlight only the trailing ellipsis in clipped result cells so the value
  keeps its normal color before opening the cell inspector.

- Open cell values in regular buffers with `InspectCellBuffer` or the result
  prefix plus `V`; use the plugin prefix plus `o` to promote floats and `f`
  to toggle raw/formatted content. The inspector menu shows only cell actions
  and preserves native Vim keys except `q` and Escape for closing. Use standard
  selection and yanking in either view.
- Inspect result cells with Enter, the result-local prefix plus `v`, or
  `InspectCell`, with explicit XML/JSON commands and the `inspect_cell()` Lua
  API. Focused read-only floats preserve original values for copying, report
  SQL NULL/empty values and service storage limits, and follow retained-result
  ownership. Configured Neovim formatting affects presentation only.

- Add an Alerts branch, read-only alert properties, `:SQLServer Alerts`,
  and a UI-independent `list_alerts` callback API. Include independent
  alerts in Search All and preserve properties during failed refreshes.
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

- Keep concatenated `FOR JSON` / `FOR XML` results copyable beyond scalar
  storage limits and detect JSON per text cell instead of using a first-row
  hint. Preserve JSON filetype and skip feedback for `FOR JSON` above 1 MiB.
  Failed cell-float promotion restores focus and scratch-buffer cleanup.

- Filter `:SQLServer` command completion by the typed prefix, ignoring case
  while preserving context-sensitive suggestions and command capitalization.

[Unreleased]: https://github.com/NicholasMata/sqlserver.nvim/compare/v1.0.0...next
