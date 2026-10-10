local api = require("sqlserver.api")
local agent_tree = require("sqlserver.agent.explorer")
local agent_inspector = require("sqlserver.agent.inspector")
local explorer = require("sqlserver.objects.ui.explorer")
local object_tree = require("sqlserver.objects.explorer")
local registry = require("sqlserver.workspace.registry")
local workspace_module = require("sqlserver.workspace")

local T = MiniTest.new_set()

T["Jobs API returns normalized workspace data and safe failures"] = function()
  local backend = {
    owner_uri = "file:///agent-api.sql",
    connect_async = function()
      return {}
    end,
    disconnect_async = function() end,
  }
  local workspace = workspace_module.create({ bufnr = 712, backend = backend, objects = {} })
  registry.attach(712, workspace)
  workspace.connect_async({ connection = { options = { server = "localhost" } } })
  workspace.set_agent_backend({
    list_jobs_async = function()
      return { { id = "job-1", name = "First", enabled = false } }
    end,
    get_job_details_async = function(job)
      return { job_id = job.id, job_name = job.name, steps = {}, schedules = {}, histories = {}, linked_alerts = {} }
    end,
  })
  local jobs, err
  api.list_jobs({ bufnr = 712 }, function(value, failure)
    jobs, err = value, failure
  end)
  assert(not err and #jobs == 1 and jobs[1].enabled == false)
  local details
  api.job_details({ bufnr = 712, job = jobs[1] }, function(value, failure)
    assert(not failure)
    details = value
  end)
  assert(details.job_id == "job-1")

  workspace.set_agent_backend({
    list_jobs_async = function()
      error({ code = "agent_permission_denied", message = "Insufficient permissions to inspect SQL Agent" }, 0)
    end,
  })
  api.list_jobs({ bufnr = 712 }, function(value, failure)
    jobs, err = value, failure
  end)
  assert(jobs == nil and err.code == "agent_permission_denied")
  assert(workspace.get_agent_state("jobs").data[1].name == "First")
  workspace.dispose_async()
  registry.detach(712)
end

local function service_root(kind)
  return object_tree.from_service({
    nodePath = kind == "Server" and "server" or "database",
    label = kind == "Server" and "localhost" or "ApplicationDb",
    objectType = kind,
    isLeaf = false,
  })
end

T["Agent tree is instance-level and preserves service nodes"] = function()
  local database = service_root("Database")
  local root = agent_tree.attach(database, "localhost")
  assert(root.agent_kind == "server" and root.label == "localhost")
  assert(root.children[1].label == "Databases" and root.children[1].children[1] == database)
  assert(root.children[2].label == "SQL Server Agent")
  assert(root.children[2].children[1].label == "Jobs")

  local server = service_root("Server")
  local same_root = agent_tree.attach(server, "ignored")
  assert(same_root == server and server.children[1].agent_kind == "service")
  object_tree.set_service_children(server, {
    { nodePath = "server/Databases", label = "Databases", objectType = "Folder", isLeaf = false },
  })
  assert(server.children[1].nodePath == "server/Databases")
  assert(server.children[2].agent_kind == "service")
end

T["Agent jobs show status icons without repeating text"] = function()
  local root = agent_tree.attach(service_root("Database"), "localhost")
  local jobs_node = root.children[2].children[1]
  local job = { id = "job-1", name = "Backup", enabled = true, execution_status = "idle" }
  agent_tree.set_jobs(jobs_node, { job })
  local job_node = jobs_node.children[1]
  assert(job_node.id == "sqlserver-agent://jobs/job-1")
  assert(job_node.icon == "󰄬" and #object_tree.details(job_node) == 0)
  assert(job_node.status_icon == "󰅐" and job_node.status_highlight == "SqlServerJobIdle")
  assert(job_node.isLeaf and job_node.children == nil)
  job_node.details = { steps = {} }
  agent_tree.set_jobs(jobs_node, { vim.tbl_extend("force", job, { enabled = false, execution_status = "executing" }) })
  assert(jobs_node.children[1] == job_node and job_node.details)
  assert(job_node.icon == "󰅙")
  assert(job_node.status_icon == "󰐊" and job_node.status_highlight == "SqlServerJobRunning")
  assert(#object_tree.details(job_node) == 0)
  agent_tree.set_jobs(jobs_node, { vim.tbl_extend("force", job, { execution_status = "queued" }) })
  assert(job_node.status_icon == "󰔟" and job_node.status_highlight == "SqlServerJobWaiting")
  agent_tree.set_jobs(jobs_node, { vim.tbl_extend("force", job, { execution_status = "suspended" }) })
  assert(job_node.status_icon == "󰏤" and job_node.status_highlight == "SqlServerJobSuspended")
  agent_tree.set_jobs(jobs_node, {})
  assert(#jobs_node.children == 0 and object_tree.details(jobs_node)[1] == "No jobs")
end

T["Job inspector separates properties from filterable history"] = function()
  local job = { name = "Backup", enabled = true, execution_status = "idle", last_run_outcome = "succeeded" }
  local data = {
    steps = { { name = "Query", command = "SELECT 1\nSELECT 2" } },
    schedules = { { name = "Daily", enabled = false } },
    linked_alerts = { { name = "Failure", type = "sql_server_event" } },
    histories = {
      {
        run_at = "2026-10-01",
        outcome = "succeeded",
        duration = "1s",
        steps = { { name = "Query", outcome = "succeeded", message = "Done" } },
      },
    },
  }
  local pages = agent_inspector.properties(job, data)
  assert(#pages == 4 and pages[1].label == "Overview")
  assert(pages[2].entries[1].label == "Step 1 · Query")
  assert(table.concat(pages[2].entries[1].lines, "\n"):find("SELECT 1\nSELECT 2", 1, true))
  assert(pages[3].entries[1].label == "Schedule · Daily")
  assert(pages[4].entries[1].label == "Linked alert · Failure")
  local history = agent_inspector.history(data)
  assert(#history == 1 and history[1].text:find("succeeded", 1, true))
  assert(history[1].detail:find("Done", 1, true))
  assert(history[1].marks[2].outcome == "succeeded")
  assert(history[1].marks[5].heading and history[1].marks[5].outcome == "succeeded")
  assert(#agent_inspector.history({ histories = {} }) == 0)
end

T["Job inspector preserves nonsequential step IDs"] = function()
  local steps = {
    { id = 3, name = "Third", outcome = "failed", message = "Third failed" },
    { id = 1, name = "First", outcome = "succeeded", message = "First finished" },
    { name = "Missing ID", outcome = "succeeded", message = "Fallback" },
  }
  local pages = agent_inspector.properties({}, { steps = steps })
  assert(pages[2].entries[1].label == "Step 3 · Third")
  assert(pages[2].entries[2].label == "Step 1 · First")
  assert(pages[2].entries[3].label == "Step 3 · Missing ID")
  local detail = agent_inspector.history({ histories = { { steps = steps } } })[1].detail
  assert(detail:find("Step 3: Third · failed", 1, true))
  assert(detail:find("Step 3 message: Third failed", 1, true))
  assert(detail:find("Step 1: First · succeeded", 1, true))
  assert(detail:find("Step 1 message: First finished", 1, true))
  assert(detail:find("Step 3 message: Fallback", 1, true))
end

T["Object Explorer loads Agent jobs without a service node path"] = function()
  local original = package.loaded.snacks
  local original_notify = vim.notify
  local notifications = {}
  vim.notify = function(message)
    notifications[#notifications + 1] = message
  end
  local options, detail_options, selected_actions, selected_callback
  local viewed
  local picker = {
    closed = false,
    input = { set = function() end },
    list = {
      view = function(_, index)
        viewed = index
      end,
    },
    focus = function() end,
    find = function() end,
    refresh = function() end,
    close = function(self)
      self.closed = true
      options.on_close(self)
    end,
  }
  package.loaded.snacks = {
    picker = {
      pick = function(opts)
        if opts.title == "SQL Server Object Explorer" then
          options = opts
        else
          detail_options = opts
        end
        return picker
      end,
      format = {
        tree = function()
          return {}
        end,
      },
      select = function(actions, _, callback)
        selected_actions, selected_callback = actions, callback
      end,
    },
  }
  local root = agent_tree.attach(service_root("Database"), "localhost")
  local requests, errors, copied, closed = {}, {}, nil, false
  local fail_jobs, deferred_details
  local ok, failure = pcall(function()
    explorer.open({
      bufnr = 7123,
      root = root,
      focus_target = "jobs",
      on_copy = function(value)
        copied = value
      end,
      on_close = function()
        closed = true
      end,
      on_error = function(message)
        errors[#errors + 1] = message
      end,
      on_expand = function(node, force, callback)
        requests[#requests + 1] = { kind = node.agent_kind, path = node.nodePath, force = force }
        if node.agent_kind == "jobs" then
          if fail_jobs then
            callback(nil, { message = "Jobs request failed" })
          else
            callback({ { id = "job-1", name = "Backup", enabled = true, execution_status = "executing" } })
          end
        elseif node.agent_kind == "job" then
          if deferred_details then
            deferred_details = callback
          else
            callback({
              steps = { { name = "Step", command = "SELECT 1" } },
              schedules = {},
              histories = {},
              linked_alerts = {},
            })
          end
        else
          error("Synthetic node reached service expansion")
        end
      end,
    })
    assert(vim.wait(1000, function()
      return viewed == 5
    end))
    local jobs = options.finder()[5]
    assert(jobs.label == "Jobs")
    options.actions.object_toggle(picker, jobs)
    assert(requests[1].kind == "jobs" and requests[1].path == nil)
    local job = options.finder()[6]
    assert(job.label == "Backup")
    assert(job.node.isLeaf and #options.finder() == 6)
    assert(vim.iter(options.format(job, picker)):any(function(chunk)
      return chunk[2] == "SqlServerJobRunning"
    end))
    options.actions.object_actions(picker, job)
    assert(selected_actions[1].id == "inspect_job")
    assert(selected_actions[2].id == "job_history")
    selected_callback(selected_actions[1])
    assert(requests[2].kind == "job" and requests[2].path == nil)
    local properties_win = vim.api.nvim_get_current_win()
    assert(vim.bo[vim.api.nvim_win_get_buf(properties_win)].filetype == "sqlserver-job-properties")
    vim.api.nvim_win_close(properties_win, true)
    options.actions.object_actions(picker, job)
    selected_callback(selected_actions[2])
    assert(detail_options == nil)
    assert(notifications[#notifications] == "No history for Backup")
    assert(#requests == 2, "History should reuse cached job details")
    options.actions.object_actions(picker, job)
    selected_callback(vim.iter(selected_actions):find(function(action)
      return action.id == "copy_name"
    end))
    assert(copied == "Backup")
    options.actions.object_refresh(picker, job)
    assert(requests[3].kind == "job" and requests[3].force == true)
    fail_jobs = true
    options.actions.object_refresh(picker, jobs)
    assert(#jobs.node.children == 1 and jobs.node.errorMessage == "Jobs request failed")
    assert(errors[#errors] == "Jobs request failed")
    deferred_details = true
    options.actions.object_refresh(picker, job)
    local pending_callback = deferred_details
    options.actions.object_actions(picker, job)
    selected_callback(selected_actions[1])
    options.actions.object_actions(picker, job)
    selected_callback(selected_actions[2])
    pending_callback({ steps = {}, schedules = {}, histories = { { run_at = "Now" } }, linked_alerts = {} })
    assert(detail_options.title == "Job History · Backup")
    assert(detail_options.layout.preset == "select" and detail_options.confirm)
    options.actions.object_refresh(picker, job)
    local late_callback = deferred_details
    explorer.close(7123)
    assert(closed)
    late_callback({ steps = {}, schedules = {}, histories = {}, linked_alerts = {} })
    assert(not job.node.loading)
  end)
  package.loaded.snacks = original
  vim.notify = original_notify
  explorer.close(7123)
  assert(ok, failure)
end

local function with_explorer(test)
  local original = package.loaded.snacks
  local state = { requests = {}, errors = {}, children = {}, active = true, cancellations = 0 }
  local function fake_picker(opts)
    local result = {
      opts = opts,
      closed = false,
      focus = function() end,
      refresh = function() end,
      close = function(self)
        if self.closed then
          return
        end
        self.closed = true
        if opts.on_close then
          opts.on_close(self)
        end
      end,
    }
    return result
  end
  package.loaded.snacks = {
    picker = {
      pick = function(opts)
        local picker = fake_picker(opts)
        if opts.title == "SQL Server Object Explorer" then
          state.picker, state.options = picker, opts
        else
          state.children[#state.children + 1] = picker
        end
        return picker
      end,
      select = function(actions, _, callback)
        state.actions, state.select = actions, callback
      end,
      format = {
        tree = function()
          return {}
        end,
      },
    },
  }
  local database = service_root("Database")
  object_tree.set_service_children(database, {})
  state.root = agent_tree.attach(database, "localhost")
  state.jobs = state.root.children[2].children[1]
  explorer.open({
    bufnr = 7124,
    root = state.root,
    is_active = function()
      return state.active
    end,
    on_cancel_details = function()
      state.cancellations = state.cancellations + 1
    end,
    on_expand = function(node, force, callback)
      state.requests[#state.requests + 1] = { node = node, force = force, done = callback }
    end,
    on_error = function(message)
      state.errors[#state.errors + 1] = message
    end,
  })
  function state.item(node)
    return { node = node, id = node.id, label = node.label }
  end
  function state.action(node, id)
    state.options.actions.object_actions(state.picker, state.item(node))
    for _, action in ipairs(state.actions) do
      assert(not vim.list_contains({ "run", "stop", "start_service", "stop_service" }, action.id))
      if action.id == id then
        state.select(action)
        return
      end
    end
    error("Missing action: " .. id)
  end
  local ok, err = pcall(test, state)
  explorer.close(7124)
  package.loaded.snacks = original
  assert(ok, err)
end

local function fixture_jobs(state)
  agent_tree.set_jobs(state.jobs, {
    { id = "a", name = "First", enabled = true },
    { id = "b", name = "Second", enabled = false },
  })
  return state.jobs.children[1], state.jobs.children[2]
end

T["Agent refresh supersedes replies and releases Search All waiters"] = function()
  with_explorer(function(state)
    fixture_jobs(state)
    state.jobs.loaded = false
    state.options.filter.transform(state.picker, { pattern = "Latest" })
    state.options.confirm(state.picker, state.options.finder()[1])
    assert(#state.requests == 1 and state.requests[1].node == state.jobs)
    assert(state.requests[1].node.nodePath == nil)
    state.options.actions.object_refresh(state.picker, state.item(state.jobs))
    assert(#state.requests == 2 and state.requests[2].force)
    state.requests[1].done(nil, { message = "Old failure" })
    assert(state.jobs.loading and #state.errors == 0)
    state.requests[2].done({ { id = "new", name = "Latest" } })
    assert(state.jobs.children[1].label == "Latest" and not state.jobs.loading)
    assert(not state.options.finder()[1].search_loading)
    assert(vim.iter(state.options.finder()):any(function(item)
      return item.label == "Latest"
    end))
    state.requests[1].done({ { id = "old", name = "Old" } })
    assert(state.jobs.children[1].label == "Latest")
  end)
end

T["Agent Search All keeps service requests separate and retains jobs on errors"] = function()
  with_explorer(function(state)
    local database = state.root.children[1].children[1]
    database.loaded = false
    state.options.filter.transform(state.picker, { pattern = "Second" })
    state.options.confirm(state.picker, state.options.finder()[1])
    assert(state.requests[1].node == database and state.requests[1].node.nodePath == "database")
    state.requests[1].done({})
    assert(state.requests[2].node == state.jobs and state.requests[2].node.nodePath == nil)
    state.requests[2].done({ { id = "b", name = "Second" } })
    assert(#state.requests == 2)
    assert(vim.iter(state.options.finder()):any(function(item)
      return item.label == "Second"
    end))
    state.options.actions.object_refresh(state.picker, state.item(state.jobs))
    state.requests[3].done(nil, { code = "agent_timeout", message = "SQL Agent request timed out" })
    assert(state.jobs.children[1].label == "Second" and state.jobs.loaded)
    assert(state.errors[1] == "SQL Agent request timed out")
  end)
end

T["Details refresh replaces pending replies and retains cached properties on failure"] = function()
  with_explorer(function(state)
    local job = fixture_jobs(state)
    state.options.confirm(state.picker, state.item(job))
    state.options.actions.object_refresh(state.picker, state.item(job))
    assert(#state.requests == 2 and state.requests[2].force)
    state.requests[1].done({ steps = { { name = "Old" } } })
    assert(job.loading and job.details == nil)
    state.requests[2].done({ steps = { { name = "Latest" } } })
    assert(job.details.steps[1].name == "Latest")
    assert(vim.bo[vim.api.nvim_get_current_buf()].filetype == "sqlserver-job-properties")
    state.options.actions.object_refresh(state.picker, state.item(job))
    state.requests[3].done(nil, { message = "Permission denied" })
    assert(job.details.steps[1].name == "Latest" and state.errors[1] == "Permission denied")
    explorer.close(7124)
    assert(not vim.iter(vim.api.nvim_list_wins()):any(function(win)
      return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "sqlserver-job-properties"
    end))
  end)
end

T["Selecting cached jobs cancels late details and refresh invalidates selection"] = function()
  with_explorer(function(state)
    local first, second = fixture_jobs(state)
    second.details = { steps = {} }
    state.options.confirm(state.picker, state.item(first))
    state.options.confirm(state.picker, state.item(second))
    local win = vim.api.nvim_get_current_win()
    assert(state.cancellations == 1 and not first.loading)
    state.requests[1].done(nil, { code = "agent_cancelled", message = "Cancelled" })
    assert(#state.errors == 0 and first.details == nil)
    assert(
      table
        .concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
        :find("Second", 1, true)
    )
    state.options.confirm(state.picker, state.item(first))
    assert(not vim.api.nvim_win_is_valid(win))
    state.options.actions.object_refresh(state.picker, state.item(state.jobs))
    state.requests[2].done({ steps = {} })
    assert(first.details == nil and state.cancellations == 2)
    state.requests[3].done({})
    assert(#state.jobs.children == 0 and state.jobs.annotations[1] == "No jobs")
  end)
end

T["Explorer closure disposes history pickers and floats and ignores disconnected replies"] = function()
  with_explorer(function(state)
    local job = fixture_jobs(state)
    job.details = { histories = { { run_at = "Now", outcome = "succeeded", message = "Done" } } }
    state.action(job, "job_history")
    local child = state.children[1]
    assert(not child.closed)
    explorer.close(7124)
    assert(child.closed)
    child.opts.confirm(child, child.opts.items[1])
    assert(vim.bo.filetype ~= "sqlserver-job-history")
  end)
  with_explorer(function(state)
    local job = fixture_jobs(state)
    job.details = { histories = { { run_at = "Now", outcome = "succeeded" } } }
    state.action(job, "job_history")
    local child = state.children[1]
    child.opts.confirm(child, child.opts.items[1])
    local win = vim.api.nvim_get_current_win()
    assert(child.closed and vim.bo.filetype == "sqlserver-job-history")
    state.active = false
    explorer.close(7124)
    assert(not vim.api.nvim_win_is_valid(win))
  end)
  with_explorer(function(state)
    local job = fixture_jobs(state)
    state.options.confirm(state.picker, state.item(job))
    state.active = false
    state.requests[1].done({ steps = {} })
    assert(job.details == nil and vim.bo.filetype ~= "sqlserver-job-properties")
  end)
end

T["Properties sections and entries navigate and release their buffer"] = function()
  with_explorer(function(state)
    local job = fixture_jobs(state)
    job.details = {
      steps = { { name = "First step", command = "SELECT 1" }, { name = "Second step", command = "SELECT 2" } },
      schedules = { { name = "Daily" }, { name = "Weekly" } },
      linked_alerts = { { name = "Failure" }, { name = "Warning" } },
    }
    state.options.confirm(state.picker, state.item(job))
    local win = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_win_get_buf(win)
    local function press(key, expected)
      vim.api.nvim_feedkeys(key, "xt", false)
      local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
      assert(content:find(expected, 1, true), content)
    end
    press("2", "First step")
    press("]", "Second step")
    press("[", "First step")
    press("[", "Second step")
    press("l", "Daily")
    press("]", "Weekly")
    press("l", "Failure")
    press("]", "Warning")
    press("h", "Daily")
    press("1", "Job: First")
    vim.api.nvim_feedkeys("q", "xt", false)
    assert(not vim.api.nvim_win_is_valid(win) and not vim.api.nvim_buf_is_valid(bufnr))
  end)
end

return T
