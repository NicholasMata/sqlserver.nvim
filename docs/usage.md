# Usage

`sqlserver.nvim` commands use the form `:SQLServer <command>`. When
`keymap_prefix` is configured, the mappings below are added after that prefix.
Command completion includes only actions valid for the current workspace state.

## Daily workflow

| Default suffix | Command | Behavior |
| --- | --- | --- |
| `n` | `NewQuery` | Open a new SQL query buffer |
| `d` | `NewDefaultQuery` | Open a query using the `default` connection profile |
| `c` | `Connect` | Connect the current query buffer |
| `R` | `Reconnect` | Retry the query buffer's previous connection |
| `q` | `Disconnect` | Disconnect the current query buffer |
| `x` | `ExecuteQuery` | Execute the statement under the cursor |
| visual `x` | `ExecuteQuery` | Execute the selected text |
| `X` | `ExecuteBuffer` | Execute the complete buffer |
| `l` | `CancelQuery` | Cancel the active query |
| `a` | `Activity` | Toggle workspace activity |

If a disconnected query is executed, the plugin attempts to use the connection
profile named `default`. Current-statement parsing is delegated to SQL Tools
Service.

## Query results and errors

Every SQL source buffer retains its own recent successful executions in memory.
Each execution can contain one or more `sqlserver-result` buffers, displayed in
a reusable results window. `:SQLServer ShowResults` or `<keymap_prefix>v`
restores the active execution belonging to the current SQL buffer.

Use `]r`, `[r`, `:SQLServer NextResult`, or `:SQLServer PreviousResult` to move
between result sets from one execution. From a result buffer, use
`<keymap_prefix>n`, `<keymap_prefix>p`, `:SQLServer NextExecution`, or
`:SQLServer PreviousExecution` to move between retained executions. Executing
again selects the new execution without deleting the older result buffers.
`results.history_limit` controls how many executions are retained per source
buffer; deleting the source buffer discards its complete result history.
The result winbar identifies the source buffer and shows both positions, such
as `Run 2/4  Result 1/2`.

Each result can be saved independently with the buffer-local
`<keymap_prefix>s` mapping or `:SQLServer SaveQueryResults`. No result-buffer
mappings using `keymap_prefix` are created when that option is disabled.

When the configured row limit is reached, the buffer reports how many rows are
shown. Cell-width truncation affects only the rendered table. Database `NULL`
remains distinct from the string `"NULL"`, and Unicode, decimal, datetime,
binary, and invariant-culture values are preserved when SQL Tools Service
provides them.

Successful result sets are retained when another batch raises an error. Empty
result slots from failed batches are omitted, but surviving buffer names retain
their execution ordinal; if the first batch fails and the second succeeds, the
buffer is named `results 2.sqlresult`. Every SQL Server error also produces a
Neovim error notification.

Statements without a `GO` separator execute as one SQL Server batch. A
batch-terminating error may prevent later statements from running. Use `GO` to
run later statements as independent batches; the plugin does not silently
split T-SQL because that would change variable, transaction, temporary-table,
and other batch semantics.

An intentional cancellation remains in progress until SQL Tools Service
reports completion, after which the connected buffer can execute again. A
query timeout also requests server-side cancellation but leaves the workspace
disconnected because execution state cannot be confirmed. Use `Reconnect`
before running another query.

Connection, authentication, TLS, unreachable-server, timeout, and service
failures have distinct secret-safe messages. Detailed redacted diagnostics are
retained in activity history. Deleting a SQL buffer disposes its connection;
leaving Neovim stops plugin-owned SQL Tools Service clients.

## Activity and language features

Open the activity view with `:SQLServer Activity` or the `a` suffix and press
`q` inside it to close it. A mixed query outcome uses a warning state while each
underlying SQL error remains an error; an error-only execution uses the failed
state.

SQL Tools Service attaches through Neovim's standard LSP client, so existing
completion, diagnostics, hover, signature-help, definition, and formatting
integrations continue to work. Neovim identifies the client as `mssql_ls` in
LSP status and health output. For example:

```lua
vim.keymap.set("n", "K", vim.lsp.buf.hover)
vim.keymap.set("n", "gd", vim.lsp.buf.definition)
vim.keymap.set("i", "<C-s>", vim.lsp.buf.signature_help)
vim.keymap.set("n", "<leader>f", function()
  vim.lsp.buf.format({ async = true })
end)
```

Schema-aware results become available after connection and IntelliSense
readiness. `:SQLServer RefreshCache` rebuilds both object and IntelliSense
metadata for the current connection.

## Object workflow

The object picker searches a snapshot of tables, views, stored procedures,
scalar functions, and table-valued functions in the connected database.

| Default suffix | Command | Behavior |
| --- | --- | --- |
| `f` | `Find` | Build `SELECT` SQL for a table/view or `EXEC` SQL for a procedure |
| `o` | `ObjectDefinition` | Open the selected object's editable definition |
| `r` | `RefreshCache` | Refresh object and IntelliSense metadata |

Generated table and view queries execute immediately by default. Procedure
calls are inserted but never executed automatically because they may have side
effects. Definitions use `CREATE` scripting and open in dedicated editable SQL
buffers named `<schema>.<object>.sql`. If that name is already open, choose to
focus it or create a numbered buffer such as `dbo.Person (2).sql`.
Individual-node refresh and generic `ALTER`/`DROP` actions are outside the 1.0
scope.

## Command reference

| Command | Purpose |
| --- | --- |
| `Activity` | Toggle workspace activity |
| `Connect` | Connect the current query buffer |
| `Reconnect` | Retry the query buffer's previous connection |
| `Disconnect` | Disconnect the current query buffer |
| `ExecuteQuery` | Execute the statement under the cursor or selected text |
| `ExecuteBuffer` | Execute the complete buffer |
| `CancelQuery` | Cancel the active query |
| `NewQuery` | Open a query buffer |
| `NewDefaultQuery` | Open a query using the `default` profile |
| `SwitchDatabase` | Change database on the current server |
| `Find` | Build a runnable query for a database object |
| `ObjectDefinition` | Script a database object's definition |
| `RefreshCache` | Refresh metadata and IntelliSense caches |
| `EditConnections` | Edit connection profiles |
| `SaveQueryResults` | Export the current result set |
| `ShowResults` | Focus or reopen the current SQL buffer's active execution |
| `NextResult` | Display the next result set |
| `PreviousResult` | Display the previous result set |
| `NextExecution` | Display the next retained execution |
| `PreviousExecution` | Display the previous retained execution |
| `BackupDatabase` | Insert a database backup command |
| `RestoreDatabase` | Insert a database restore command |

See [Configuration](configuration.md) for setup options and UI customization,
and [Public Lua API](public-api.md) for UI-independent automation.
