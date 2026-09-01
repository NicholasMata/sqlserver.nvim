local query_result = require("sqlserver.core.query_result")
local result_cell = require("sqlserver.core.result_cell")
local renderer = require("sqlserver.ui.results.renderer")

return {
  test_name = "Result renderer preserves models and describes truncation",
  run_test_async = function()
    local model = query_result.create({
      columns = { "ID", "Payload" },
      rows = {
        { result_cell.create({ display_value = "1" }), result_cell.create({ display_value = "a long value" }) },
        {
          result_cell.create({ display_value = "2" }),
          result_cell.create({ display_value = "NULL", is_null = true }),
        },
        {
          result_cell.create({ display_value = "3" }),
          result_cell.create({ display_value = "NULL", is_null = false }),
        },
      },
      row_count = 5,
      locator = { resultSetIndex = 0 },
    })
    local rendered = renderer.render(model, { max_cell_width = 6 })
    local text = table.concat(rendered.lines, "\n")

    assert(model.rows[1][2].display_value == "a long value", "Rendering mutated the result model")
    assert(model.truncated and model.displayed_row_count == 3)
    assert(text:find("ID", 1, true) and text:find("│", 1, true))
    assert(text:find("a lon…", 1, true), "Expected a visibly truncated cell")
    assert(text:find("Showing 3 of 5 rows", 1, true))
    assert(#rendered.decorations >= 4, "Expected semantic result highlights")

    local null_highlights = vim
      .iter(rendered.decorations)
      :filter(function(decoration)
        return decoration.highlight == "SqlServerResultNull"
      end)
      :totable()
    assert(#null_highlights == 1, "Only database NULL should receive null highlighting")
  end,
}
