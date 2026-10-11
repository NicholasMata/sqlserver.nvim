local sqlserver = require("sqlserver")
local integration = require("tests.helpers.integration")
local view = require("sqlserver.results.ui.view")
local T = MiniTest.new_set()

T["Cell inspection retains complete values and exposes pinned service limits"] = require("tests.helpers").async(
  function()
    local source = vim.api.nvim_get_current_buf()
    -- Query-local fixtures leave no database objects behind.
    local query = [[SELECT
    CAST(N'<root><name>Grüße 😀</name></root>' AS XML) AS NativeXml,
    N'<root>text</root>' AS XmlText,
    N'{"name":"Grüße 😀","items":[1,null]}' AS JsonText,
    CAST(NULL AS nvarchar(max)) AS NullValue,
    N'' AS EmptyValue,
    N'line one' + NCHAR(10) + N'line two 😀' AS Multiline,
    REPLICATE(CAST(N'x' AS nvarchar(max)), 60000) + N'END' AS LargeValue,
    REPLICATE(CAST(N'x' AS nvarchar(max)), 70000) + N'END' AS BeyondStorage,
    N'{bad json}' AS Malformed,
    0x00FF AS BinaryValue,
    CAST(42 AS int) AS NumberValue,
    CAST('2026-10-10' AS date) AS DateValue,
    CAST(1 AS bit) AS BooleanValue,
    CAST(N'<root>' + REPLICATE(CAST(N'x' AS nvarchar(max)), 70000) + N'</root>' AS XML) AS LargeXml,
    CAST(N'<root>' + REPLICATE(CAST(N'x' AS nvarchar(max)), 2097200) + N'</root>' AS XML) AS LimitedXml;]]
    local result = integration.await(function(callback)
      sqlserver.execute({ scope = "buffer", text = query, bufnr = source }, callback)
    end)
    local cells = result.result_sets[1].rows[1]
    assert(cells[7].display_value == string.rep("x", 60000) .. "END")
    assert(#cells[8].display_value == 65535, "Pinned service storage limit changed")
    assert(cells[8].completeness == "possibly_truncated")
    assert(cells[7].completeness == "complete")
    assert(cells[14].display_value == "<root>" .. string.rep("x", 70000) .. "</root>")
    assert(cells[14].completeness == "complete")
    assert(
      #cells[15].display_value == 2097153 and cells[15].completeness == "possibly_truncated",
      vim.inspect({
        length = #cells[15].display_value,
        status = cells[15].completeness,
        column = result.result_sets[1].column_metadata[15],
      })
    )
    view.show(result.result_sets, {
      results = { max_cell_width = 10, history_limit = 2 },
      open_results_in = function(buf)
        vim.api.nvim_set_current_buf(buf)
      end,
    }, source)
    local result_buf = vim.api.nvim_get_current_buf()
    local expected =
      { "xml", "xml", "json", "text", "text", "text", "text", "text", "json", "text", "text", "text", "text" }
    expected[14], expected[15] = "xml", "xml"
    for column = 1, #cells do
      local opened = integration.await(function(callback)
        sqlserver.inspect_cell({
          bufnr = result_buf,
          row = 1,
          column = column,
          format = (column == 2 and "xml") or (column == 9 and "json") or nil,
        }, callback)
      end)
      assert(vim.bo[opened.bufnr].filetype == expected[column])
      assert(not vim.bo[opened.bufnr].modifiable and not vim.wo[opened.winid].spell)
      if column == 8 or column == 15 then
        assert(opened.status:find("unavailable", 1, true))
      elseif column == 4 then
        assert(opened.status == "SQL NULL")
      elseif column == 5 then
        assert(opened.status == "Empty string")
      else
        assert(
          require("sqlserver.results.inspection").copy(
            require("sqlserver.results.inspection").create(cells[column]),
            "a"
          )
        )
        assert(vim.fn.getreg("a") == cells[column].display_value)
      end
      require("sqlserver.results.ui.inspection").perform("close")
    end
    integration.await(function(callback)
      sqlserver.execute({ scope = "buffer", text = "SELECT 2", bufnr = source }, callback)
    end)
    integration.await(function(callback)
      sqlserver.disconnect(source, callback)
    end)
    -- No service request or stale locator is necessary for a retained snapshot.
    local opened = view.inspect_cell({ bufnr = result_buf, row = 1, column = 7 })
    vim.cmd('normal! ggVG"ay')
    assert(vim.fn.getreg("a") == string.rep("x", 60000) .. "END\n")
    require("sqlserver.results.ui.inspection").perform("close")
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_buf_delete(result_buf, { force = true })
    assert(not vim.api.nvim_buf_is_valid(opened.bufnr))
  end
)
T["Cell inspection handles concatenated FOR documents and mixed JSON text rows"] = require("tests.helpers").async(
  function()
    local source = vim.api.nvim_get_current_buf()
    local result = integration.await(function(callback)
      sqlserver.execute({
        scope = "buffer",
        bufnr = source,
        text = [[
SELECT REPLICATE(CAST(N'x' AS nvarchar(max)), 70000) AS payload FOR JSON PATH;
SELECT REPLICATE(CAST(N'x' AS nvarchar(max)), 2200000) AS payload FOR XML PATH('row');
SELECT REPLICATE(CAST(N'x' AS nvarchar(max)), 2200000) AS payload FOR XML PATH('row'), TYPE;
SELECT payload FROM (VALUES
  (1, N'{"x":1}'), (2, N'ordinary text'), (3, N'null'),
  (4, N'42'), (5, N'true'), (6, N'"text"'), (7, N'[1,null]')
) AS mixed(ordinal, payload) ORDER BY ordinal;
]],
      }, callback)
    end)
    local sets = result.result_sets
    assert(#sets == 4)
    local json = '[{"payload":"' .. string.rep("x", 70000) .. '"}]'
    local xml = "<row><payload>" .. string.rep("x", 2200000) .. "</payload></row>"
    for index, expected in ipairs({ json, xml }) do
      local value = sets[index].rows[1][1]
      assert(value.display_value == expected, "FOR document must retain every chunk")
      assert(value.completeness == "complete", vim.inspect(sets[index].column_metadata))
      local snapshot = require("sqlserver.results.inspection").create(value, sets[index].column_metadata[1])
      assert(snapshot.complete and snapshot.filetype == (index == 1 and "json" or "xml"))
      assert(require("sqlserver.results.inspection").copy(snapshot, "a"))
      assert(vim.fn.getreg("a") == expected)
    end
    local typed = sets[3].rows[1][1]
    assert(typed.completeness == "possibly_truncated", "FOR XML TYPE remains a bounded scalar XML value")
    assert(not require("sqlserver.results.inspection").copy(require("sqlserver.results.inspection").create(typed), "a"))
    local mixed = sets[4]
    assert(mixed.column_metadata[1].is_json, "Pinned service should infer the column hint from row one")
    for index, row in ipairs(mixed.rows) do
      local snapshot = require("sqlserver.results.inspection").create(row[1], mixed.column_metadata[1])
      assert(snapshot.filetype == ((index == 1 or index == 7) and "json" or "text"))
      assert(not snapshot.status:find("invalid JSON", 1, true))
    end
    local group = vim.api.nvim_create_augroup("test-aggregate-json-format", { clear = true })
    _G.sqlserver_test_aggregate_format = function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[", '  {"payload":"' .. string.rep("x", 70000) .. '"}', "]" })
      return 0
    end
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "json",
      callback = function()
        vim.bo.formatexpr = "v:lua.sqlserver_test_aggregate_format()"
      end,
    })
    local formatted, format_error = pcall(function()
      view.show(sets, {
        results = { max_cell_width = 10, history_limit = 2 },
        open_results_in = function(buf)
          vim.api.nvim_set_current_buf(buf)
        end,
      }, source)
      local opened = view.inspect_cell({ row = 1, column = 1 })
      assert(vim.api.nvim_buf_line_count(opened.bufnr) == 3, "Complete aggregate JSON should reach the formatter")
      require("sqlserver.results.ui.inspection").perform("format")
      assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == json)
      require("sqlserver.results.ui.inspection").perform("close")
    end)
    _G.sqlserver_test_aggregate_format = nil
    vim.api.nvim_del_augroup_by_id(group)
    view.clear(source)
    vim.api.nvim_set_current_buf(source)
    assert(formatted, format_error)
  end
)

T["Cell inspection keeps FOR JSON identity above the validation limit"] = require("tests.helpers").async(function()
  local source = vim.api.nvim_get_current_buf()
  local result = integration.await(function(callback)
    sqlserver.execute({
      scope = "buffer",
      bufnr = source,
      text = "SELECT REPLICATE(CAST(N'x' AS nvarchar(max)), 1100000) AS payload FOR JSON PATH;",
    }, callback)
  end)
  local set = result.result_sets[1]
  local value = set.rows[1][1]
  local expected = '[{"payload":"' .. string.rep("x", 1100000) .. '"}]'
  assert(value.display_value == expected and value.completeness == "complete")
  assert(set.column_metadata[1].aggregate_format == "json")
  local snapshot = require("sqlserver.results.inspection").create(value, set.column_metadata[1])
  assert(snapshot.filetype == "json" and snapshot.notice:find("validation skipped", 1, true))
  assert(require("sqlserver.results.inspection").copy(snapshot, "a") and vim.fn.getreg("a") == expected)
  local calls = 0
  _G.sqlserver_test_large_json_format = function()
    calls = calls + 1
    return 0
  end
  local group = vim.api.nvim_create_augroup("test-large-json-format", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "json",
    callback = function()
      vim.bo.formatexpr = "v:lua.sqlserver_test_large_json_format()"
    end,
  })
  local ok, err = pcall(function()
    view.show(result.result_sets, {
      results = { max_cell_width = 10, history_limit = 2 },
      open_results_in = function(buf)
        vim.api.nvim_set_current_buf(buf)
      end,
    }, source)
    local opened = view.inspect_cell({ row = 1, column = 1 })
    assert(vim.bo[opened.bufnr].filetype == "json")
    assert(opened.status:find("JSON validation skipped", 1, true))
    assert(opened.status:find("formatting skipped", 1, true))
    assert(vim.wo[opened.winid].winbar:find("validation skipped", 1, true))
    assert(calls == 0, "Large JSON should retain its filetype without invoking a formatter")
    assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == expected)
    require("sqlserver.results.ui.inspection").perform("close")
  end)
  _G.sqlserver_test_large_json_format = nil
  vim.api.nvim_del_augroup_by_id(group)
  view.clear(source)
  vim.api.nvim_set_current_buf(source)
  assert(ok, err)
end)

return T
