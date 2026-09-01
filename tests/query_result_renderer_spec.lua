local query_result = require("sqlserver.core.query_result")
local renderer = require("sqlserver.ui.results.renderer")

return {
	test_name = "Result renderer preserves models and describes truncation",
	run_test_async = function()
		local model = query_result.create({
			columns = { "ID", "Payload" },
			rows = { { "1", "a long value" }, { "2", "NULL" } },
			row_count = 5,
			locator = { resultSetIndex = 0 },
		})
		local rendered = renderer.render(model, { max_cell_width = 6 })
		local text = table.concat(rendered.lines, "\n")

		assert(model.rows[1][2] == "a long value", "Rendering mutated the result model")
		assert(model.truncated and model.displayed_row_count == 2)
		assert(text:find("ID", 1, true) and text:find("│", 1, true))
		assert(text:find("a lon…", 1, true), "Expected a visibly truncated cell")
		assert(text:find("Showing 2 of 5 rows", 1, true))
		assert(#rendered.decorations >= 4, "Expected semantic result highlights")
	end,
}
