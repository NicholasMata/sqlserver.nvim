local winbar = require("sqlserver.results.ui.winbar")

local T = MiniTest.new_set()

T["Result winbar should separate metadata from navigation"] = function()
  local rendered = winbar.render({
    source_name = "query.sql",
    execution = 2,
    execution_count = 4,
    result = 1,
    result_count = 2,
    displayed_rows = 42,
    total_rows = 42,
    duration_ms = 38,
  })

  assert(rendered == "query.sql  42 rows  38 ms%=Execution 2/4  Result 1/2 ")
end

T["Result winbar should compactly describe limited results"] = function()
  local rendered = winbar.render({
    source_name = "100% query.sql",
    execution = 1,
    execution_count = 1,
    result = 1,
    result_count = 1,
    displayed_rows = 100,
    total_rows = 10000,
    duration_ms = 1250,
  })

  assert(rendered:find("100%% query.sql  100 of 10,000 rows  1.25 s%=", 1, true))
  assert(rendered:find("Execution 1/1  Result 1/1", 1, true))
end

return T
