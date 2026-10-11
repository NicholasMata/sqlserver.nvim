local M = {}

---@class SqlServerPlan
---@field xml string Original, unformatted Showplan XML
---@field kind "estimated"|"actual"
---@field ordinal integer
---@field batch_index integer Zero-based batch identity within this execution
---@field result_index integer Zero-based service result identity
---@field source_bufnr? integer
---@field execution_id? integer
---@field connection? table Connection context without credentials
---@field batch_range? table Executed batch range, not a per-statement range

function M.validate(plan)
  if type(plan) ~= "table" or type(plan.xml) ~= "string" or plan.xml == "" then
    error({ code = "invalid_plan", message = "An execution-plan snapshot with XML is required" }, 0)
  end
  if not plan.xml:find("<ShowPlanXML[%s>]") or not plan.xml:find("</ShowPlanXML>%s*$") then
    error({ code = "invalid_plan", message = "SQL Tools Service returned invalid Showplan XML" }, 0)
  end
  return plan
end

function M.title(plan)
  local context = plan.connection or {}
  return string.format(
    "%s plan %d · batch %d · %s/%s · execution %s",
    plan.kind == "estimated" and "Estimated" or "Actual",
    plan.ordinal or 1,
    (plan.batch_index or 0) + 1,
    context.server or "?",
    context.database or "?",
    tostring(plan.execution_id or "?")
  )
end

return M
