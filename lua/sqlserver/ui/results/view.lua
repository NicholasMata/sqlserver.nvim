local renderer = require("sqlserver.ui.results.renderer")
local sticky_header = require("sqlserver.ui.results.sticky_header")

local M = {}
local namespace = vim.api.nvim_create_namespace("sqlserver-results")
local sources = {}
local result_sessions = {}
local next_execution_id = 1
local last_source_buffer

local highlight_links = {
  SqlServerResultHeader = "Title",
  SqlServerResultBorder = "NonText",
  SqlServerResultNull = "Comment",
  SqlServerResultTruncated = "DiagnosticWarn",
  SqlServerResultPosition = "Comment",
}

local function define_highlights()
  for group, link in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, group, { default = true, link = link })
  end
end

function M.setup(opts)
  define_highlights()
  sticky_header.setup({ enabled = opts == nil or opts.sticky_header ~= false })
  local group = vim.api.nvim_create_augroup("SqlServerResultHighlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlights })
end

local function delete_execution(execution)
  for _, bufnr in ipairs(execution.buffers) do
    result_sessions[bufnr] = nil
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
end

local function clear_source(source_bufnr)
  local source = sources[source_bufnr]
  if not source then
    return
  end
  sources[source_bufnr] = nil
  if last_source_buffer == source_bufnr then
    last_source_buffer = nil
  end
  for _, execution in ipairs(source.executions) do
    delete_execution(execution)
  end
end

function M.clear(source_bufnr)
  if source_bufnr then
    clear_source(source_bufnr)
    return
  end
  for _, bufnr in ipairs(vim.tbl_keys(sources)) do
    clear_source(bufnr)
  end
end

local function source_for_buffer(bufnr, use_last_source)
  local result = result_sessions[bufnr]
  if result then
    return result.source_bufnr
  end
  if sources[bufnr] then
    return bufnr
  end
  return use_last_source and last_source_buffer or nil
end

local function valid_buffer(execution)
  local preferred = execution.buffers[execution.active_result]
  if preferred and vim.api.nvim_buf_is_valid(preferred) then
    return preferred
  end
  for index, bufnr in ipairs(execution.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      execution.active_result = index
      return bufnr
    end
  end
end

local function prune_source(source)
  local active = source.executions[source.active_execution]
  for index = #source.executions, 1, -1 do
    if not valid_buffer(source.executions[index]) then
      table.remove(source.executions, index)
    end
  end
  source.active_execution = #source.executions
  for index, execution in ipairs(source.executions) do
    if execution == active then
      source.active_execution = index
      break
    end
  end
end

local function active_execution(source)
  prune_source(source)
  local execution = source.executions[source.active_execution]
  if execution and valid_buffer(execution) then
    return execution
  end
  for index = #source.executions, 1, -1 do
    execution = source.executions[index]
    if valid_buffer(execution) then
      source.active_execution = index
      return execution
    end
  end
end

local function execution_index(source, target)
  for index, execution in ipairs(source.executions) do
    if execution == target then
      return index
    end
  end
end

local function result_position(execution, target_index)
  local position
  local count = 0
  for index, bufnr in ipairs(execution.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      count = count + 1
      if index == target_index then
        position = count
      end
    end
  end
  return position, count
end

function M.is_result_buffer(bufnr)
  return result_sessions[bufnr or vim.api.nvim_get_current_buf()] ~= nil
end

function M.render_winbar(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = result_sessions[bufnr]
  if not session then
    return ""
  end
  local source = sources[session.source_bufnr]
  if not source then
    return ""
  end
  prune_source(source)
  local run = execution_index(source, session.execution)
  local result, result_count = result_position(session.execution, session.result_index)
  if not (run and result) then
    return ""
  end
  local source_name = vim.api.nvim_buf_get_name(session.source_bufnr)
  source_name = source_name ~= "" and vim.fn.fnamemodify(source_name, ":t") or "[No Name]"
  source_name = source_name:gsub("%%", "%%%%")
  local position = ("Run %d/%d  Result %d/%d"):format(run, #source.executions, result, result_count)
  return ("%s%%=%%#SqlServerResultPosition#%s%%* "):format(source_name, position)
end

function M.winbar()
  return M.render_winbar()
end

function M.has_results(bufnr)
  local use_last_source = bufnr == nil
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local source = sources[source_for_buffer(bufnr, use_last_source)]
  return source ~= nil and active_execution(source) ~= nil
end

local function result_window(source)
  for _, execution in ipairs(source.executions) do
    for _, bufnr in ipairs(execution.buffers) do
      local windows = vim.api.nvim_buf_is_valid(bufnr) and vim.fn.win_findbuf(bufnr) or {}
      if #windows > 0 then
        return windows[1]
      end
    end
  end
end

local function display_buffer(source, bufnr, open_results_in)
  local windows = vim.fn.win_findbuf(bufnr)
  local existing_window = result_window(source)
  if #windows > 0 then
    vim.api.nvim_set_current_win(windows[1])
  elseif existing_window then
    vim.api.nvim_win_set_buf(existing_window, bufnr)
    vim.api.nvim_set_current_win(existing_window)
  else
    open_results_in(bufnr)
  end
end

function M.show_results(open_results_in, bufnr)
  local use_last_source = bufnr == nil
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local source = sources[source_for_buffer(bufnr, use_last_source)]
  local execution = source and active_execution(source) or nil
  local result_buffer = execution and valid_buffer(execution) or nil
  if not result_buffer then
    return false
  end
  last_source_buffer = source.bufnr
  display_buffer(source, result_buffer, open_results_in)
  return true
end

local function select_result(offset)
  local session = result_sessions[vim.api.nvim_get_current_buf()]
  if not session then
    return false
  end
  local buffers = session.execution.buffers
  local indices = {}
  local current_index
  for index, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      table.insert(indices, index)
      if index == session.result_index then
        current_index = #indices
      end
    end
  end
  if #indices < 2 or not current_index then
    return false
  end
  local index = indices[((current_index - 1 + offset) % #indices) + 1]
  local bufnr = buffers[index]
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  session.execution.active_result = index
  vim.api.nvim_win_set_buf(0, bufnr)
  return true
end

function M.next_result()
  return select_result(1)
end

function M.previous_result()
  return select_result(-1)
end

local function select_execution(offset, open_results_in)
  local current_buffer = vim.api.nvim_get_current_buf()
  local source_bufnr = source_for_buffer(current_buffer, true)
  local source = sources[source_bufnr]
  if not source then
    return false
  end
  prune_source(source)
  if #source.executions < 2 then
    return false
  end
  local index = ((source.active_execution - 1 + offset) % #source.executions) + 1
  local execution = source.executions[index]
  local bufnr = valid_buffer(execution)
  if not bufnr then
    return false
  end
  source.active_execution = index
  last_source_buffer = source_bufnr
  if result_sessions[current_buffer] then
    vim.api.nvim_win_set_buf(0, bufnr)
    return true
  end
  display_buffer(source, bufnr, open_results_in)
  return true
end

function M.next_execution(open_results_in)
  return select_execution(1, open_results_in)
end

function M.previous_execution(open_results_in)
  return select_execution(-1, open_results_in)
end

local function ensure_source(source_bufnr)
  local source = sources[source_bufnr]
  if source then
    return source
  end
  source = { bufnr = source_bufnr, executions = {}, active_execution = 0 }
  sources[source_bufnr] = source
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = source_bufnr,
    once = true,
    callback = function()
      clear_source(source_bufnr)
    end,
  })
  return source
end

local function result_buffer_name(execution_id, ordinal, include_ordinal)
  local suffix = include_ordinal and (" " .. ordinal) or ""
  return ("sqlserver-results://execution/%d/results%s.sqlresult"):format(execution_id, suffix)
end

---@param result_sets SqlServerResultSet[]
---@param opts table
---@param source_bufnr? integer
function M.show(result_sets, opts, source_bufnr)
  if not result_sets or #result_sets == 0 then
    return false
  end
  source_bufnr = source_bufnr or vim.api.nvim_get_current_buf()
  assert(vim.api.nvim_buf_is_valid(source_bufnr), "Result source buffer is no longer valid")
  define_highlights()

  local source = ensure_source(source_bufnr)
  local execution = {
    id = next_execution_id,
    source_bufnr = source_bufnr,
    buffers = {},
    active_result = 1,
  }
  next_execution_id = next_execution_id + 1

  for index, result_set in ipairs(result_sets) do
    local rendered = renderer.render(result_set, { max_cell_width = opts.results.max_cell_width })
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(
      bufnr,
      result_buffer_name(execution.id, result_set.ordinal, #result_sets > 1 or result_set.ordinal > 1)
    )
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
    sticky_header.attach(
      bufnr,
      rendered.lines[1] or "",
      vim.tbl_filter(function(decoration)
        return decoration.line == 0
      end, rendered.decorations)
    )
    vim.b[bufnr].query_result_info = {
      subset_params = result_set.locator,
      source_bufnr = source_bufnr,
      execution_id = execution.id,
      result_ordinal = result_set.ordinal,
    }
    vim.api.nvim_set_option_value("filetype", "sqlserver-result", { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", true, { buf = bufnr })
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    result_sessions[bufnr] = { source_bufnr = source_bufnr, execution = execution, result_index = index }
    vim.api.nvim_create_autocmd("BufEnter", {
      buffer = bufnr,
      callback = function()
        local current_source = sources[source_bufnr]
        local current_session = result_sessions[bufnr]
        if not (current_source and current_session) then
          return
        end
        current_source.active_execution = execution_index(current_source, current_session.execution)
          or current_source.active_execution
        current_session.execution.active_result = current_session.result_index
        last_source_buffer = source_bufnr
      end,
    })
    table.insert(execution.buffers, bufnr)
  end

  table.insert(source.executions, execution)
  source.active_execution = #source.executions
  last_source_buffer = source_bufnr

  local history_limit = opts.results.history_limit or 10
  while #source.executions > history_limit do
    delete_execution(table.remove(source.executions, 1))
    source.active_execution = source.active_execution - 1
  end

  display_buffer(source, execution.buffers[1], opts.open_results_in)
  return true
end

return M
