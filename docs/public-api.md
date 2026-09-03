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

The callback runs exactly once. Errors are tables with `code`, `message`, and an
optional redacted `cause`. API methods do not prompt, open result windows, or
turn failures into notifications. Ex commands and mappings use separate UI
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

## Query Execution

`execute(opts, callback)` supports these forms:

```lua
sqlserver.execute({ bufnr = 0 }, callback) -- statement under cursor
sqlserver.execute({ bufnr = 0, scope = "buffer" }, callback)
sqlserver.execute({ bufnr = 0, text = "SELECT 1" }, callback)
```

The result contains `cancelled`, a normalized `summary`, and `result_sets`.
Result sets contain columns, typed cells, total and displayed row counts,
truncation state, ordinal, and an opaque locator. No result buffers are opened.

Request cancellation with `cancel(bufnr, callback)`. The callback confirms the
request; the query's execution callback completes after SQL Tools Service
reports cancellation.

## Objects

The 1.0 object model is a searchable snapshot of tables, views, stored
procedures, scalar functions, and table-valued functions in the connected
database. It is not a hierarchical server explorer.

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
}, callback)
```

Supported formats are `csv`, `json`, `xml`, `xls`, and `xlsx`. The format is
inferred from `path` unless `format` is supplied. A result-buffer number may be
provided as `bufnr` instead of `result_set`.

## Interactive Commands

The existing interactive Lua handlers remain available under
`sqlserver.commands`, such as `sqlserver.commands.connect()` and
`sqlserver.commands.execute_query()`. Calling `sqlserver.connect()` without a
profile also invokes the interactive connection picker for convenience.
