local M = {}

local function escape(value)
  return tostring(value or "")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
    :gsub("'", "&#39;")
    :gsub("\r\n", "\n")
    :gsub("\r", "\n")
    :gsub("\n", "<br>")
end

---@param result_set SqlServerResultSet
---@param selection SqlServerResultSelection
---@return string
function M.render(result_set, selection)
  local lines = {
    "<table>",
    "<thead><tr>",
  }
  for column = selection.column_start + 1, selection.column_end + 1 do
    lines[#lines + 1] = "<th>" .. escape(result_set.columns[column]) .. "</th>"
  end
  lines[#lines + 1] = "</tr></thead>"
  lines[#lines + 1] = "<tbody>"
  for row = selection.row_start + 1, selection.row_end + 1 do
    lines[#lines + 1] = "<tr>"
    for column = selection.column_start + 1, selection.column_end + 1 do
      local cell = result_set.rows[row][column]
      lines[#lines + 1] = "<td>" .. escape(cell and cell.display_value or "") .. "</td>"
    end
    lines[#lines + 1] = "</tr>"
  end
  lines[#lines + 1] = "</tbody>"
  lines[#lines + 1] = "</table>"
  return table.concat(lines, "")
end

return M
