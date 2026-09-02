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
changing files. Unit tests do not download SQL Tools Service or require a
database. Test configuration, data, state, and cache files are isolated under
`.tests/`.

## Integration tests

Run the complete integration suite against the disposable SQL Server 2022
Developer container:

```sh
make test-integration-local
```

This requires Docker with the Compose plugin. The target starts SQL Server,
waits for it to become healthy, recreates fixture databases, downloads SQL
Tools Service into `.tests/`, and runs the integration suite.

Stop and remove the test database and its volumes with:

```sh
make test-env-down
```

The integration target waits briefly for shutdown and fails if its headless
Neovim or SQL Tools Service process remains. Run the assertion independently
with `make assert-no-process-leaks`.

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
