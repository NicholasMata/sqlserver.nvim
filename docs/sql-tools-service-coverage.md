# SQL Tools Service coverage

The [README coverage chart](../README.md#sql-tools-service-coverage) summarizes
`sqlserver.nvim` workflows. It is not an inventory of every SQL Tools Service
endpoint. The categories group related user tasks; the definitions below set
the scope of each chart entry for this plugin.

The repository's `area:` labels use these same workflow names and scopes. An
area label identifies the subject of an issue, not a commitment to implement
it; the status below and any milestone describe the current plan.

## Status meanings

| Status | Meaning |
| --- | --- |
| ✅ Complete | The plugin implements its documented scope for this workflow. It does not claim every related SQL Tools Service capability. |
| 🟡 Partial | Some of the documented workflow is usable, but important parts remain unfinished. |
| 🔵 Planned | A future workflow that is not yet shipped. [Release milestones](https://github.com/NicholasMata/sqlserver.nvim/milestones) and their issues define scope once scheduled. |
| ⚪ Not currently on the roadmap | The plugin does not plan a dedicated workflow for this item. This does not imply that SQL Tools Service lacks the capability. |

## Development

Tools for connecting to a database and writing, understanding, executing, and
scripting SQL and database objects. This section covers the daily
query-authoring workflow, not changes to stored table data.

| Item | Scope in `sqlserver.nvim` |
| --- | --- |
| ✅ Connections | Create and edit connection profiles, authenticate to SQL Server or Azure SQL, and manage the connection lifecycle for query buffers. See [Connection profiles](connections-json.md) and [SQL buffer workflow](usage.md#sql-buffer-workflow). |
| ✅ IntelliSense | SQL-aware completion, diagnostics, hover, signature help, definitions, and formatting through Neovim's LSP interface. See [Language features](usage.md#language-features). This does not include every SQL Tools Service editor feature. |
| ✅ Query | Execute the statement under the cursor, a visual selection, or the entire SQL buffer; inspect messages and multiple result sets; cancel execution; and export results. See [Query workflow](usage.md#sql-buffer-workflow) and [Result view workflow](usage.md#result-view-workflow). Execution-plan presentation is tracked separately below. |
| ✅ Objects | Find database objects, generate runnable queries and editable definitions, and browse the SQL Tools Service hierarchy with optional Snacks. The supported actions and object types are defined in [Object Explorer](object-explorer.md#supported-scope). This is not a general server-administration explorer. |
| ⚪ Schema Compare | Compare schemas and produce reviewable differences or migration work. No dedicated workflow is currently planned. |
| ⚪ Table Design | A dedicated interface for changing table structure. Object definitions can be scripted as SQL, but there is no table designer. |

## Administration

Workflows that inspect or change stored data and operational resources such as
jobs, backups, and permissions. An item can appear here even when the plugin
plans only read-only access to it.

| Item | Scope in `sqlserver.nvim` |
| --- | --- |
| 🟡 SQL Agent | Browse instance-level Jobs through Object Explorer, with read-only properties, searchable history, and contextual actions. The Alerts branch remains planned under [Jobs and Alerts](https://github.com/NicholasMata/sqlserver.nvim/issues/21). Operators, Proxies, and standalone Schedules are tracked separately in [their feature issue](https://github.com/NicholasMata/sqlserver.nvim/issues/23). See [SQL Agent Jobs](usage.md#sql-agent-jobs) for the implemented workflow. |
| ⚪ Backup | A dedicated backup workflow with configuration and status tracking is not planned. `BackupDatabase` currently inserts a SQL command into a query buffer; it is not a backup-management UI. |
| ⚪ Restore | A dedicated restore workflow with configuration and status tracking is not planned. `RestoreDatabase` currently inserts a SQL command into a query buffer; it is not a restore-management UI. |
| 🔵 Edit Data | Update eligible cells, add and delete rows, and use SQL Tools Service to generate an unsaved SQL buffer for review and manual execution. The feature does not apply changes automatically. Arbitrary query results are not assumed writable. See the [feature issue](https://github.com/NicholasMata/sqlserver.nvim/issues/22) for release scope. |
| ⚪ Security | Administration of logins, users, roles, and permissions. Connecting with a configured identity is supported, but a security-management UI is not planned. |

## Diagnostics

Tools for investigating server behavior and query performance beyond the
messages, errors, and timings shown during ordinary query execution.

| Item | Scope in `sqlserver.nvim` |
| --- | --- |
| ⚪ Profiler | Capturing and inspecting server event traces. No dedicated workflow is currently planned. |
| ⚪ Query Store | Browsing Query Store performance history and reports. This is distinct from the plugin's query execution and result history; no dedicated workflow is currently planned. |
| 🟡 Query Plans | For `1.1.0`, capture estimated/actual plans, inspect retained XML, and save original `.sqlplan` files. See [capture/export #39](https://github.com/NicholasMata/sqlserver.nvim/issues/39) and [Usage](usage.md#execution-plans). Native operator exploration and graphical viewing/comparison are tracked for `1.2.0` in [#40](https://github.com/NicholasMata/sqlserver.nvim/issues/40). |
| ⚪ Assessment | Running database or server assessment checks and reviewing recommendations. No dedicated workflow is currently planned. |
