# Vision

`sqlserver.nvim` is a SQL Server-native workspace for Neovim.

It should help users stay in Neovim for the daily SQL Server workflow: connect,
browse schema, write T-SQL, execute queries, inspect results, script objects,
and use SQL Server-aware language intelligence.

It is not an SSMS clone. SSMS is a broad administrative product with designers,
wizards, SQL Agent management, backup and restore workflows, Activity Monitor,
Query Store reports, security UI, diagrams, import/export wizards, and many
other specialized surfaces. `sqlserver.nvim` should focus on the parts that
make sense in a text editor and terminal-first workflow.

## Product Bet

The future database workflow is likely a combination of:

- LSP for editor intelligence
- MCP for agent access to schemas, queries, plans, and metadata
- SQL as the reviewable artifact
- Neovim as the control surface for editing, execution, and verification

Plain English will be useful for exploration and generation, but serious
database work still needs visible SQL, reviewable changes, repeatable scripts,
permissions, limits, and auditability.

## Core Loop

The first-class workflow is:

1. Choose or create a connection profile.
2. Open a query buffer tied to a connection and database.
3. Browse or search objects from the current connection.
4. Write or generate T-SQL with language intelligence.
5. Execute the current statement, selection, or buffer.
6. View messages, errors, timings, and multiple result sets.
7. Export or script the useful output.

This loop should be boringly reliable before adding broad management features.

## Architecture Principles

- Keep UI separate from backend adapters.
- Treat SQL Tools Service as a backend with quirks, not as the whole product.
- Prefer stable internal Lua APIs over direct coupling between commands and
  protocol calls.
- Make read-only and destructive operations explicit in the UX and APIs.
- Preserve exact SQL wherever possible so users can review and repeat work.
- Keep the initial surface small enough to maintain.

## Backend Direction

Use Microsoft SQL Tools Service where it is valuable:

- completion
- diagnostics
- hover
- signature help
- formatting
- definitions and object scripting, if reliable

Do not assume SQL Tools Service must own everything. Query execution and metadata
may eventually move behind separate adapters if a driver-backed helper gives
better cancellation, result structure, parameters, or multiple result-set
support.

## Non-Goals

These are explicitly out of scope for the early project:

- full SSMS clone
- table designer
- visual query builder
- database diagrams
- SQL Agent management
- backup and restore UI
- security and login management UI
- Query Store dashboards
- Activity Monitor clone
- replication or AlwaysOn administration
- broad multi-database support

