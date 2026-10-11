local M = {}

function M.outcome(value)
  value = tostring(value):lower()
  if value == "succeeded" then
    return "DiagnosticOk"
  elseif value == "failed" then
    return "DiagnosticError"
  elseif value == "canceled" or value == "cancelled" then
    return "DiagnosticWarn"
  end
end

return M
