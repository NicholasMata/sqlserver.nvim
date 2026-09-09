# Usage

`sqlserver.nvim` commands use the form `:SQLServer <command>`. When
`keymap_prefix` is configured, the mappings below are added after that prefix.
Command completion includes only actions valid for the current workspace state.

## Workspace layout

<p align="center">
  <img src="assets/workspace-layout-annotated.png" alt="Annotated sqlserver.nvim query and result workspace" width="800">
</p>

| Label | Term | Meaning |
| --- | --- | --- |
| 1 | Query buffer | Editable `sql` buffer that owns its connection, active execution, and retained result history |
| 2 | Workspace winbar | Neovim's built-in per-window bar showing the connected server, database, and current state |
| 3 | Result view | Reusable Neovim window displaying one `sqlserver-result` buffer at a time |
| 4 | Result winbar | Identifies the source query and the active execution and result-set positions |
| 5 | Column header | Real first buffer row; a non-focusable sticky copy remains visible when this row scrolls away |

A buffer owns text and plugin state; a window displays a buffer. Query and
result buffers remain tied together even when either buffer is hidden or shown
in a different window. One query execution can produce several result sets, and
each result set has its own result buffer. A retained sequence of those
executions is the query buffer's result history.

## SQL buffer workflow

| Vim Mode | Mapping | Command | Behavior |
| --- | --- | --- | --- |
| Normal | `<keymap_prefix>n` | `NewQuery` | Open a new SQL query buffer |
| Normal | `<keymap_prefix>d` | `NewDefaultQuery` | Open a query using the `default` connection profile |
| Normal | `<keymap_prefix>e` | `EditConnections` | Edit connection profiles |
| Normal | `<keymap_prefix>c` | `Connect` | Connect the current query buffer |
| Normal | `<keymap_prefix>R` | `Reconnect` | Retry the query buffer's previous connection |
| Normal | `<keymap_prefix>q` | `Disconnect` | Disconnect the current query buffer |
| Normal | `<keymap_prefix>s` | `SwitchDatabase` | Change database on the connected server |
| Normal | `<keymap_prefix>x` | `ExecuteQuery` | Execute the statement under the cursor |
| Visual | `<keymap_prefix>x` | `ExecuteQuery` | Execute the selected text |
| Normal | `<keymap_prefix>X` | `ExecuteBuffer` | Execute the complete buffer |
| Normal | `<keymap_prefix>l` | `CancelQuery` | Cancel the active query |
| Normal | `<keymap_prefix>v` | `ShowResults` | Reopen the active retained execution |
| Normal | `<keymap_prefix>f` | `Find` | Build a query for a selected database object |
| Normal | `<keymap_prefix>o` | `ObjectDefinition` | Open a selected database object's definition |
| Normal | `<keymap_prefix>r` | `RefreshCache` | Refresh object and IntelliSense metadata |
| Normal | `<keymap_prefix>a` | `Activity` | Toggle workspace activity |

If a disconnected query is executed, the plugin attempts to use the connection
profile named `default`. Current-statement parsing is delegated to SQL Tools
Service.

## Result view workflow

Every SQL source buffer retains its own recent successful executions in memory.
Each execution can contain one or more `sqlserver-result` buffers, displayed in
a reusable results window. Unless noted otherwise, these mappings run from a
result buffer:

| Vim Mode | Mapping | Command | Behavior |
| --- | --- | --- | --- |
| Normal | `]r` | `NextResult` | Show the next result set in the execution |
| Normal | `[r` | `PreviousResult` | Show the previous result set in the execution |
| Normal | `<keymap_prefix>n` | `NextExecution` | Show the next retained execution |
| Normal | `<keymap_prefix>p` | `PreviousExecution` | Show the previous retained execution |
| Normal | `]c` | — | Move to the next result column |
| Normal | `[c` | — | Move to the previous result column |
| Normal | `K` | — | Inspect the current column's SQL type and metadata |
| Normal | `<keymap_prefix>d` | `RemoveResult` | Remove the current result after confirmation |
| Normal | `<keymap_prefix>s` | `ExportQueryResults` | Export the complete result set |
| Visual | `<keymap_prefix>s` | `ExportQueryResults` | Export the selected rows and columns |
| Visual | `<keymap_prefix>y` | — | Copy the selected cells as a rich HTML table |
| Normal | — | `CopyResultCell` | Copy the complete value under the cursor; command only |

### Result history

Executing again activates a new execution without deleting older result
buffers. `results.history_limit` controls how many executions are retained for
each source buffer. Deleting the source buffer discards its complete history.

### Result winbar

The result winbar identifies the source SQL buffer and shows the current
execution and result-set positions. For example, `Run 2/4  Result 1/2` means the
view is showing the first result set from the second of four retained
executions.

### Removing results

Removing a result selects the nearest remaining result. Removing the final
result in an execution removes that execution; removing the final retained
result also closes the results view.

### Columns and sticky header

Column inspection displays compact types such as `varchar(100) NULL` or
`decimal(12, 2) NOT NULL`, plus source-object metadata when SQL Tools Service
provides it. The sticky header keeps column names visible while scrolling and
can be disabled with `results.sticky_header = false`.

### Copying and exporting

Copy and export actions use complete underlying cell values rather than
display-width-truncated text. Rich HTML clipboard copy includes the selected
headings and uses native macOS and Windows facilities; Linux requires `wl-copy`
or `xclip`.

CSV, JSON, and XML exports open as modified, unsaved buffers. Edit them if
needed and use Neovim's normal `:write` command to save them. Binary Excel
`.xlsx` exports ask for a destination and write directly. Visual exports use
the rectangular range covered by the selection; linewise selections include
every column. Result mappings that use `keymap_prefix` are omitted when no
prefix is configured.

### Limits and value fidelity

When the configured row limit is reached, the buffer reports how many rows are
shown. Cell-width truncation affects only the rendered table. Database `NULL`
remains distinct from the string `"NULL"`, and Unicode, decimal, datetime,
binary, and invariant-culture values are preserved when SQL Tools Service
provides them.

### SQL errors and batches

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

### Cancellation and cleanup

An intentional cancellation remains in progress until SQL Tools Service
reports completion, after which the connected buffer can execute again. A
query timeout also requests server-side cancellation but leaves the workspace
disconnected because execution state cannot be confirmed. Use `Reconnect`
before running another query.

Connection, authentication, TLS, unreachable-server, timeout, and service
failures have distinct secret-safe messages. Detailed redacted diagnostics are
retained in activity history. Deleting a SQL buffer disposes its connection;
leaving Neovim stops plugin-owned SQL Tools Service clients.

## Activity view

| Vim Mode | Mapping | Command | Behavior |
| --- | --- | --- | --- |
| Normal | `q` | — | Close the activity view |

A mixed query outcome uses a warning state while each underlying SQL error
remains an error; an error-only execution uses the failed state.

## Language features

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
scalar functions, and table-valued functions in the connected database. Its
actions are invoked from the SQL buffer and are listed in the SQL buffer
workflow table above.

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
| `ExportQueryResults` | Export the current result set |
| `ShowResults` | Focus or reopen the current SQL buffer's active execution |
| `NextResult` | Display the next result set |
| `PreviousResult` | Display the previous result set |
| `NextExecution` | Display the next retained execution |
| `PreviousExecution` | Display the previous retained execution |
| `RemoveResult` | Remove the current result set and any execution it leaves empty |
| `CopyResultCell` | Copy the complete value under the cursor from a result set |
| `BackupDatabase` | Insert a database backup command |
| `RestoreDatabase` | Insert a database restore command |

See [Configuration](configuration.md) for setup options and UI customization,
and [Public Lua API](public-api.md) for UI-independent automation.
