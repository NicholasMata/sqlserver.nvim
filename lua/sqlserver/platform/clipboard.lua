local M = {}

local start_marker = "<!--StartFragment-->"
local end_marker = "<!--EndFragment-->"

---@param fragment string
---@return string
function M.cf_html(fragment)
  local html = "<html><body>" .. start_marker .. fragment .. end_marker .. "</body></html>"
  local header_template = table.concat({
    "Version:0.9",
    "StartHTML:%010d",
    "EndHTML:%010d",
    "StartFragment:%010d",
    "EndFragment:%010d",
    "",
  }, "\r\n")
  local empty_header = header_template:format(0, 0, 0, 0)
  local _, start_end = html:find(start_marker, 1, true)
  local end_start = assert(html:find(end_marker, 1, true))
  local start_html = #empty_header
  local end_html = start_html + #html
  local start_fragment = start_html + start_end
  local end_fragment = start_html + end_start - 1
  return header_template:format(start_html, end_html, start_fragment, end_fragment) .. html
end

local function provider(system_name)
  if system_name == "Darwin" then
    local script = table.concat({
      "on run argv",
      "set htmlContent to item 1 of argv",
      "set the clipboard to {«class HTML»:htmlContent}",
      "end run",
    }, "\n")
    return { command = { "osascript", "-e", script }, argument = true }
  end
  if system_name == "Windows_NT" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$html = [Console]::In.ReadToEnd();",
      "[System.Windows.Forms.Clipboard]::SetText($html, [System.Windows.Forms.TextDataFormat]::Html)",
    }, " ")
    return { command = { "powershell.exe", "-NoProfile", "-STA", "-Command", script }, cf_html = true }
  end
  if vim.fn.executable("wl-copy") == 1 then
    return { command = { "wl-copy", "--type", "text/html" } }
  end
  if vim.fn.executable("xclip") == 1 then
    return { command = { "xclip", "-selection", "clipboard", "-t", "text/html" } }
  end
end

---@param html string
---@return boolean
---@return string? error
function M.copy_html(html)
  local selected = provider(vim.uv.os_uname().sysname)
  if not selected then
    return false, "Rich HTML clipboard support requires wl-copy or xclip on Linux"
  end
  local contents = selected.cf_html and M.cf_html(html) or html
  local command = vim.deepcopy(selected.command)
  local opts = { text = true }
  if selected.argument then
    command[#command + 1] = contents
  else
    opts.stdin = contents
  end
  local result = vim.system(command, opts):wait()
  if result.code ~= 0 then
    local detail = result.stderr and vim.trim(result.stderr) or ""
    return false, detail ~= "" and detail or "The system clipboard command failed"
  end
  return true
end

return M
