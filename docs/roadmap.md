# Roadmap

## Phase 0: Stabilize The Base

- Rename public module and docs from `mssql` to `sqlserver`.
- Keep the SQL Tools Service executable/client name where required.
- Remove inherited API and configuration constraints; compatibility with
  `mssql.nvim` is not a goal.
- Document the inherited architecture and known protocol quirks.
- Keep the LSP null sanitizer until SQL Tools Service responses are normalized
  upstream.
- Make the test runner work from the new repo name.

## Phase 1: Reliable Query Workflow

- Validated connection profiles with environment-variable support and
  secret-safe errors.
- New query buffers bound to a connection and database.
- Execute current statement, visual selection, or whole buffer.
- Cancel running query.
- Detect connection loss and reconnect with the previous profile.
- Split messages/errors from tabular results.
- Preserve multiple and partial result sets when a batch reports an error.
- Export results to CSV and JSON.
- Preserve typed cell metadata and apply row limits and truncation consistently.
- Normalize SQL Tools Service batch timings in query activity.
- Dispose buffer connections and SQL Tools Service processes deterministically.

## Phase 2: Object Workflow

- Object explorer for servers, databases, schemas, tables, views, procedures,
  and functions.
- Refresh individual nodes.
- Search objects by name.
- Script object as `CREATE`, `ALTER`, `DROP`, and `SELECT` where supported.
- Open definitions in editable buffers.

## Phase 3: Language Intelligence

- Harden SQL Tools Service startup and version handling.
- Preserve standard Neovim LSP behavior rather than owning a parallel UI.
- Keep completion compatible with Neovim's LSP completion consumers.
- Sanitize malformed SQL Tools Service completion and signature responses.
- Verify diagnostics, hover, signature help, definitions, and formatting across
  connection and database changes.

## Phase 4: Public API

- `connect(profile, opts, callback)`
- `disconnect(bufnr, callback)` and `reconnect(bufnr, callback)`
- `current_connection(bufnr)`
- `execute(opts, callback)`
- `cancel(bufnr, callback)`
- `list_objects(opts, callback)`
- `script_object(opts, callback)`
- `export_results(opts, callback)`

The API uses explicit buffers, structured errors, secret-free connection
snapshots, and UI-independent result models so it is useful both for user
config and future MCP/agent integration.

## Later

- Execution-plan capture and readable summaries.
- Optional MCP integration.
- Query history and saved query library.
- Read-only/admin mode distinction.
- Lightweight template/snippet explorer.
- Performance investigation helpers using DMVs.
