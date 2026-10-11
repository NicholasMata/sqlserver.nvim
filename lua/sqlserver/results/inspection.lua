local M = {}

function M.create(cell, column, format)
  if format ~= nil and format ~= "text" and format ~= "xml" and format ~= "json" then
    error({ code = "invalid_argument", message = "Inspection format must be text, xml, or json" }, 0)
  end
  column = column or {}
  local value = cell.display_value
  local status = cell.is_null and "SQL NULL" or (value == "" and "Empty string" or "Complete available representation")
  local notice = cell.is_null and "SQL NULL" or (value == "" and "Empty string" or nil)
  local complete = (cell.completeness or "complete") == "complete"
  if not complete then
    notice = cell.completeness == "possibly_truncated" and "Possibly truncated" or "Complete value unavailable"
    if cell.limit then
      notice = notice .. " · service limit " .. cell.limit
    end
    status = "Complete value unavailable: " .. (cell.completeness or "unknown")
    if cell.limit then
      status = status .. " (service storage limit " .. cell.limit .. ")"
    end
  end
  local filetype = "text"
  if not cell.is_null and value ~= "" then
    local kind = (column.type_name or ""):lower()
    if format then
      filetype = format
    elseif kind == "xml" or column.is_xml then
      filetype = "xml"
    elseif kind == "json" or column.is_json then
      filetype = "json"
    elseif #value <= 1024 * 1024 and value:match("^%s*[%[{]") and pcall(vim.json.decode, value) then
      filetype = "json"
    end
  end
  if filetype == "json" and #value > 1024 * 1024 then
    status = status .. "; JSON validation skipped above 1 MiB"
    notice = notice or "JSON validation skipped (>1 MiB)"
  elseif filetype == "json" and not pcall(vim.json.decode, value) then
    status = status .. "; invalid JSON, showing raw content"
    notice = notice or "Invalid JSON · raw value"
  elseif filetype == "xml" then
    status = status .. "; XML validation delegated to configured tools"
  end
  return {
    original = value,
    is_null = cell.is_null,
    complete = complete,
    filetype = filetype,
    status = status,
    notice = notice,
  }
end

function M.copy(snapshot, register)
  if snapshot.is_null then
    return false, "SQL NULL has no textual original value"
  end
  if not snapshot.complete then
    return false, "The complete original value is unavailable"
  end
  vim.fn.setreg(register or '"', snapshot.original, "v")
  return true
end

return M
