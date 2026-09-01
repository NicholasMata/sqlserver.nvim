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

## Boundaries

### Public API

The module returned by `require("sqlserver")` will become the supported entry
point for user configuration and automation. Until the public API milestone,
its shape may change as the architecture is established. Keep it small and
delegate work to services. Public functions must not expose SQL Tools Service
request or response shapes.

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
- result model and exporters

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

## Models

Introduce plugin-owned models at backend boundaries. In particular, query
execution should normalize batches, result sets, columns, rows, messages,
errors, timings, truncation, and cancellation before passing data to renderers.

Exact SQL remains the reviewable artifact. Generated or destructive SQL should
be visible to the user, and destructive execution must be explicit.

## Migration Strategy

The inherited implementation works and should be replaced incrementally:

1. Extract backend protocol and Neovim UI responsibilities from `init.lua`.
2. Put connection and query-buffer state behind a connection manager.
3. Normalize query responses into a result model before rendering them.
4. Move object discovery and scripting behind a metadata service.
5. Reduce `init.lua` to setup and public API composition.

Each step should preserve intentional capabilities and retain necessary
protocol workarounds, but it does not need to preserve `mssql.nvim` APIs,
commands, configuration shapes, module names, or internal state. Prefer direct
replacement over compatibility shims. Add focused tests around every boundary
being introduced.
