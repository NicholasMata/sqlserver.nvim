local adapter = require("sqlserver.adapters.sql_tools_service.plans")
local api = require("sqlserver.api")
local workspace_module = require("sqlserver.workspace")
local registry = require("sqlserver.workspace.registry")
local view = require("sqlserver.results.ui.view")
local files = require("sqlserver.plans.files")
local plan_ui = require("sqlserver.plans.ui")
local h = require("tests.helpers")
local T = MiniTest.new_set()
local xml =
  '<ShowPlanXML xmlns="http://schemas.microsoft.com/sqlserver/2004/07/showplan"><BatchSequence>日本語 &amp; test</BatchSequence></ShowPlanXML>'
local function plan(kind, ordinal)
  return { xml = xml, kind = kind or "estimated", ordinal = ordinal or 1, batch_index = 0, result_index = 1 }
end
local function raw()
  return {
    ownerUri = "file:///plans.sql",
    _sqlserver_query_id = 1,
    batchSummaries = {
      {
        hasError = false,
        selection = { startLine = 2, endLine = 5 },
        resultSetSummaries = {
          { rowCount = 1, columnInfo = { { columnName = "Value", dataTypeName = "int" } } },
          { rowCount = 1, columnInfo = { { columnName = "XML" } }, specialAction = { expectYukonXMLShowPlan = true } },
        },
      },
    },
  }
end

T["Plan adapter retrieves only flagged results and normalizes snapshots"] = h.async(function()
  local requests = {}
  local client = {
    request = function(_, method, params, callback)
      requests[#requests + 1] = { method = method, params = params }
      callback(nil, { executionPlan = { format = "xml", content = xml } })
      return true, 1
    end,
  }
  local completed = raw()
  local captured = adapter.collect_async(client, completed, "actual", 1000, function()
    return true
  end)
  assert(#captured == 1 and captured[1].xml == xml and captured[1].kind == "actual")
  assert(requests[1].method == "query/executionPlan" and requests[1].params.resultSetIndex == 1)
  assert(captured[1].batch_index == 0 and captured[1].batch_range.start_line == 2)
  completed.batchSummaries[1].selection.startLine = 99
  assert(captured[1].batch_range.start_line == 2)
  local collected = require("sqlserver.results.collection").collect_async(completed, 10, function(locator)
    assert(locator.resultSetIndex == 0)
    return { { require("sqlserver.results.cell").create({ display_value = "42" }) } }
  end)
  assert(#collected == 1)
  local summary = require("sqlserver.queries.summary").create(completed)
  assert(summary.row_count == 1 and summary.result_set_count == 1)
end)

T["Plan adapter rejects incomplete and unsupported responses"] = h.async(function()
  for _, response in ipairs({
    {},
    { executionPlan = { format = "json", content = xml } },
    { executionPlan = { format = "xml", content = "<ShowPlanXML>truncated" } },
  }) do
    local client = {
      request = function(_, _, _, callback)
        callback(nil, response)
        return true, 1
      end,
    }
    local ok, err = pcall(adapter.collect_async, client, raw(), "estimated", 1000)
    assert(not ok and (err.code == "plan_capture_failed" or err.code == "invalid_plan"))
  end
end)

T["Plan requests time out and ignore late responses"] = h.async(function()
  local callback
  local cancelled = 0
  local client = {
    request = function(_, _, _, handler)
      callback = handler
      return true, 9
    end,
    cancel_request = function(_, id)
      assert(id == 9)
      cancelled = cancelled + 1
    end,
  }
  local ok, err = pcall(adapter.collect_async, client, raw(), "actual", 10)
  assert(not ok and err.code == "plan_timeout" and cancelled == 1)
  callback(nil, { executionPlan = { format = "xml", content = xml } })
end)

T["Plan requests cancel during collection and reject transport failures"] = h.async(function()
  local active = true
  local cancelled = 0
  local client = {
    request = function()
      vim.defer_fn(function()
        active = false
      end, 10)
      return true, 9
    end,
    cancel_request = function()
      cancelled = cancelled + 1
    end,
  }
  local ok, err = pcall(adapter.collect_async, client, raw(), "actual", false, function()
    return active
  end)
  assert(not ok and err.code == "plan_cancelled" and cancelled == 1)
  local rejected = {
    request = function()
      return false
    end,
  }
  ok, err = pcall(adapter.collect_async, rejected, raw(), "actual", 1000)
  assert(not ok and err.code == "plan_capture_failed")
end)

local function setup_workspace(fetch)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local count = 0
  local requests = {}
  local disposed = 0
  local workspace = workspace_module.create({
    bufnr = bufnr,
    objects = {},
    backend = {
      owner_uri = "file:///plans.sql",
      connect_async = function()
        return {}
      end,
      execute_async = function(request)
        requests[#requests + 1] = request
        count = count + 1
        local result = raw()
        result._sqlserver_query_id = count
        return result
      end,
      fetch_result_rows_async = function()
        return { { require("sqlserver.results.cell").create({ display_value = "42" }) } }
      end,
      fetch_execution_plans_async = fetch,
      cancel_async = function() end,
      disconnect_async = function() end,
      dispose_query_async = function()
        disposed = disposed + 1
      end,
    },
  })
  registry.attach(bufnr, workspace)
  workspace.connect_async({
    connection = { options = { server = "localhost", database = "TestDbA", password = "Secret" } },
  })
  api.configure({ results = { max_rows = 10 }, timeouts = { export = false } })
  return bufnr,
    workspace,
    requests,
    function()
      return disposed
    end,
    function()
      view.clear(bufnr)
      registry.detach(bufnr)
      workspace.dispose_async()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

T["Plan capture holds the execution lock and retains secret-free context"] = h.async(function()
  local thread
  local bufnr, workspace, requests, _, cleanup = setup_workspace(function(_, kind, timeout)
    assert(kind == "actual" and timeout == false)
    thread = coroutine.running()
    return coroutine.yield()
  end)
  local execution
  api.execute({ bufnr = bufnr, text = "SELECT 42", plan = "actual" }, function(value, err)
    assert(not err)
    execution = value
  end)
  assert(workspace.get_state() == workspace_module.states.executing)
  assert(workspace.get_active_operation().phase == "loading_plans")
  local concurrent_error
  api.execute({ bufnr = bufnr, text = "SELECT 84" }, function(_, err)
    concurrent_error = err
  end)
  assert(concurrent_error and #requests == 1)
  coroutine.resume(thread, { plan("actual") })
  assert(execution.plan_status == "captured" and #execution.plans == 1 and #execution.result_sets == 1)
  assert(execution.plans[1].connection.database == "TestDbA" and execution.plans[1].connection.password == nil)
  assert(execution.plans[1].source_bufnr == bufnr and execution.plans[1].execution_id == 1)
  assert(requests[1].plan == "actual")
  cleanup()
end)

T["Cancellation and disconnect suppress late plan presentation"] = h.async(function()
  for _, dispose in ipairs({ false, true }) do
    local thread
    local bufnr, workspace, _, disposed, cleanup = setup_workspace(function()
      thread = coroutine.running()
      return coroutine.yield()
    end)
    local result
    local presented = false
    api.execute({
      bufnr = bufnr,
      text = "SELECT 42",
      plan = "actual",
      _present = function()
        presented = true
      end,
    }, function(value, err)
      assert(not err)
      result = value
    end)
    if dispose then
      workspace.dispose_async()
    else
      workspace.cancel_async()
    end
    coroutine.resume(thread, { plan("actual") })
    assert(result.cancelled and not presented and disposed() > 0)
    assert(
      workspace.get_state() == (dispose and workspace_module.states.disconnected or workspace_module.states.connected)
    )
    cleanup()
  end
end)

T["Capture failure never presents partial plans and ends the operation"] = h.async(function()
  local bufnr, workspace, _, disposed, cleanup = setup_workspace(function()
    error({ code = "plan_capture_failed", message = "Second plan retrieval failed" }, 0)
  end)
  local failure
  local presented = false
  api.execute({
    bufnr = bufnr,
    text = "SELECT 42",
    plan = "actual",
    _present = function()
      presented = true
    end,
  }, function(result, err)
    assert(not result)
    failure = err
  end)
  assert(failure.code == "plan_capture_failed" and not presented and disposed() > 0)
  assert(workspace.get_active_operation() == nil and workspace.get_state() == workspace_module.states.connected)
  cleanup()
end)

T["Plan export preserves exact XML and handles overwrite and write failures"] = function()
  local path = vim.fn.tempname() .. ".sqlplan"
  files.save(plan(), path)
  local function read()
    local fd = assert(vim.uv.fs_open(path, "r", 438))
    local data = vim.uv.fs_read(fd, assert(vim.uv.fs_fstat(fd)).size, 0)
    vim.uv.fs_close(fd)
    return data
  end
  assert(read() == xml)
  local ok, err = pcall(files.save, plan(), path)
  assert(not ok and err.code == "plan_export_failed" and read() == xml)
  files.save(plan(), path, true)
  assert(read() == xml)
  local write = vim.uv.fs_write
  vim.uv.fs_write = function()
    return nil, "write failed"
  end
  ok, err = pcall(files.save, plan(), path, true)
  vim.uv.fs_write = write
  assert(not ok and err.code == "plan_export_failed" and read() == xml)
  vim.fn.delete(path)
  ok, err = pcall(files.save, plan(), path .. "/missing.sqlplan")
  assert(not ok and err.code == "plan_export_failed")
end

T["Plan-only history and mixed results navigate and clean up together"] = function()
  view.clear()
  local source = vim.api.nvim_create_buf(false, true)
  local opts = {
    results = { max_cell_width = 100, history_limit = 2 },
    open_results_in = function(buf)
      vim.api.nvim_set_current_buf(buf)
    end,
  }
  local original = plan()
  view.show({}, opts, source, nil, { original })
  local first = vim.api.nvim_get_current_buf()
  assert(vim.bo[first].filetype == "xml" and vim.bo[first].readonly)
  assert(view.render_winbar():find("Estimated plan", 1, true))
  original.xml = "changed"
  assert(view.execution_plans()[1].xml == xml)
  local collected = require("sqlserver.results.collection").collect_async(raw(), 10, function()
    return { { require("sqlserver.results.cell").create({ display_value = "42" }) } }
  end)
  view.show(collected, opts, source, nil, { plan("actual") })
  assert(view.execution_plans()[1].kind == "actual")
  assert(view.next_result())
  assert(vim.bo.filetype == "xml" and not view.copy_cell())
  assert(view.previous_execution(opts.open_results_in) and vim.api.nvim_get_current_buf() == first)
  view.show({}, opts, source, nil, { plan() })
  assert(not vim.api.nvim_buf_is_valid(first))
  local current = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_delete(source, { force = true })
  assert(not vim.api.nvim_buf_is_valid(current) and not view.has_results(source))
  view.clear()
end

T["Failed plan preparation rolls back and preserves previous history"] = function()
  view.clear()
  local source = vim.api.nvim_create_buf(false, true)
  local opts = {
    results = { history_limit = 1 },
    open_results_in = function(buf)
      vim.api.nvim_set_current_buf(buf)
    end,
  }
  view.show({}, opts, source, nil, { plan() })
  local first = vim.api.nvim_get_current_buf()
  local before = #vim.api.nvim_list_bufs()
  local ok = pcall(view.show, {}, opts, source, nil, { { xml = "invalid" } })
  assert(not ok and vim.api.nvim_get_current_buf() == first and #vim.api.nvim_list_bufs() == before)
  assert(view.execution_plans()[1].xml == xml)
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end

T["Plan winbar shares the source indicator and source navigation"] = function()
  view.clear()
  local source = vim.api.nvim_create_buf(false, true)
  local opts = {
    results = { max_cell_width = 100, history_limit = 2 },
    open_results_in = function(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
    end,
  }
  view.show({}, opts, source, nil, { plan() })
  local plan_buffer = vim.api.nvim_get_current_buf()
  local plan_window = vim.api.nvim_get_current_win()
  assert(view.render_winbar():find("↗", 1, true))
  assert(view.render_winbar():find("Plan 1/1", 1, true))
  assert(view.show_query() and vim.api.nvim_get_current_buf() == source)
  local source_window = vim.api.nvim_get_current_win()
  assert(not view.render_winbar(plan_buffer):find("↗", 1, true))
  assert(vim.b[plan_buffer].sqlserver_plan.xml == xml)
  vim.api.nvim_set_current_win(plan_window)
  assert(view.show_query() and vim.api.nvim_get_current_win() == source_window)
  vim.api.nvim_win_close(source_window, true)
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end

T["Public plan viewing and export work without a connected workspace"] = function()
  api.configure({ results = { max_rows = 10 } })
  local path = vim.fn.tempname() .. ".sqlplan"
  local saved
  api.export_plan({ plan = plan(), path = path }, function(result, err)
    assert(not err)
    saved = result
  end)
  assert(saved.path == path)
  local opened
  api.open_plan({ plan = plan() }, function(result, err)
    assert(not err)
    opened = result.bufnr
  end)
  assert(vim.bo[opened].filetype == "xml")
  assert(#vim.api.nvim_buf_get_lines(opened, 0, -1, false) > 0)
  assert(vim.b[opened].sqlserver_plan.xml == xml)
  vim.api.nvim_win_close(0, true)
  assert(not vim.api.nvim_buf_is_valid(opened))
  vim.fn.delete(path)
  local err
  api.export_plan({ plan = plan(), path = "bad.xml" }, function(_, failure)
    err = failure
  end)
  assert(err.code == "invalid_argument")
end

T["Plan inspection uses the XML filetype's configured formatexpr"] = function()
  local calls = 0
  _G.sqlserver_test_xml_format = function()
    calls = calls + 1
    assert(vim.bo.filetype == "xml")
    assert(vim.v.lnum == 1 and vim.v.count == 1)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "<ShowPlanXML>", "  <BatchSequence/>", "</ShowPlanXML>" })
    return 0
  end
  local autocmd = vim.api.nvim_create_autocmd("FileType", {
    pattern = "xml",
    callback = function()
      vim.bo.formatexpr = "v:lua.sqlserver_test_xml_format()"
    end,
  })
  local source = vim.api.nvim_get_current_buf()
  local transaction = require("sqlserver.plans.ui").prepare(plan())
  vim.api.nvim_del_autocmd(autocmd)
  _G.sqlserver_test_xml_format = nil
  assert(calls == 1)
  assert(vim.api.nvim_get_current_buf() == source)
  assert(#vim.api.nvim_buf_get_lines(transaction.bufnr, 0, -1, false) == 3)
  assert(vim.b[transaction.bufnr].sqlserver_plan.xml == xml)
  assert(vim.bo[transaction.bufnr].readonly and not vim.bo[transaction.bufnr].modifiable)
  assert(not vim.bo[transaction.bufnr].modified)
  transaction.rollback()
end

T["Plan inspection uses configured formatprg without changing snapshot XML"] = function()
  -- cat is a real, identity formatprg available on the local/CI Unix hosts.
  if vim.fn.executable("cat") == 0 then
    return
  end
  local autocmd = vim.api.nvim_create_autocmd("FileType", {
    pattern = "xml",
    callback = function()
      vim.bo.formatexpr = ""
      vim.bo.formatprg = "cat"
    end,
  })
  local transaction = require("sqlserver.plans.ui").prepare(plan())
  vim.api.nvim_del_autocmd(autocmd)
  assert(table.concat(vim.api.nvim_buf_get_lines(transaction.bufnr, 0, -1, false), "\n") == xml)
  assert(vim.b[transaction.bufnr].sqlserver_plan.xml == xml)
  transaction.rollback()
end

T["Plan inspection leaves XML unchanged when no formatter is configured"] = function()
  local autocmd = vim.api.nvim_create_autocmd("FileType", {
    pattern = "xml",
    callback = function()
      vim.bo.formatexpr = ""
      vim.bo.formatprg = ""
    end,
  })
  local transaction = require("sqlserver.plans.ui").prepare(plan())
  vim.api.nvim_del_autocmd(autocmd)
  assert(table.concat(vim.api.nvim_buf_get_lines(transaction.bufnr, 0, -1, false), "\n") == xml)
  transaction.rollback()
end

T["Plan Ex ranges preserve line boundaries and Unicode columns"] = function()
  local source = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(source)
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "SELECT 1;", "SELECT N'日本語';", "SELECT 3;" })
  local request
  require("sqlserver.ui.commands").setup({
    estimated_plan = function(opts)
      request = opts.request
    end,
  })
  vim.cmd("2SQLServer EstimatedPlan")
  assert(request.kind == "selection" and request.range.startLine == 1 and request.range.endLine == 1)
  assert(request.range.endColumn == vim.str_utfindex("SELECT N'日本語';", "utf-16"))
  vim.api.nvim_buf_delete(source, { force = true })
end

T["Invalid plan options fail before SQL execution"] = h.async(function()
  local bufnr, _, requests, _, cleanup = setup_workspace(function()
    return {}
  end)
  for _, kind in ipairs({ "unknown", false }) do
    local failure
    api.execute({ bufnr = bufnr, text = "UPDATE something", plan = kind }, function(_, err)
      failure = err
    end)
    assert(failure.code == "invalid_argument" and #requests == 0)
  end
  cleanup()
end)

return T
