local clipboard = require("sqlserver.platform.clipboard")

local T = MiniTest.new_set()

T["Windows HTML clipboard payload should contain valid byte offsets"] = function()
  local fragment = "<table><tr><td>😀</td></tr></table>"
  local payload = clipboard.cf_html(fragment)
  local start_html = tonumber(payload:match("StartHTML:(%d+)"))
  local end_html = tonumber(payload:match("EndHTML:(%d+)"))
  local start_fragment = tonumber(payload:match("StartFragment:(%d+)"))
  local end_fragment = tonumber(payload:match("EndFragment:(%d+)"))

  assert(payload:sub(start_html + 1, start_html + 6) == "<html>")
  assert(end_html == #payload)
  assert(payload:sub(start_fragment + 1, end_fragment) == fragment)
end

return T
