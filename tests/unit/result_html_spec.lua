local result_cell = require("sqlserver.results.cell")
local result_html = require("sqlserver.results.html")

local T = MiniTest.new_set()

T["HTML result rendering should include only selected cells"] = function()
  local html = result_html.render({
    columns = { "ID", "Name & note", "Ignored" },
    rows = {
      {
        result_cell.create({ display_value = "1" }),
        result_cell.create({ display_value = "<Ada>\nLovelace" }),
        result_cell.create({ display_value = "hidden" }),
      },
      {
        result_cell.create({ display_value = "2" }),
        result_cell.create({ display_value = 'Grace "Amazing"' }),
        result_cell.create({ display_value = "hidden" }),
      },
    },
  }, {
    row_start = 0,
    row_end = 1,
    column_start = 1,
    column_end = 1,
  })

  assert(html:find("Name &amp; note", 1, true))
  assert(html:find("&lt;Ada&gt;<br>Lovelace", 1, true))
  assert(html:find("Grace &quot;Amazing&quot;", 1, true))
  assert(not html:find("Ignored", 1, true) and not html:find("hidden", 1, true))
  assert(not html:find("style=", 1, true), "Clipboard HTML should leave presentation to the destination")
end

return T
