local query_summary = require("sqlserver.core.query_summary")

return {
  test_name = "Query summaries should preserve mixed outcomes",
  run_test_async = function()
    local summary = query_summary.create({
      batchSummaries = {
        {
          hasError = true,
          resultSetSummaries = {
            { rowCount = 2 },
          },
        },
        {
          hasError = false,
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
  end,
}
