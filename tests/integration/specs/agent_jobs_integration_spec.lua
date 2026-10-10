local sqlserver = require("sqlserver")
local integration = require("tests.helpers.integration")

local T = MiniTest.new_set()

local function find_named(items, name)
  return vim.iter(items):find(function(item)
    return item.name == name
  end)
end

T["Jobs command and public API inspect seeded jobs"] = require("tests.helpers").async(function()
  local source = vim.api.nvim_get_current_buf()
  integration.await(function(callback)
    sqlserver.disconnect(source, callback)
  end)
  integration.connect(source, "TestDbB")
  local jobs = integration.await(function(callback)
    sqlserver.list_jobs({ bufnr = source }, callback)
  end)
  local history_job = assert(find_named(jobs, "sqlserver.nvim fixture history"))
  local empty_job = assert(find_named(jobs, "sqlserver.nvim fixture no history"))
  assert(history_job.enabled == true and empty_job.enabled == false)
  assert(history_job.last_run_outcome == "succeeded")

  local history = integration.await(function(callback)
    sqlserver.job_details({ bufnr = source, job = history_job }, callback)
  end)
  assert(history.history_state == "available" and #history.histories > 0)
  assert(#history.linked_alerts > 0)
  local empty = integration.await(function(callback)
    sqlserver.job_details({ bufnr = source, job = empty_job }, callback)
  end)
  assert(empty.history_state == "empty" and #empty.steps > 0 and #empty.schedules > 0)

  assert(vim.list_contains(vim.fn.getcompletion("SQLServer J", "cmdline"), "Jobs"))
  vim.opt.runtimepath:prepend(vim.fs.joinpath(vim.fn.getcwd(), ".tests", "deps", "snacks.nvim"))
  local snacks = require("snacks")
  snacks.setup({ picker = { enabled = true } })
  local original_notify = vim.notify
  local empty_notice
  local picker
  local function find_item(label)
    if not picker then
      return nil
    end
    for _, item in ipairs(picker.opts.finder()) do
      if item.label == label then
        return item
      end
    end
  end
  local ok, failure = pcall(function()
    vim.cmd("SQLServer Jobs")
    assert(
      vim.wait(10000, function()
        picker = snacks.picker.get({ tab = false })[1]
        return picker and picker.shown and find_item("Jobs") ~= nil
      end, 20),
      "Jobs did not focus Object Explorer"
    )
    assert(find_item("SQL Server Agent"))
    assert(sqlserver.current_connection(source).database == "TestDbB")
    local jobs_node = find_item("Jobs")
    picker.opts.actions.object_toggle(picker, jobs_node)
    assert(
      vim.wait(10000, function()
        return find_item("sqlserver.nvim fixture no history") ~= nil
      end, 20),
      "Agent jobs did not load in Object Explorer"
    )
    local job_node = find_item("sqlserver.nvim fixture no history")
    assert(job_node.node.isLeaf and job_node.node.children == nil)
    assert(vim.iter(picker.opts.format(job_node, picker)):any(function(chunk)
      return chunk[2] == "SqlServerJobIdle"
    end))
    picker.opts.confirm(picker, job_node)
    assert(
      vim.wait(10000, function()
        return vim.bo[vim.api.nvim_get_current_buf()].filetype == "sqlserver-job-properties"
      end, 20),
      "Job properties did not open"
    )
    local properties_win = vim.api.nvim_get_current_win()
    local function properties_text()
      return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(properties_win), 0, -1, false), "\n")
    end
    assert(properties_text():find("Job: sqlserver.nvim fixture no history", 1, true))
    local marks = vim.api.nvim_buf_get_extmarks(
      vim.api.nvim_win_get_buf(properties_win),
      vim.api.nvim_get_namespaces()["sqlserver-agent-properties"],
      0,
      -1,
      { details = true }
    )
    assert(vim.iter(marks):any(function(mark)
      return mark[4].hl_group == "SqlServerJobPropertyLabel"
    end))
    assert(vim.iter(marks):any(function(mark)
      return mark[4].hl_group == "SqlServerJobDisabled"
    end))
    vim.api.nvim_feedkeys("2", "xt", false)
    assert(properties_text():find("Step 1 · Never run", 1, true))
    marks = vim.api.nvim_buf_get_extmarks(
      vim.api.nvim_win_get_buf(properties_win),
      vim.api.nvim_get_namespaces()["sqlserver-agent-properties"],
      0,
      -1,
      { details = true }
    )
    assert(vim.iter(marks):any(function(mark)
      return mark[4].hl_group == "SqlServerJobPropertyHeading"
    end))
    vim.api.nvim_feedkeys("3", "xt", false)
    assert(properties_text():find("sqlserver.nvim fixture no-history schedule", 1, true))
    vim.api.nvim_feedkeys("4", "xt", false)
    assert(properties_text():find("No linked alerts", 1, true))
    vim.api.nvim_feedkeys("q", "xt", false)
    assert(
      vim.wait(1000, function()
        return not vim.api.nvim_win_is_valid(properties_win)
      end),
      "Job properties did not close"
    )
    picker.opts.actions.object_actions(picker, job_node)
    local menu = vim.iter(snacks.picker.get({ tab = false })):find(function(open)
      return open.opts.title == "Actions"
    end)
    assert(menu, "Job action menu did not open")
    local view_history = vim.iter(menu.opts.finder()):find(function(item)
      return item.item.id == "job_history"
    end)
    vim.notify = function(message, ...)
      if message == "No history for sqlserver.nvim fixture no history" then
        empty_notice = message
      else
        original_notify(message, ...)
      end
    end
    menu.opts.actions.confirm(menu, view_history)
    assert(
      vim.wait(10000, function()
        return empty_notice ~= nil
      end, 20),
      "Empty history was not reported"
    )
    assert(not vim.iter(snacks.picker.get({ tab = false })):any(function(open)
      return open.opts.title == "Job History · sqlserver.nvim fixture no history"
    end))
    vim.notify = original_notify

    picker.opts.actions.object_actions(picker, find_item("sqlserver.nvim fixture history"))
    menu = vim.iter(snacks.picker.get({ tab = false })):find(function(open)
      return open.opts.title == "Actions"
    end)
    assert(menu, "Populated job action menu did not open")
    view_history = vim.iter(menu.opts.finder()):find(function(item)
      return item.item.id == "job_history"
    end)
    menu.opts.actions.confirm(menu, view_history)
    assert(
      vim.wait(10000, function()
        return vim.iter(snacks.picker.get({ tab = false })):any(function(open)
          return open.opts.title == "Job History · sqlserver.nvim fixture history"
        end)
      end, 20),
      "Populated history picker did not open"
    )
    local history_picker = vim.iter(snacks.picker.get({ tab = false })):find(function(open)
      return open.opts.title == "Job History · sqlserver.nvim fixture history"
    end)
    local run = history_picker.opts.items[1]
    assert(run.detail and run.run_at)
    history_picker.input:set("sqlserver-no-such-history-run-27")
    history_picker:find()
    assert(
      vim.wait(1000, function()
        return history_picker.list:count() == 0
      end),
      "History filtering kept unmatched runs"
    )
    history_picker.input:set("succeeded")
    history_picker:find()
    assert(
      vim.wait(1000, function()
        return history_picker.list:count() > 0
      end),
      "History filtering lost matching runs"
    )
    history_picker.opts.confirm(history_picker, run)
    assert(history_picker.closed)
    local float_win = vim.api.nvim_get_current_win()
    local float_buf = vim.api.nvim_win_get_buf(float_win)
    assert(vim.bo[float_buf].filetype == "sqlserver-job-history")
    assert(table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), "\n"):find("Outcome:", 1, true))
    local history_marks = vim.api.nvim_buf_get_extmarks(
      float_buf,
      vim.api.nvim_get_namespaces()["sqlserver-agent-history"],
      0,
      -1,
      { details = true }
    )
    assert(vim.iter(history_marks):any(function(mark)
      return mark[4].hl_group == "SqlServerJobHistoryLabel"
    end))
    assert(vim.iter(history_marks):any(function(mark)
      return mark[4].hl_group == "SqlServerJobHistoryHeading"
    end))
    assert(vim.iter(history_marks):any(function(mark)
      return mark[4].hl_group == "DiagnosticOk"
    end))
    assert(vim.fn.mode():find("^n") and vim.fn.maparg("q", "n") ~= "")
    vim.api.nvim_feedkeys("q", "xt", false)
    assert(
      vim.wait(1000, function()
        return not vim.api.nvim_win_is_valid(float_win)
      end),
      "Closing the run window did not return to Object Explorer"
    )
    assert(
      vim.wait(1000, function()
        return not picker.closed
          and vim.api.nvim_get_current_win() == picker.input.win.win
          and vim.fn.mode():find("^n") ~= nil
      end),
      "Object Explorer did not regain focus"
    )
    picker.opts.confirm(picker, find_item("sqlserver.nvim fixture no history"))
    local disconnect_win = vim.api.nvim_get_current_win()
    assert(vim.bo[vim.api.nvim_win_get_buf(disconnect_win)].filetype == "sqlserver-job-properties")
    integration.await(function(callback)
      sqlserver.disconnect(source, callback)
    end)
    assert(picker.closed and not vim.api.nvim_win_is_valid(disconnect_win), "Disconnect left an Agent view open")
  end)
  vim.notify = original_notify
  if picker and not picker.closed then
    picker:close()
  end
  assert(ok, failure)
end)

T["Explorer accepts job replies during query execution and cancellation"] = function()
  local workspace_module = require("sqlserver.workspace")
  local registry = require("sqlserver.workspace.registry")
  local explorer = require("sqlserver.objects.ui.explorer")
  local original_snacks = package.loaded.snacks
  local source = vim.api.nvim_create_buf(true, false)
  local source_win = vim.api.nvim_get_current_win()
  local original_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(source)
  local state = workspace_module.states.connected
  local requests, options, picker = {}, nil, nil
  local workspace = {
    bufnr = source,
    get_state = function()
      return state
    end,
    get_connection = function()
      return { server = "localhost" }
    end,
    open_object_explorer_async = function()
      return {},
        require("sqlserver.objects.explorer").from_service({
          nodePath = "database",
          label = "TestDbB",
          objectType = "Database",
          isLeaf = false,
        })
    end,
    close_object_explorer_session = function() end,
    close_agent_view = function() end,
    cancel_agent_request = function() end,
    list_agent_jobs_async = function()
      return { { id = "a", name = "Backup" } }
    end,
    get_agent_job_details_async = function()
      requests[#requests + 1] = coroutine.running()
      return coroutine.yield()
    end,
  }
  registry.attach(source, workspace)
  package.loaded.snacks = {
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      pick = function(opts)
        options = opts
        picker = {
          closed = false,
          refresh = function() end,
          focus = function() end,
          close = function(self)
            self.closed = true
            opts.on_close(self)
          end,
        }
        return picker
      end,
    },
  }
  local ok, err = pcall(function()
    require("sqlserver").object_explorer({ focus_target = "jobs" })
    assert(options, "Public explorer entry point did not open")
    local jobs = vim.iter(options.finder()):find(function(item)
      return item.node.agent_kind == "jobs"
    end)
    options.actions.object_toggle(picker, jobs)
    local job = vim.iter(options.finder()):find(function(item)
      return item.node.agent_kind == "job"
    end)
    for _, query_state in ipairs({ workspace_module.states.executing, workspace_module.states.cancelling }) do
      state = workspace_module.states.connected
      options.actions.object_refresh(picker, job)
      assert(job.node.loading)
      state = query_state
      assert(coroutine.resume(requests[#requests], { steps = { { id = 3, name = "Third" } } }))
      assert(not job.node.loading and job.node.details, "Query state stranded the details reply")
      state = workspace_module.states.connected
      local count = #requests
      options.confirm(picker, job)
      assert(#requests == count, "Inspecting cached details issued another request")
      local win = vim.api.nvim_get_current_win()
      assert(vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "sqlserver-job-properties")
      vim.api.nvim_win_close(win, true)
    end
  end)
  explorer.close(source)
  registry.detach(source)
  package.loaded.snacks = original_snacks
  vim.api.nvim_set_current_win(source_win)
  vim.api.nvim_set_current_buf(original_buf)
  vim.api.nvim_buf_delete(source, { force = true })
  assert(ok, err)
end

return T
