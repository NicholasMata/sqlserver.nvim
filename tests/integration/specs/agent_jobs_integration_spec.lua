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
      return open.opts.title == "sqlserver.nvim fixture no history"
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
      return open.opts.title == "sqlserver.nvim fixture history"
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
        return not picker.closed and vim.api.nvim_get_current_win() == picker.list.win.win
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

return T
