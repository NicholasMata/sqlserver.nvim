# Contributing

Read [the vision](docs/vision.md), [the roadmap](docs/roadmap.md), and
[the architecture](docs/architecture.md) before making broad changes. The
project prioritizes a reliable query and object workflow over broad SSMS-style
administration features.

## Local setup

Load the plugin from a checkout while developing:

```lua
vim.opt.rtp:prepend("/path/to/sqlserver.nvim")
require("sqlserver").setup({
  keymap_prefix = "<leader>s",
})
```

## Formatting and unit tests

Lua uses two-space indentation enforced by StyLua 2.5.2:

```sh
make format
make lint
make test
```

`make format` rewrites all Lua sources. `make lint` verifies formatting without
changing files. Tests use `mini.test`, pinned to an exact `mini.nvim` commit and
downloaded into `.tests/deps/` by the Makefile. Unit tests do not download SQL
Tools Service or require a database. Test configuration, data, state, cache,
and dependencies are isolated under `.tests/`.

Run the native SQL Tools Service installation and lifecycle suite:

```sh
make test-platform
```

Platform integration downloads the pinned SQL Tools Service release, installs
it through the plugin, attaches it to a SQL buffer, and shuts it down. CI runs
this suite natively on Linux, macOS, and Windows. SQL Server-backed integration
tests remain on Linux because their database is provided by a Linux container.

Run a focused case by matching any part of its `mini.test` description:

```sh
SQLSERVER_TEST_FILTER=query_selection make test-unit
SQLSERVER_TEST_FILTER=cancel_query make test-integration-local
```

Generate line-coverage reports with LuaCov:

```sh
make coverage-unit        # unit tests only
make coverage-platform    # native SQL Tools Service lifecycle only
make coverage-integration # Docker integration tests only
make coverage             # combined unit, platform, and database coverage
```

The commands write an annotated report to `coverage/luacov.report.out` and a
per-file and overall summary to `coverage/summary.txt`. Coverage runs disable
LuaJIT so LuaCov can observe executed lines reliably. Coverage is diagnostic;
the project does not currently enforce a minimum percentage. CI merges raw
coverage statistics from Linux, macOS, Windows, and the Docker integration
suite so platform-specific branches are represented in one report. The Docker
suite runs as isolated `core` and `objects` jobs in CI; each job starts and
seeds its own SQL Server container and uploads a uniquely named coverage shard.

## Integration tests

Run the complete integration suite against the disposable SQL Server 2022
Developer container:

```sh
make test-integration-local
```

This requires Docker with the Compose plugin. The target starts SQL Server,
waits for it to become healthy, recreates fixture databases, downloads SQL
Tools Service into `.tests/`, and runs the integration suite.

The local commands remain unsharded. To reproduce one CI shard against an
already seeded test environment, run either:

```sh
make test-integration-shard SHARD=core
make test-integration-shard SHARD=objects
```

Every integration spec is assigned to exactly one shard. A unit test fails when
a spec is unassigned, assigned more than once, or no longer exists.

Stop and remove the test database and its volumes with:

```sh
make test-env-down
```

The integration target waits briefly for shutdown and fails if its headless
Neovim or SQL Tools Service process remains. Run the assertion independently
with `make assert-no-process-leaks`.

Connected integration cases receive a fresh SQL buffer and SQL Login
connection from shared fixtures. Each case explicitly disconnects and removes
its buffers afterward. Tests that require a particular database must select it
themselves and must not depend on execution order.

Microsoft supports its SQL Server Linux container images only on x86-64 Linux
hosts. The Compose configuration requests `linux/amd64`, but emulation on ARM
is not officially supported. Use a reachable SQL Server instance if the
container is unreliable on an ARM host.

To use an existing server:

```sh
DbServer=localhost \
DbDatabase=master \
DbUser=sa \
DbPassword='your-password' \
make test-integration
```

Set `SQLSERVER_PORT` for a non-default local container port. Also set
`DbServer` to the server value expected by SQL Server clients, such as
`localhost,14330`.

## Architecture and tests

Keep dependencies directed from public commands and views toward workspace
services, plugin-owned models, and backend adapters. Neovim UI code should not
issue SQL Tools Service requests directly. Add focused unit tests for new
boundaries and integration tests for behavior that depends on SQL Tools
Service or SQL Server.

Documentation filenames under `docs/` use lowercase kebab-case, such as
`public-api.md`. Keep media in `docs/assets/` and follow the same convention.

## Pull requests

Keep pull requests focused on one coherent change. Split unrelated behavior,
refactoring, and documentation work when they can be reviewed and merged
independently. Use a draft pull request while the design or implementation is
still changing substantially.

Write an imperative, capitalized title that describes the outcome, without a
trailing period. The description must explain the change in its own words; a
commit range or generated list of commit subjects is not a substitute. Describe
what changed, why it is needed, and link any resolved issue with a GitHub
keyword such as `Fixes #123`.

Every pull request, whether authored by a human or an agent, must use and
adhere to the [pull request template](.github/PULL_REQUEST_TEMPLATE.md). Check
every applicable type and every item under **Checklist** before requesting
review. A pull request with an unchecked checklist item is not ready for
review; resolve the requirement or explain the permitted alternative in the
pull request description before checking it. GitHub Checks is the source of
truth for automated test results; do not copy CI status or test counts into the
description. For a visible Neovim change, include a screenshot or recording.
Explain compatibility concerns, known limitations, important design choices,
and alternatives when they apply.

Before requesting review, make sure the branch is based on the current target
branch, relevant local checks pass, required GitHub checks complete,
documentation matches the implementation, and user-visible changes appear
under `Unreleased` in [CHANGELOG.md](CHANGELOG.md). Do not include credentials,
connection strings, access tokens, or private database contents in
descriptions, logs, screenshots, or fixtures.

## Commit messages

Follow [Tim Pope's commit message guidance](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html):

- use an imperative, capitalized subject;
- keep the subject around 50 characters;
- do not end the subject with a period;
- separate the body with a blank line;
- wrap body text at approximately 72 characters;
- explain what changed and why.

Agents and AI coding tools must also follow [AGENTS.md](AGENTS.md).

## Releases

User-visible changes belong under `Unreleased` in [CHANGELOG.md](CHANGELOG.md).
Maintainers must complete [the release checklist](docs/releasing.md), including
the documented manual core-loop pass, before tagging a stable release.
