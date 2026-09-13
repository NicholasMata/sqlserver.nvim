# Architecture

`sqlserver.nvim` is organized around the daily SQL Server workspace rather than
around SQL Tools Service protocol methods. Protocol details belong at the edge
of the plugin and should not define its public API or views.

## Dependency Direction

Dependencies should point inward:

```text
public API, commands, and keymaps
                |
                v
workspace services and workflows
                |
                v
backend adapter interfaces
                |
                v
SQL Tools Service and Neovim APIs
```

Renderers and views consume plugin-owned result and metadata models. They should
not need to understand raw SQL Tools Service payloads.

## Project Layout

Modules are grouped by product capability rather than collected into a generic
`core` directory or organized solely around Neovim filetypes:

```text
lua/sqlserver/
├── adapters/sql_tools_service/  protocol client, query backend, and installer
├── config/                      defaults and option normalization
├── connections/                 profiles and credential handling
├── objects/                     object intents and picker UI
├── queries/                     selection and execution summaries
├── results/                     result models, collections, sessions, and UI
├── ui/                          commands, contextual keymaps, and presentation
└── workspace/                   connection/query lifecycle and activity state
```

The configured plugin prefix remains contextual so connection and new-query
actions are available outside SQL buffers. The `sqlserver-result` filetype
belongs to this plugin; its ftplugin delegates all buffer-local behavior to
`results/ui` rather than mixing it into the global keymap module.

Feature modules can depend on their own models and on adapter interfaces. Raw
SQL Tools Service response fields must be normalized before entering a public
result, object, connection, or workspace model.

## Boundaries

### Public API

The module returned by `require("sqlserver")` is the supported entry point for
user configuration and automation. Keep it small and delegate work to services.
Public functions expose plugin-owned models and structured errors rather than
SQL Tools Service request or response shapes.

### Neovim interface

Commands, keymaps, pickers, buffers, windows, and notifications translate user
actions into service calls and render their results. This layer may use Neovim
APIs, but it should not issue backend protocol requests directly.

### Workspace services

Services own the plugin's connection, query, object, and export workflows. They
coordinate adapters and maintain plugin-owned state without depending on a
particular view.

The main service boundaries are:

- connection manager
- query executor
- metadata and object explorer
- result model, serializers, and views

Object scripting uses an explicit plugin-owned intent. Query intent produces
runnable SQL for the selected object, while definition intent produces its
schema definition. SQL Tools Service operation numbers remain an adapter detail
and must not determine user-facing behavior implicitly.

### Backend adapters

Adapters translate between plugin-owned operations and backend-specific
protocols. SQL Tools Service is currently used for language intelligence,
connections, queries, metadata, and scripting, but those concerns should remain
separable so another implementation can replace one without replacing all.

The SQL Tools Service language adapter owns LSP configuration, protocol handler
registration, response sanitization, and client attachment. Backend quirks
should be normalized here whenever possible.

## State Ownership

Connection and execution state belongs to workspace services. Buffer variables
may associate a query buffer with a service instance, but they should not be the
only source of truth for domain state. Views should read state through service
methods rather than mutating buffer state directly.

Global state should be limited to intentionally shared resources such as cached
metadata and plugin configuration. Every global cache needs an explicit key,
refresh policy, and cleanup path.

Workspaces publish structured lifecycle and server-message events through an
activity stream. Presentation modules subscribe to that stream; workspace
services do not call winbar, progress, notification, or window APIs directly.
Subscribers must be independently replaceable and a failing subscriber must
not interrupt the underlying connection or query operation.

Every asynchronous workflow uses the same operation model. An operation has a
stable identifier, kind, phase, status, source buffer, timestamps, details, and
an optional structured error. Only valid state transitions are accepted, and
terminal operations ignore late callbacks. Workspace disposal cancels every
active operation before releasing backend resources.

Interactive prompts are not operations. Waiting for a connection profile,
filename, overwrite confirmation, or object selection must not display an
elapsed timer. The operation begins when service work starts and remains active
through result presentation when presentation is part of the requested action.

## Models

Introduce plugin-owned models at backend boundaries. In particular, query
execution should normalize batches, result sets, columns, rows, messages,
errors, timings, truncation, and cancellation before passing data to renderers.

Query results currently cross three explicit boundaries: the query-result
model owns normalized data, the result renderer produces display text and
semantic decorations, and the `sqlserver-result` view owns Neovim buffers,
windows, and result-set navigation. Renderers must not fetch protocol data, and
models must not depend on a particular table format or Neovim window layout.

The result view groups result buffers into executions and keys execution
history by the originating SQL buffer. This ownership is explicit rather than
inferred from the current window, which may change before asynchronous result
collection completes. Windows remain replaceable presentation state: one
results window can display any retained execution without owning or destroying
the underlying result buffers. Source-buffer cleanup and the configured
per-source history limit bound the lifetime of those buffers.

The sticky result header is a view-only copy of the renderer-owned column
header. It uses a non-focusable window so it cannot replace the real buffer row
or intercept normal- and visual-mode commands, and it is disposed with its
parent result window.

Text file exports remain SQL Tools Service serializations. The interactive UI
loads CSV, JSON, and XML through temporary files into ordinary modified Neovim
buffers, while the public API and XLSX workflow write explicit paths. Temporary
files are an adapter constraint and do not become user-facing result state.
Export operations finish only after serialization and any requested buffer
presentation succeed. Plugin-owned temporary files are removed on success,
failure, and cancellation.

Generated query, definition, result, and text-export buffers are transactional
presentation state. They are prepared while hidden, committed to a window only
when complete, and deleted when preparation fails. This prevents asynchronous
backend timing from exposing empty or partially initialized buffers.

Rich clipboard export is a presentation concern rather than a SQL Tools Service
file export. The result layer creates semantic HTML from the complete normalized
cell model, and a platform adapter publishes the native HTML clipboard format.

The SQL Tools Service adapter translates protocol cells into plugin-owned result
cells. Models preserve display values, invariant-culture values, and database
null identity so renderers do not infer SQL semantics from formatted text.
Execution summaries likewise preserve row counts and error state independently
from how activity or result buffers present them.

Exact SQL remains the reviewable artifact. Generated or destructive SQL should
be visible to the user, and destructive execution must be explicit.

## Maintenance Rules

- Normalize backend payloads before they enter public models or views.
- Keep protocol requests inside backend adapters.
- Keep buffer, window, keymap, and clipboard behavior inside presentation
  modules.
- Give every retained buffer, query, connection, process, and temporary file an
  explicit cleanup path.
- Add focused unit tests at module boundaries and Docker integration tests for
  behavior that depends on SQL Tools Service or SQL Server.
- Prefer coherent `sqlserver.nvim` behavior over compatibility shims for the
  inherited `mssql.nvim` implementation.
