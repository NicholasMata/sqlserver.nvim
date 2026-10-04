local integration = require("tests.helpers.integration")
local utils = require("sqlserver.utils")
local T = MiniTest.new_set()

local function execute(bufnr, sql, kind)
  local client = integration.get_sql_client(bufnr)
  local response, err = utils.lsp_request_async(client, "query/executeString", {
    ownerUri = utils.lsp_file_uri(bufnr),
    query = sql,
    executionPlanOptions = kind and { ["include" .. kind .. "ExecutionPlanXml"] = true } or nil,
  }, bufnr)
  assert(response and not err, err and err.message)
  return assert(utils.wait_for_notification_async(bufnr, client, "query/complete", 30000))
end

local function plans(bufnr, completed)
  local captured = {}
  for bi, batch in ipairs(completed.batchSummaries) do
    assert(not batch.hasError, "Plan capture failed")
    for ri, result in ipairs(batch.resultSetSummaries or {}) do
      if result.specialAction and result.specialAction.expectYukonXMLShowPlan == true then
        assert(result.rowCount == 1)
        local response, err = utils.lsp_request_async(integration.get_sql_client(bufnr), "query/executionPlan", {
          ownerUri = utils.lsp_file_uri(bufnr),
          batchIndex = bi - 1,
          resultSetIndex = ri - 1,
        })
        assert(not err and response.executionPlan.format == "xml")
        local xml = response.executionPlan.content
        assert(xml:find("<ShowPlanXML", 1, true) and xml:find("</ShowPlanXML>", 1, true))
        captured[#captured + 1] = xml
      end
    end
  end
  return captured
end

local function scalar(bufnr, sql)
  return utils.get_query_result_async(execute(bufnr, sql))[1].Value
end

T["Estimated plans do not execute writes; actual plans execute once"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  execute(bufnr, "UPDATE TestDbA.dbo.PlanCapture SET Value = 0 WHERE ID = 1")
  local sql =
    "UPDATE TestDbA.dbo.PlanCapture SET Value = Value + 1 WHERE ID = 1; SELECT Value FROM TestDbA.dbo.PlanCapture WHERE ID = 1;"
  local estimated = plans(bufnr, execute(bufnr, sql, "Estimated"))
  assert(#estimated == 1 and not estimated[1]:find("RunTimeCountersPerThread", 1, true))
  assert(scalar(bufnr, "SELECT Value FROM TestDbA.dbo.PlanCapture WHERE ID = 1") == "0")
  local completed = execute(bufnr, sql, "Actual")
  local actual = plans(bufnr, completed)
  assert(#actual > 0 and actual[1]:find("RunTimeCountersPerThread", 1, true))
  local normal_index
  for index, result in ipairs(completed.batchSummaries[1].resultSetSummaries) do
    if result.specialAction.expectYukonXMLShowPlan == false then
      normal_index = index - 1
    end
  end
  assert(normal_index, "Actual capture must preserve the ordinary SELECT result")
  local rows = assert(utils.lsp_request_async(integration.get_sql_client(bufnr), "query/subset", {
    ownerUri = utils.lsp_file_uri(bufnr),
    batchIndex = 0,
    resultSetIndex = normal_index,
    rowsStartIndex = 0,
    rowsCount = 1,
  }))
  assert(rows.resultSubset.rows[1][1].displayValue == "1")
  assert(scalar(bufnr, "SELECT Value FROM TestDbA.dbo.PlanCapture WHERE ID = 1") == "1")
end)

T["Plans preserve statements, GO batches, and procedure parameters"] = require("tests.helpers").async(function()
  local bufnr = vim.api.nvim_get_current_buf()
  local sql =
    "SELECT Value FROM TestDbA.dbo.PlanCapture WHERE ID = 1; SELECT Value FROM TestDbA.dbo.PlanCapture WHERE ID = 2;\nGO\nEXEC TestDbA.dbo.GetPlanCapture @ID = 1;"
  for _, kind in ipairs({ "Estimated", "Actual" }) do
    local captured = plans(bufnr, execute(bufnr, sql, kind))
    assert(#captured >= 2)
    if kind == "Estimated" then
      assert(captured[1]:find('StatementId="2"', 1, true), "Estimated statements must remain in the plan document")
    else
      assert(#captured == 3, "Actual plans are separate documents per executed statement")
    end
    assert(captured[#captured]:find("PlanCapture", 1, true))
  end
  local client = integration.get_sql_client(bufnr)
  utils.lsp_request_async(client, "query/dispose", { ownerUri = utils.lsp_file_uri(bufnr) })
  local response, err = utils.lsp_request_async(client, "query/executionPlan", {
    ownerUri = utils.lsp_file_uri(bufnr),
    batchIndex = 0,
    resultSetIndex = 0,
  })
  assert(err and not response, "Disposed plans must be unavailable")
end)

T["Missing plans and SHOWPLAN permission failures remain distinct"] = require("tests.helpers").async(function()
  local admin = vim.api.nvim_get_current_buf()
  assert(#plans(admin, execute(admin, "PRINT N'No query plan'", "Actual")) == 0)
  local bufnr = integration.new_query_buffer()
  integration.connect_with(bufnr, {
    database = "TestDbA",
    user = "sqlserver_nvim_plan_limited",
    password = "Test_Plan_Limited_123",
  })
  assert(scalar(bufnr, "SELECT Value FROM dbo.PlanCapture WHERE ID = 1"))
  for _, kind in ipairs({ "Estimated", "Actual" }) do
    local completed = execute(bufnr, "SELECT Value FROM dbo.PlanCapture WHERE ID = 1", kind)
    assert(completed.batchSummaries[1].hasError == true)
    assert(not vim.iter(completed.batchSummaries[1].resultSetSummaries):any(function(result)
      return result.specialAction.expectYukonXMLShowPlan == true
    end))
  end
end)

return T
