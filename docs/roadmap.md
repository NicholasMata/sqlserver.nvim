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

- Connection profiles with environment-variable support.
- New query buffers bound to a connection and database.
- Execute current statement, visual selection, or whole buffer.
- Cancel running query.
- Split messages/errors from tabular results.
- Handle multiple result sets.
- Export results to CSV and JSON.
- Apply row limits and truncation consistently.

## Phase 2: Object Workflow

- Object explorer for servers, databases, schemas, tables, views, procedures,
  and functions.
- Refresh individual nodes.
- Search objects by name.
- Script object as `CREATE`, `ALTER`, `DROP`, and `SELECT` where supported.
- Open definitions in editable buffers.

## Phase 3: Language Intelligence

- Harden SQL Tools Service startup and version handling.
- Completion compatibility with `nvim-cmp` and `blink.cmp`.
- Signature help and hover without invalid `vim.NIL` values.
- Go to definition where SQL Tools Service provides useful locations.
- Formatting with user-configurable SQL Tools Service settings.

## Phase 4: Public API

- `connect(profile)`
- `disconnect(bufnr)`
- `current_connection(bufnr)`
- `execute(opts)`
- `cancel(bufnr)`
- `list_objects(opts)`
- `script_object(opts)`
- `export_results(opts)`

The API should be useful both for user config and for future MCP/agent
integration.

## Later

- Execution-plan capture and readable summaries.
- Optional MCP integration.
- Query history and saved query library.
- Read-only/admin mode distinction.
- Lightweight template/snippet explorer.
- Performance investigation helpers using DMVs.
