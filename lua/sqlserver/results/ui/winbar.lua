local M = {}

local function format_duration(duration_ms)
  if duration_ms < 1000 then
    return ("%d ms"):format(math.floor(duration_ms + 0.5))
  end
  if duration_ms < 60000 then
    local precision = duration_ms < 10000 and 2 or 1
    local seconds = ("%." .. precision .. "f"):format(duration_ms / 1000):gsub("0+$", ""):gsub("%.$", "")
    return seconds .. " s"
  end
  if duration_ms < 3600000 then
    return ("%dm %ds"):format(math.floor(duration_ms / 60000), math.floor(duration_ms % 60000 / 1000))
  end
  return ("%dh %dm"):format(math.floor(duration_ms / 3600000), math.floor(duration_ms % 3600000 / 60000))
end

local function format_row_count(count)
  return tostring(count):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

---@param info { source_name: string, execution: integer, execution_count: integer, result: integer, result_count: integer, displayed_rows: integer, total_rows: integer, duration_ms?: number }
---@return string
function M.render(info)
  local source_name = info.source_name:gsub("%%", "%%%%")
  local row_label = info.total_rows == 1 and "row" or "rows"
  local metadata
  if info.displayed_rows < info.total_rows then
    metadata = ("%s of %s %s"):format(
      format_row_count(info.displayed_rows),
      format_row_count(info.total_rows),
      row_label
    )
  else
    metadata = ("%s %s"):format(format_row_count(info.total_rows), row_label)
  end
  if info.duration_ms then
    metadata = metadata .. "  " .. format_duration(info.duration_ms)
  end
  local position = ("Execution %d/%d  Result %d/%d"):format(
    info.execution,
    info.execution_count,
    info.result,
    info.result_count
  )
  return ("%s  %s%%=%s "):format(source_name, metadata, position)
end

return M
