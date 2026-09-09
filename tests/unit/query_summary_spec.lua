local query_summary = require("sqlserver.queries.summary")

local T = MiniTest.new_set()

T["Query summaries should preserve mixed outcomes"] = require("tests.helpers").async(function()
  local summary = query_summary.create({
    batchSummaries = {
      {
        hasError = true,
        executionElapsed = "00:00:01.2500000",
        resultSetSummaries = {
          { rowCount = 2 },
        },
      },
      {
        hasError = false,
        executionElapsed = "1.02:03:04.5000000",
        resultSetSummaries = {
          { rowCount = 3 },
          { rowCount = 0 },
        },
      },
    },
  })

  assert(summary.batch_count == 2)
  assert(summary.result_set_count == 3)
  assert(summary.row_count == 5)
  assert(summary.has_error)
  assert(summary.server_duration_ms == 93785750)
end)

return T
