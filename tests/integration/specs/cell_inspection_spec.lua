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
return T
