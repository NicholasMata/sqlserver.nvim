# SQL Agent protocol observations

These observations come from the pinned SQL Tools Service `6.0.20260902.1`
against the isolated SQL Server 2022 integration fixtures. The tests in
`tests/integration/specs/agent_fixture_protocol_spec.lua` and
`tests/agent_unavailable/test_agent_unavailable.lua` keep the behavior
reproducible. They establish response classifications for the SQL Agent
adapter; they do not define public API models.

| Scenario | Observed response |
| --- | --- |
| Agent enabled, seeded jobs | `agent/jobs` returns `success = true` and a populated `jobs` list. |
| Agent enabled, no visible jobs | A login in `SQLAgentUserRole` with no owned jobs receives `success = true` and `jobs = []`. |
| Job with history | `agent/jobhistory` returns `success = true` with history, steps, schedules, and job-linked alerts. |
| Never-run job | `agent/jobhistory` returns `success = false` with no error message or history, but retains steps and schedules. This is an empty-history state, not a failed details load. |
| Agent enabled, alerts | `agent/alerts` returns `success = true` and includes both job-linked and independent alerts. |
| Login without Agent permissions | Jobs, history, and alerts return `success = false` with permission evidence in `errorMessage`. The alerts error includes a server stack trace and must not be shown verbatim to users. |
| SQL Server Express | Jobs and alerts return `success = false` with an unsupported-edition message. An empty list alone does not establish that Agent is unavailable. |

The Developer fixture enables Agent and recreates its named jobs, schedules,
alerts, and logins on every seed. The opt-in Express fixture has no Agent and
uses a separate port. Run `make test-integration-local` for the enabled
fixture and `make test-agent-unavailable-local` for Express. `make
test-env-down` removes both containers and their volumes.

A stopped Agent on an otherwise supported SQL Server edition is not covered
by these Linux fixtures. The adapter must classify that state only when a
future observed service response provides enough evidence.

## Read-only adapter model

The adapter in `lua/sqlserver/adapters/sql_tools_service/agent.lua` sends the
three read-only requests with the connected workspace's owner URI. It returns
plugin-owned fields with `snake_case` names and named enum values. Jobs retain
their GUID as `id`, execution status, last run outcome and time, and next run
time when available. Selected job details have separate `histories`, `steps`,
`schedules`, and `linked_alerts` lists. The server-wide alert operation returns
all visible alerts, including alerts with no associated job.

Service nulls, empty optional strings, and SQL Server's year-one date sentinel
become absent fields. Unknown enum values are omitted rather than exposed as
protocol numbers. The proven never-run response has
`history_state = "empty"` with its steps and schedules intact. Permission and
unsupported-edition failures receive stable error codes and safe messages.
Raw service errors and stack traces never enter the model. Request
cancellation, timeout, refresh, and disconnect ownership belong to the
workspace work in #26.
