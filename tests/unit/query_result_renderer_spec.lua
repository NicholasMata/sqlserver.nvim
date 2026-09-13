local query_result = require("sqlserver.results.result_set")
local result_cell = require("sqlserver.results.cell")
local renderer = require("sqlserver.results.ui.renderer")
local result_sets = require("sqlserver.results.collection")

local T = MiniTest.new_set()

T["Result descriptions retain SQL Tools Service column metadata"] = function()
  local metadata = {
    columnName = "Amount",
    dataTypeName = "decimal",
    numericPrecision = 12,
    numericScale = 2,
    allowDBNull = false,
  }
  local descriptors = result_sets.describe({
    ownerUri = "file:///query.sql",
    batchSummaries = {
      {
        hasError = false,
        executionElapsed = "00:00:00.1250000",
        resultSetSummaries = { { rowCount = 0, columnInfo = { metadata } } },
      },
    },
  }, 100)

  assert(vim.deep_equal(descriptors[1].columns, { "Amount" }))
  assert(vim.deep_equal(descriptors[1].column_metadata, {
    {
      name = "Amount",
      type_name = "decimal",
      precision = 12,
      scale = 2,
      nullable = false,
      is_long = false,
    },
  }))
  assert(descriptors[1].duration_ms == 125)
  metadata.dataTypeName = "changed"
  assert(
    descriptors[1].column_metadata[1].type_name == "decimal",
    "Metadata should be normalized at the adapter boundary"
  )
end

T["Result descriptions exclude non-tabular summaries"] = function()
  local descriptors = result_sets.describe({
    ownerUri = "file:///query.sql",
    batchSummaries = {
      {
        hasError = false,
        resultSetSummaries = {
          { rowCount = 1, columnInfo = {} },
          { rowCount = 0 },
        },
      },
    },
  }, 100)

  assert(#descriptors == 0, "Summaries without columns must not create empty result buffers")
end

T["Result renderer preserves models and describes truncation"] = require("tests.helpers").async(function()
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
  assert(rendered.cell_ranges[1][1].start_col == 0)
  assert(rendered.cell_ranges[1][2].start_col == 7)
  assert(rendered.cell_ranges[3][2].start_col == 7)

  local null_highlights = vim
    .iter(rendered.decorations)
    :filter(function(decoration)
      return decoration.highlight == "SqlServerResultNull"
    end)
    :totable()
  assert(#null_highlights == 1, "Only database NULL should receive null highlighting")
end)

return T
