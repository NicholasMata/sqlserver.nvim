# Migrating from mssql.nvim

`sqlserver.nvim` began with code from
[`Kurren123/mssql.nvim`](https://github.com/Kurren123/mssql.nvim), but it is a
separate plugin with intentionally incompatible APIs and configuration. This
guide describes the user-visible differences in the current implementation.

## Installation and module names

Replace the plugin repository and Lua module:

```lua
-- Before
{
  "Kurren123/mssql.nvim",
  opts = { keymap_prefix = "<leader>m" },
}

-- After
{
  "NicholasMata/sqlserver.nvim",
  opts = { keymap_prefix = "<leader>s" },
}
```

Direct Lua calls move from `require("mssql")` to `require("sqlserver")`.
Commands move from `:MSSQL <command>` to `:SQLServer <command>`. There are no
compatibility aliases for the old names.

The default data directory also moves from `mssql.nvim` to `sqlserver.nvim`
under `vim.fn.stdpath("data")`. Copy an existing `connections.json` into the
new directory or set `connections_file` to its existing path. SQL Tools Service
will be downloaded into the new data directory unless `tools_file` points to an
existing executable.

## Configuration changes

The connection JSON shape, `keymap_prefix`, `open_results_in`,
`execute_generated_select_statements`, `lsp_settings`, `sql_buffer_options`,
`connections_file`, `tools_file`, and the asynchronous `setup` callback remain
available.

Result limits are now grouped under `results`:

```lua
-- Before
require("mssql").setup({
  max_rows = 100,
  max_column_width = 100,
})

-- After
require("sqlserver").setup({
  results = {
    max_rows = 100,
    max_cell_width = 100,
  },
})
```

The following options were removed:

| mssql.nvim option | sqlserver.nvim replacement |
| --- | --- |
| `max_rows` | `results.max_rows` |
| `max_column_width` | `results.max_cell_width` |
| `results_buffer_extension` | Removed; result buffers use `.sqlresult` |
| `results_buffer_filetype` | Removed; result buffers use `sqlserver-result` |

`open_results_in` still accepts `"split"`, `"vsplit"`, `"current_window"`, or
a function. For multiple result sets, the function is called once with the
first buffer so it opens one results area rather than one window per result.

SQL Server messages now default to `view_messages_in = "activity"` instead of
transient notifications. The old `"notification"`, `"buffer"`, and function
forms remain available.

The new `ui` object configures persistent presentation:

```lua
require("sqlserver").setup({
  ui = {
    presenter = "default",
    winbar = true,
    native_progress = true,
    height = 12,
  },
})
```

`ui.winbar` may be `false`, `true`, or an object with `layout` and `alignment`.
A presenter may be replaced with a function that receives structured workspace
activity events.

## Query execution changes

`ExecuteQuery` no longer means “selection or whole buffer.” Its behavior is now
scope-specific:

| Action | Command or default suffix | Behavior |
| --- | --- | --- |
| Execute query | `:SQLServer ExecuteQuery` or `x` | Execute the statement under the cursor |
| Execute selection | Visual-mode `x` | Execute the selected text |
| Execute buffer | `:SQLServer ExecuteBuffer` or `X` | Execute the entire buffer |

Current-statement detection is delegated to SQL Tools Service's T-SQL parser.
This avoids guessing statement boundaries from semicolons, comments, strings,
or `GO` batches inside Neovim.

## Results changes

`mssql.nvim` rendered a result as a Markdown table. `sqlserver.nvim` uses a
plugin-owned result model, a dedicated table renderer, and the
`sqlserver-result` filetype.

When a query returns multiple result sets:

- each result set gets its own buffer;
- all result buffers share one results window;
- the first result is displayed initially;
- `]r`, `[r`, `:SQLServer NextResult`, and `:SQLServer PreviousResult` navigate
  between them;
- each result set can be saved independently.

Cell-width truncation affects only the displayed table. Row-limit truncation is
reported in the result buffer. The underlying result model remains independent
of its rendered text.

## Status and activity changes

The `require("mssql").lualine_component` table has been removed. The built-in
UI now provides:

- workspace identity and state in Neovim's winbar;
- native progress messages for active work;
- an activity split opened with `:SQLServer Activity` or the `a` key suffix;
- structured activity subscriptions through
  `require("sqlserver").subscribe_activity(callback)`;
- `require("sqlserver").status()` for a custom statusline component.

For example:

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      function()
        return require("sqlserver").status() or ""
      end,
    },
  },
})
```

The workspace publishes state changes to replaceable subscribers instead of
calling a particular notification, winbar, or statusline integration directly.

Programmatic operations now use the documented callback-based
[`sqlserver.nvim` public API](public-api.md). Interactive Lua handlers are
available under `require("sqlserver").commands`; they are separate from the
UI-independent connection, execution, object, cancellation, and export API.

## Added commands and keymaps

The original connection, database, object finder, backup/restore, export, and
cache commands remain under the new `SQLServer` command name. The current
implementation adds:

| Default suffix | Command | Purpose |
| --- | --- | --- |
| `a` | `Activity` | Toggle workspace activity |
| `X` | `ExecuteBuffer` | Execute the complete query buffer |
| `o` | `ObjectDefinition` | Script a database object's definition |
| none | `NextResult` | Display the next result set |
| none | `PreviousResult` | Display the previous result set |

Result buffers also provide the buffer-local `]r` and `[r` mappings.

`Find` now always builds runnable SQL: `SELECT` for a table or view and `EXEC`
for a stored procedure. It no longer opens procedure definitions. Use
`ObjectDefinition` for `CREATE TABLE`, view definitions, procedure definitions,
and supported function definitions. Generated procedure calls are not executed
automatically.

## Internal architecture

Configurations that reached into undocumented `mssql.nvim` internals must be
rewritten. Connection and execution state now belong to per-buffer workspace
objects. SQL Tools Service protocol details are isolated in adapters, query
results use plugin-owned models, and presentation consumes structured activity
events. Buffer variables associate Neovim buffers with these objects but are no
longer the primary state store.

These boundaries are intentionally allowed to differ from `mssql.nvim`; only
the public `require("sqlserver")` module should be treated as the integration
surface.

## Migration checklist

1. Change the plugin repository to `NicholasMata/sqlserver.nvim`.
2. Replace `require("mssql")` with `require("sqlserver")`.
3. Replace `:MSSQL` mappings or commands with `:SQLServer`.
4. Move or explicitly configure the connections file.
5. Nest result limits under `results` and remove Markdown result options.
6. Replace `lualine_component` with `status()` if needed.
7. Decide whether to keep the default winbar and activity presenter.
8. Add an `ExecuteBuffer` mapping if the configured prefix is not used.
9. Review scripts that assumed normal-mode `ExecuteQuery` ran the whole buffer.
