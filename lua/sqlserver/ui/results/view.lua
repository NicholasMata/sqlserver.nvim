local renderer = require("sqlserver.ui.results.renderer")

local M = {}
local namespace = vim.api.nvim_create_namespace("sqlserver-results")
local result_buffers = {}
local sessions = {}

local highlight_links = {
  SqlServerResultHeader = "Title",
  SqlServerResultBorder = "NonText",
  SqlServerResultNull = "Comment",
  SqlServerResultTruncated = "DiagnosticWarn",
}

local function define_highlights()
  for group, link in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = link })
  end
end

function M.clear()
  for _, bufnr in ipairs(result_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and sessions[bufnr] then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    sessions[bufnr] = nil
  end
  result_buffers = {}
end

local function select_relative(offset)
  local session = sessions[vim.api.nvim_get_current_buf()]
  if not (session and #session.buffers > 1) then
    return false
  end
  local index = ((session.index - 1 + offset) % #session.buffers) + 1
  local bufnr = session.buffers[index]
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  vim.api.nvim_win_set_buf(0, bufnr)
  return true
end

function M.next_result()
  return select_relative(1)
end

function M.previous_result()
  return select_relative(-1)
end

---@param result_sets SqlServerResultSet[]
---@param opts table
function M.show(result_sets, opts)
  M.clear()
  if not result_sets or #result_sets == 0 then
    return false
  end
  define_highlights()
  local buffers = {}

  for index, result_set in ipairs(result_sets) do
    local rendered = renderer.render(result_set, { max_cell_width = opts.results.max_cell_width })
    local bufnr = vim.api.nvim_create_buf(false, false)
    local suffix = (#result_sets > 1 or result_set.ordinal > 1) and (" " .. result_set.ordinal) or ""
    vim.api.nvim_buf_set_name(bufnr, "results" .. suffix .. ".sqlresult")
    vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
    vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, rendered.lines)
    for _, decoration in ipairs(rendered.decorations) do
      local extmark = decoration.end_col == -1 and { line_hl_group = decoration.highlight }
        or { end_col = decoration.end_col, hl_group = decoration.highlight }
      vim.api.nvim_buf_set_extmark(bufnr, namespace, decoration.line, decoration.start_col, extmark)
    end
    vim.b[bufnr].query_result_info = { subset_params = result_set.locator }
    vim.api.nvim_set_option_value("filetype", "sqlserver-result", { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", true, { buf = bufnr })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    table.insert(buffers, bufnr)
  end

  for index, bufnr in ipairs(buffers) do
    sessions[bufnr] = { buffers = buffers, index = index, result_set = result_sets[index] }
  end
  result_buffers = buffers
  opts.open_results_in(buffers[1])
  return true
end

return M
