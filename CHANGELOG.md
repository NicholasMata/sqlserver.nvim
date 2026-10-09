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

- Mark result views with an eye icon `󰈈` when their source query is visible
  in the current tab, or `󰈉` when hidden, keeping winbar spacing stable.
  Customize the hidden icon through `SqlServerSourceHidden`, which defaults
  to `DiagnosticWarn`.
  Use `ShowQuery` or the result-local
  `<keymap_prefix>o` to return to it.
- Restore a hidden source query in its original window with `ShowQuery`, or
  recreate the window opposite the preferred result split if it has closed.

### Fixed

- Filter `:SQLServer` command completion by the typed prefix, ignoring case
  while preserving context-sensitive suggestions and command capitalization.

[Unreleased]: https://github.com/NicholasMata/sqlserver.nvim/compare/v1.0.0...next
