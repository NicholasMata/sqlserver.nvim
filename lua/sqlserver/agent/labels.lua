-- Presentation names follow SQL Server Management Studio's Agent dialogs.
local M = {}

local alert_types = {
  sql_server_event = "SQL Server event alert",
  performance_condition = "SQL Server performance condition alert",
  non_sql_server_event = "Non-SQL Server event alert",
  wmi_event = "WMI event alert",
}

local severities = {
  [10] = "Status Information",
  [11] = "Specified Database Object Not Found",
  [13] = "Transaction Deadlock",
  [14] = "Insufficient Permission",
  [15] = "Syntax Error in SQL Statement",
  [16] = "Miscellaneous User Error",
  [17] = "Insufficient Resources",
  [18] = "Nonfatal Internal Error Detected",
  [19] = "SQL Server Error in Resource",
  [20] = "SQL Server Fatal Error in Current Process",
  [21] = "SQL Server Fatal Error in Database (dbid) Process",
  [22] = "SQL Server Fatal Error Table Integrity Suspect",
  [23] = "SQL Server Fatal Error Database Integrity Suspect",
  [24] = "Hardware Error",
  [25] = "Fatal Error",
}

function M.alert_type(value)
  return alert_types[value] or value
end

function M.severity(value)
  if value == nil or value == 0 then
    return nil
  end
  local description = severities[value]
  if value >= 1 and value <= 9 then
    description = "Miscellaneous System Information"
  end
  return description and ("%03d - %s"):format(value, description) or tostring(value)
end

function M.notification_methods(values)
  if values == nil then
    return nil
  end
  local names = { email = "E-mail", pager = "Pager", net_send = "Net send" }
  local result = {}
  for _, value in ipairs(values) do
    result[#result + 1] = names[value] or value
  end
  return #result > 0 and table.concat(result, ", ") or "None"
end

return M
