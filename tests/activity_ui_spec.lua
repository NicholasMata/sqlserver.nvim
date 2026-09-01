local activity_ui = require("sqlserver.ui.activity")
local status_ui = require("sqlserver.ui.status")
local workspace_module = require("sqlserver.core.workspace")
local activity_stream_module = require("sqlserver.core.activity_stream")

return {
  test_name = "Activity UI should expose persistent workspace state",
  run_test_async = function()
    local activity_stream = activity_stream_module.create()
    local workspace = workspace_module.create({
      bufnr = vim.api.nvim_get_current_buf(),
      backend = {
        owner_uri = "file:///activity.sql",
        client = {},
        connect_async = function()
          return { connectionSummary = { databaseName = "ApplicationDb" } }
        end,
        disconnect_async = function() end,
      },
      objects = {
        initialise_cache_async = function() end,
        is_refreshing = function()
          return false
        end,
      },
      activity_stream = activity_stream,
    })

    activity_ui.setup({ native_progress = false, height = 8 })
    assert(activity_ui.is_enabled() == false)
    activity_ui.setup({}, activity_stream)
    assert(activity_ui.is_enabled() == true)
    workspace.connect_async({
      connection = { options = { server = "localhost", database = "master" } },
    })
    workspace.record_message("Changed\ndatabase context", false)

    local status = status_ui.render(workspace)
    assert(status:find("localhost", 1, true))
    assert(status:find("ApplicationDb", 1, true))
    assert(status:find("Ready", 1, true))
    assert(not status:find("SQL  ", 1, true))
    assert(not status:find("%%#SqlServerReady#"))
    local winbar = status_ui.render_winbar(workspace)
    assert(winbar:find("Ready %#SqlServerReady#●%*", 1, true))
    assert(vim.endswith(winbar, "%#SqlServerReady#●%* "))
    assert(winbar:find("ApplicationDb%=", 1, true))
    status_ui.setup({ layout = "compact", alignment = "left" })
    assert(not vim.startswith(status_ui.render_winbar(workspace), "%="))
    status_ui.setup({ layout = "compact", alignment = "center" })
    local centered = status_ui.render_winbar(workspace)
    assert(vim.startswith(centered, "%=") and vim.endswith(centered, "%="))
    assert(vim.api.nvim_get_hl(0, { name = "SqlServerReady", link = true }).link == "DiagnosticOk")

    activity_ui.toggle(workspace)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local contents = table.concat(lines, "\n")
    assert(contents:find("SQL Server Activity", 1, true))
    assert(contents:find("Changed  database context", 1, true))
    assert(vim.api.nvim_win_get_height(0) == 8)
    activity_ui.toggle(workspace)

    local original_echo = vim.api.nvim_echo
    local progress_updates = {}
    vim.api.nvim_echo = function(chunks, _, opts)
      table.insert(progress_updates, { status = opts.status, chunks = chunks, title = opts.title })
      return opts.id or 1
    end
    activity_ui.setup({ native_progress = true })
    local progress_workspace = { bufnr = 42 }
    activity_ui.on_event(progress_workspace, {
      operation_id = 1,
      title = "SQL Server query",
      message = "Executing query",
      status = "running",
    })
    activity_ui.on_event(progress_workspace, {
      operation_id = 1,
      title = "SQL Server query",
      message = "Query failed",
      status = "error",
    })
    activity_ui.on_event(progress_workspace, {
      operation_id = 2,
      title = "SQL Server query",
      message = "Query completed with errors (1 rows)",
      status = "warning",
    })
    vim.api.nvim_echo = original_echo
    assert(progress_updates[1].status == "running")
    assert(progress_updates[2].status == "failed", "Activity errors must use Neovim's failed progress status")
    assert(progress_updates[3].status == "failed", "Mixed outcomes must terminate Neovim progress")
    assert(progress_updates[3].title == nil, "Warning progress must render its own highlighted title")
    assert(progress_updates[3].chunks[1][1] == "SQL Server query:")
    assert(progress_updates[3].chunks[1][2] == "WarningMsg", "Mixed outcomes must highlight the title")
    assert(progress_updates[3].chunks[2][2] == nil, "Mixed-outcome details must use normal highlighting")
  end,
}
