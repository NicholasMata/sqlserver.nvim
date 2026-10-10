# Public Lua API

Call `require("sqlserver").setup()` before using the API. Asynchronous methods
take a final callback with the same signature:

```lua
function(result, err)
  if err then
    vim.notify(err.message, vim.log.levels.ERROR)
    return
  end
  -- use result
end
```

`setup(opts, callback)` follows this convention as well. Its result is `true`
after setup completes, and installation or configuration failures are returned
immediately through `err` instead of only being displayed as notifications.

The callback runs exactly once. Errors are tables with `code`, `message`, and an
optional redacted `cause`. API methods do not prompt, open result windows, or
turn failures into notifications. The explicit `open_plan()` method opens
a plan XML window. Ex commands and mappings use separate UI
handlers available under `require("sqlserver").commands`.

## Connections

Connect an existing SQL buffer using either a profile name from
`connections.json` or a profile table:

```lua
sqlserver.connect("development", { bufnr = 0 }, function(connection, err)
  -- connection never contains password or Azure access-token fields
end)
```

Options for `connect(profile, opts, callback)` are:

- `bufnr`: target SQL buffer; defaults to the current buffer;
- `profile_name`: diagnostic name for a profile table;
- `refresh_objects`: set to `false` to skip the initial metadata load.

Use `disconnect(bufnr, callback)` and `reconnect(bufnr, callback)` for lifecycle
operations. `current_connection(bufnr)` is synchronous and returns
`connection, err`; it returns `nil, nil` when the workspace is disconnected.
Connected snapshots include `username` when SQL Tools Service reports one and
never include passwords or access tokens.

## Query Execution

`execute(opts, callback)` supports these forms:

```lua
sqlserver.execute({ bufnr = 0 }, callback) -- statement under cursor
sqlserver.execute({ bufnr = 0, scope = "buffer" }, callback)
sqlserver.execute({ bufnr = 0, text = "SELECT 1" }, callback)
```

The result contains `cancelled`, a normalized `summary`, `result_sets`, and an
idempotent `dispose()` function.
Result sets contain columns, typed cells, total and displayed row counts,
truncation state, ordinal, and an opaque locator. No result buffers are opened.
Call `dispose()` after finishing exports or other operations that use an opaque
result locator. Built-in result views do this automatically when their
execution is removed, evicted from history, or deleted with its source buffer.
Starting a new query for the same buffer also releases the previous SQL Tools
Service query because the backend retains only one query per document URI.

Request cancellation with `cancel(bufnr, callback)`. It cancels the active
query or object-scripting operation owned by the workspace. The callback
confirms the request; the operation callback completes after SQL Tools Service
reports cancellation.

## Execution plans

Use the `plan` option on `execute()` for the same statement, selection,
buffer, and explicit-text scopes:

```lua
sqlserver.execute({ bufnr = 0, scope = "buffer", plan = "estimated" }, function(execution, err)
  if err or execution.cancelled then return end
  local plan = execution.plans[1]
  if not plan then return end -- plan_status == "none"
  sqlserver.open_plan({ plan = plan }, function(view, open_error) end)
  sqlserver.export_plan({ plan = plan, path = "/tmp/query.sqlplan" }, function(saved, save_error) end)
end)
```

`plan = "estimated"` does not execute SQL. `plan = "actual"` executes it
once and collects runtime plans alongside ordinary results. The callback
result includes `plans` and `plan_status` (`"captured"` or `"none"`).
Ordinary executions return an empty `plans` list without a `plan_status`.
Plan result sets do not contribute to summary row/result counts or table
results. Cancellation returns `cancelled = true` without publishing plans.
Permission, retrieval, unsupported-response, and malformed-response failures
return structured errors, separately from a successful no-plan result.

Each snapshot contains:

- `xml`: original, unformatted Showplan XML;
- `kind`: `"estimated"` or `"actual"`;
- `ordinal`: one-based plan position;
- `batch_index` and `result_index`: zero-based identities within the execution;
- `batch_range`: zero-based `start_line`, `start_column`, `end_line`,
  and `end_column` when the service reports the executed batch range;
- `source_bufnr` and `execution_id`: originating workspace and its execution ID;
- `connection`: source connection/database context captured before execution,
  with passwords and access tokens removed.

A document may contain multiple statements. `batch_range` describes the
batch, not a per-statement range. Plan ordinals identify documents, not
individual XML operators or statements. Execution IDs are local to each
workspace. Captured snapshots remain usable after service-side query
disposal, subsequent execution, or disconnect.

`open_plan({ plan = snapshot }, callback)` opens a separate read-only XML
buffer and returns `{ bufnr }`. Closing its window wipes the temporary
view; deleting its source also clears it. The snapshot itself remains owned
by the caller. No connection is required.

`export_plan({ plan = snapshot, path = "...sqlplan", overwrite = false }, callback)`
returns `{ path, format = "sqlplan" }`. Paths must end in `.sqlplan`.
It writes the captured XML bytes directly as UTF-8, preserving whitespace
and Unicode, with no SQL execution or table export. Existing files are
rejected unless `overwrite = true`; replacement uses a temporary sibling
file so failed writes preserve the existing file.

Plan retrieval uses `timeouts.export`; execution uses `timeouts.query`.
The workspace stays busy through plan and result collection, preventing a
new query from invalidating in-progress retrieval. Built-in commands retain
plan views in the same bounded history as results; public API callers own
their returned snapshots and may release backend query storage with
`execution.dispose()` while retaining the XML.

## Objects

The 1.0 object model includes a searchable snapshot of tables, views, stored
procedures, scalar functions, and table-valued functions in the connected
database. When Snacks is available, Object Explorer also presents the
hierarchy returned by SQL Tools Service.

`list_objects(opts, callback)` returns metadata-cache descriptors containing
`id`, `name`, `schema`, `type`, and `path`. Filter with `name`, `schema`, or
`type`, and pass `bufnr` to select the workspace. During a forced refresh, the
last successful snapshot remains readable. Before the first snapshot is ready,
listing returns a `metadata_refreshing` error.

Use `refresh_objects(bufnr, callback)` to replace the complete snapshot. A
refresh superseded by another refresh completes with `cancelled = true`.

Use a returned descriptor to avoid ambiguous names:

```lua
sqlserver.script_object({
  bufnr = 0,
  object = object,
  intent = "definition", -- or "query"
}, callback)
```

Only `query` and `definition` are supported intents. `ALTER`, `DROP`, and
individual tree-node refresh are deliberately outside the 1.0 contract. The
returned script includes the resolved public object descriptor alongside its
SQL text and execution metadata.

## Result Export

`export_results(opts, callback)` writes a public API result set without a file
picker:

```lua
sqlserver.export_results({
  result_set = execution.result_sets[1],
  path = "/tmp/result.csv",
  selection = {
    row_start = 0,
    row_end = 9,
    column_start = 1,
    column_end = 3,
  },
}, callback)
```

Supported formats are `csv`, `json`, `xml`, and `xlsx`. The format is inferred
from `path` unless `format` is supplied. A result-buffer number may be provided
as `bufnr` instead of `result_set`. `selection` is optional; its row and column
bounds are zero-based and inclusive.

## Interactive Commands

The existing interactive Lua handlers remain available under
`sqlserver.commands`, such as `sqlserver.commands.connect()` and
`sqlserver.commands.execute_query()`. Calling `sqlserver.connect()` without a
profile also invokes the interactive connection picker for convenience.
