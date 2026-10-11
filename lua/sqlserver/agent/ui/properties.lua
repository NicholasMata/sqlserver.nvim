local inspector = require("sqlserver.agent.inspector")
local status = require("sqlserver.agent.ui.status")

local M = {}

local function value_highlight(mark)
  local value = mark.value:lower()
  if mark.label == "Enabled" then
    return value == "yes" and "SqlServerJobEnabled" or "SqlServerJobDisabled"
  end
  if mark.label == "Execution" then
    if value == "executing" or value == "completing" then
      return "SqlServerJobRunning"
    elseif value == "queued" or value:find("waiting", 1, true) or value == "between_retries" then
      return "SqlServerJobWaiting"
    elseif value == "suspended" then
      return "SqlServerJobSuspended"
    elseif value == "idle" then
      return "SqlServerJobIdle"
    end
  end
  if mark.label == "Last outcome" then
    return status.outcome(value)
  end
end

function M.open(job, data, on_close)
  local pages = inspector.properties(job, data)
  local page_index, entry_index = 1, 1
  local bufnr = vim.api.nvim_create_buf(false, true)
  local width = math.min(100, math.max(20, vim.o.columns - 8))
  local height = math.min(24, math.max(8, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = "Job Properties · " .. job.name,
    title_pos = "center",
    footer = "1–4 sections · h/l switch · [/] entries · q close",
    footer_pos = "center",
  })
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].filetype = "sqlserver-job-properties"
  vim.wo[win].wrap = true
  local namespace = vim.api.nvim_create_namespace("sqlserver-agent-properties")
  vim.api.nvim_set_hl(0, "SqlServerJobPropertyLabel", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "SqlServerJobPropertyHeading", { default = true, link = "Function" })

  local function render()
    local tabs, spans, column = {}, {}, 0
    for index, page in ipairs(pages) do
      local tab = ("%d %s"):format(index, page.label)
      if index > 1 then
        tab = tab .. (" (%d)"):format(#page.entries)
      end
      spans[index] = { column, column + #tab }
      tabs[#tabs + 1] = tab
      column = column + #tab + 3
    end
    local page = pages[page_index]
    local item = page.entries[entry_index]
    local content = { table.concat(tabs, "   "), "" }
    local fields_start
    if item then
      if page_index > 1 then
        content[#content + 1] = item.label .. ("  (%d/%d)"):format(entry_index, #page.entries)
        content[#content + 1] = ""
      end
      fields_start = #content
      vim.list_extend(content, item.lines)
    else
      content[#content + 1] = "No " .. page.label:lower()
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    vim.bo[bufnr].modifiable = false
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    for index, span in ipairs(spans) do
      vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, span[1], {
        end_col = span[2],
        hl_group = index == page_index and "Title" or "Comment",
      })
    end
    if item then
      if page_index > 1 then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, 2, 0, {
          end_col = #content[3],
          hl_group = "SqlServerJobPropertyHeading",
        })
      end
      for _, mark in ipairs(item.marks) do
        local row = fields_start + mark.line
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
          end_col = mark.label_end,
          hl_group = "SqlServerJobPropertyLabel",
        })
        local group = value_highlight(mark)
        if group then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, row, mark.label_end + 1, {
            end_col = #content[row + 1],
            hl_group = group,
          })
        end
      end
    end
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end

  local function select_page(index)
    page_index = math.max(1, math.min(#pages, index))
    entry_index = 1
    render()
  end

  local function select_entry(offset)
    local count = #pages[page_index].entries
    if count > 0 then
      entry_index = (entry_index - 1 + offset) % count + 1
      render()
    end
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  for index = 1, #pages do
    vim.keymap.set("n", tostring(index), function()
      select_page(index)
    end, { buffer = bufnr, silent = true })
  end
  vim.keymap.set("n", "h", function()
    select_page(page_index - 1)
  end, { buffer = bufnr, silent = true })
  vim.keymap.set("n", "l", function()
    select_page(page_index + 1)
  end, { buffer = bufnr, silent = true })
  vim.keymap.set("n", "[", function()
    select_entry(-1)
  end, { buffer = bufnr, silent = true })
  vim.keymap.set("n", "]", function()
    select_entry(1)
  end, { buffer = bufnr, silent = true })
  vim.keymap.set("n", "q", close, { buffer = bufnr, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, silent = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if on_close then
        vim.schedule(on_close)
      end
    end,
  })
  render()
  vim.cmd("stopinsert")
  return win
end

return M
