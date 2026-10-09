local sqlserver = require("sqlserver")
local integration = require("tests.helpers.integration")
local registry = require("sqlserver.workspace.registry")
local view = require("sqlserver.results.ui.view")
local h = require("tests.helpers")
local T = MiniTest.new_set()
local sql = "SELECT Value FROM TestDbA.dbo.PlanCapture WHERE ID = 1;"
local function execute(opts)
  return integration.await(function(callback)
    sqlserver.execute(opts, callback)
  end)
end
local function read(path)
  local fd = assert(vim.uv.fs_open(path, "r", 438))
  local data = vim.uv.fs_read(fd, assert(vim.uv.fs_fstat(fd)).size, 0)
  vim.uv.fs_close(fd)
  return data
end

T["Capture API preserves plans and ordinary results across replacement and disconnect"] = h.async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  local estimated = execute({ bufnr = bufnr, text = sql, plan = "estimated" })
  assert(estimated.plan_status == "captured" and #estimated.plans == 1 and #estimated.result_sets == 0)
  assert(estimated.summary.row_count == 0 and estimated.summary.result_set_count == 0)
  local original = estimated.plans[1].xml
  local actual = execute({ bufnr = bufnr, text = sql .. "\nGO\n" .. sql, plan = "actual" })
  assert(#actual.plans == 2 and #actual.result_sets == 2 and actual.summary.row_count == 2)
  assert(actual.plans[1].xml:find("RunTimeCountersPerThread", 1, true))
  assert(actual.plans[2].batch_index == 1)
  execute({ bufnr = bufnr, text = "SELECT 42 AS Replacement" })
  integration.await(function(callback)
    sqlserver.disconnect(bufnr, callback)
  end)
  local path = vim.fn.tempname() .. ".sqlplan"
  integration.await(function(callback)
    sqlserver.export_plan({ plan = estimated.plans[1], path = path }, callback)
  end)
  assert(read(path) == original, "Plan export must preserve the captured bytes after query disposal/disconnect")
  vim.fn.delete(path)
  local opened = integration.await(function(callback)
    sqlserver.open_plan({ plan = actual.plans[2] }, callback)
  end)
  assert(vim.bo[opened.bufnr].filetype == "xml")
  assert(#vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false) > 0)
  assert(vim.b[opened.bufnr].sqlserver_plan.xml == actual.plans[2].xml)
  vim.api.nvim_win_close(0, true)
end)

T["Statement, selection, and whole-buffer commands capture into bounded history"] = h.async(function()
  local source = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { sql, sql })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local statement = execute({ bufnr = source, scope = "statement", plan = "estimated" })
  assert(#statement.plans == 1 and #statement.result_sets == 0)
  local selection = execute({
    bufnr = source,
    plan = "actual",
    request = {
      kind = "selection",
      range = { startLine = 1, startColumn = 0, endLine = 1, endColumn = #sql },
    },
  })
  assert(#selection.plans == 1 and #selection.result_sets == 1)
  local opts = {
    results = { history_limit = 2, max_cell_width = 100 },
    open_results_in = function(buf)
      vim.api.nvim_set_current_buf(buf)
    end,
  }
  view.show(statement.result_sets, opts, source, statement.dispose, statement.plans)
  local first = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(source)
  sqlserver.commands.actual_plan_buffer()
  assert(
    vim.wait(30000, function()
      return registry.get(source).get_state() == require("sqlserver.workspace").states.connected
        and #view.execution_plans(source) == 2
    end, 10),
    "ActualPlanBuffer failed to retain both statements' plans"
  )
  assert(view.has_results(source))
  assert(view.show_plan(1, opts.open_results_in))
  assert(vim.bo.filetype == "xml")
  assert(view.previous_execution(opts.open_results_in) and vim.api.nvim_get_current_buf() == first)
  vim.api.nvim_set_current_buf(source)
  local newer = execute({ bufnr = source, text = sql, plan = "estimated" })
  view.show(newer.result_sets, opts, source, newer.dispose, newer.plans)
  assert(not vim.api.nvim_buf_is_valid(first))
end)

T["Capture errors, no plan, and cancellation produce distinct outcomes"] = h.async(function()
  local source = vim.api.nvim_get_current_buf()
  local empty = execute({ bufnr = source, text = "PRINT N'no plan'", plan = "actual" })
  assert(empty.plan_status == "none" and #empty.plans == 0 and not empty.cancelled)
  local result
  local failure
  sqlserver.execute(
    { bufnr = source, text = "WAITFOR DELAY '00:00:10'; " .. sql, plan = "actual" },
    function(value, err)
      result = value
      failure = err
    end
  )
  integration.defer_async(100)
  integration.await(function(callback)
    sqlserver.cancel(source, callback)
  end)
  assert(vim.wait(30000, function()
    return result ~= nil or failure ~= nil
  end, 10))
  assert(not failure and result.cancelled)
  assert(#(result.plans or {}) == 0)
  local limited = integration.new_query_buffer()
  integration.connect_with(
    limited,
    { database = "TestDbA", user = "sqlserver_nvim_plan_limited", password = "Test_Plan_Limited_123" }
  )
  result = nil
  failure = nil
  sqlserver.execute(
    { bufnr = limited, text = "SELECT Value FROM dbo.PlanCapture WHERE ID = 1", plan = "estimated" },
    function(value, err)
      result = value
      failure = err
    end
  )
  assert(vim.wait(30000, function()
    return result ~= nil or failure ~= nil
  end, 10))
  assert(not result and failure.code == "plan_capture_failed")
  assert(registry.get(limited).get_active_operation() == nil)
end)

T["Estimated plan commands focus the plan and respect split placement"] = h.async(function()
  local source = vim.api.nvim_get_current_buf()
  local source_window = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { sql })
  integration.await(function(callback)
    sqlserver.setup({
      open_results_in = "split",
      results = { column_icons = true, cell_navigation = true },
    }, callback)
  end)
  local original_splitbelow = vim.o.splitbelow
  for index, command in ipairs({ "EstimatedPlan", "EstimatedPlanBuffer" }) do
    vim.o.splitbelow = index == 2
    vim.api.nvim_set_current_win(source_window)
    vim.api.nvim_win_set_cursor(source_window, { 1, 0 })
    vim.cmd("SQLServer " .. command)
    assert(
      vim.wait(30000, function()
        return registry.get(source).get_state() == require("sqlserver.workspace").states.connected
          and vim.bo.filetype == "xml"
      end, 10),
      command .. " did not focus the captured plan"
    )
    local plan_window = vim.api.nvim_get_current_win()
    assert(plan_window ~= source_window)
    local plan_row = vim.api.nvim_win_get_position(plan_window)[1]
    local source_row = vim.api.nvim_win_get_position(source_window)[1]
    assert((plan_row > source_row) == vim.o.splitbelow, "Plan ignored splitbelow")
    assert(vim.b.sqlserver_plan.xml and vim.bo.readonly)
    vim.cmd("SQLServer ShowQuery")
    assert(vim.api.nvim_get_current_win() == source_window, "ShowQuery did not focus the plan's source")
    vim.api.nvim_win_close(plan_window, true)
  end
  vim.o.splitbelow = original_splitbelow
end)

T["Ex ranges capture only the requested lines"] = h.async(function()
  local source = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "SELECT 42 AS Unselected;", sql })
  vim.cmd("2SQLServer EstimatedPlan")
  assert(vim.wait(30000, function()
    return registry.get(source).get_state() == require("sqlserver.workspace").states.connected
      and #view.execution_plans(source) == 1
  end, 10))
  local captured = view.execution_plans(source)[1]
  assert(captured.xml:find("PlanCapture", 1, true))
  assert(not captured.xml:find("Unselected", 1, true))
end)

return T
