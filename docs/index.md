# Documentation

Use this page to find the guide for what you are trying to do. The README keeps
the essential setup and defaults close at hand; these guides contain the full
details.

| Goal | Guide |
| --- | --- |
| Install and configure the plugin | [Configuration](configuration.md) |
| Create secure connection profiles | [Connection profiles](connections-json.md) |
| Execute queries and work with results | [Usage](usage.md) |
| Configure SQL formatting and IntelliSense | [SQL Tools Service settings](lsp-settings.md) |
| Automate the plugin from Lua | [Public Lua API](public-api.md) |
| Move from `mssql.nvim` | [Migrating from mssql.nvim](migrating-from-mssql.md) |
| Understand the project direction | [Vision](vision.md) and [roadmap](roadmap.md) |
| Understand module ownership | [Architecture](architecture.md) |
| Develop and test locally | [Contributing](../CONTRIBUTING.md) |
| Prepare a release | [Release checklist](releasing.md) |
| Review user-visible changes | [Changelog](../CHANGELOG.md) |

Configuration fields live in [Configuration](configuration.md), while commands,
keymaps, result navigation, exports, and object workflows live in
[Usage](usage.md). Keeping those concerns separate avoids maintaining the same
reference material in several places.
