local M = {}
local namespace = vim.api.nvim_create_namespace("sqlserver-result-sticky-header")
local headers = {}
local floats = {}
local enabled = true

local function is_normal_window(winid)
  return vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative == ""
end

local function close_float(parent)
  local float = floats[parent]
  floats[parent] = nil
  if not float then
    return
  end
  if vim.api.nvim_win_is_valid(float.winid) then
    vim.api.nvim_win_close(float.winid, true)
  end
  if vim.api.nvim_buf_is_valid(float.bufnr) then
    vim.api.nvim_buf_delete(float.bufnr, { force = true })
  end
end

local function close_all()
  for parent in pairs(floats) do
    close_float(parent)
  end
end

local function text_offset(winid)
  local info = vim.fn.getwininfo(winid)[1]
  return info and info.textoff or 0
end

local function first_visible_line(winid)
  return vim.api.nvim_win_call(winid, function()
    return vim.fn.line("w0")
  end)
end

local function horizontal_offset(winid)
  return vim.api.nvim_win_call(winid, function()
    return vim.fn.winsaveview().leftcol
  end)
end

local function create_header_buffer(header)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { header.line })
  for _, decoration in ipairs(header.decorations) do
    local opts = decoration.end_col == -1 and { line_hl_group = decoration.highlight }
      or { end_col = decoration.end_col, hl_group = decoration.highlight }
    vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, decoration.start_col, opts)
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  return bufnr
end

local function update_window(winid)
  if not is_normal_window(winid) then
    return
  end
  local result_buffer = vim.api.nvim_win_get_buf(winid)
  local header = headers[result_buffer]
  if not (enabled and header and first_visible_line(winid) > 1 and vim.api.nvim_win_get_height(winid) > 1) then
    close_float(winid)
    return
  end

  local offset = text_offset(winid)
  local width = math.max(1, vim.api.nvim_win_get_width(winid) - offset)
  local float = floats[winid]
  if float and float.result_buffer ~= result_buffer then
    close_float(winid)
    float = nil
  end
  if not (float and vim.api.nvim_win_is_valid(float.winid)) then
    local header_buffer = create_header_buffer(header)
    local float_window = vim.api.nvim_open_win(header_buffer, false, {
      relative = "win",
      win = winid,
      row = 0,
      col = offset,
      width = width,
      height = 1,
      focusable = false,
      mouse = false,
      style = "minimal",
      zindex = 20,
    })
    float = { winid = float_window, bufnr = header_buffer, result_buffer = result_buffer }
    floats[winid] = float
    vim.api.nvim_set_option_value("wrap", false, { win = float.winid })
    vim.api.nvim_set_option_value("winhighlight", "Normal:Normal,NormalNC:Normal", { win = float.winid })
  else
    vim.api.nvim_win_set_config(float.winid, {
      relative = "win",
      win = winid,
      row = 0,
      col = offset,
      width = width,
      height = 1,
    })
  end

  local leftcol = horizontal_offset(winid)
  vim.api.nvim_win_call(float.winid, function()
    vim.fn.winrestview({ topline = 1, leftcol = leftcol })
  end)
end

function M.refresh()
  local active_parents = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if is_normal_window(winid) then
      active_parents[winid] = true
      update_window(winid)
    end
  end
  for parent in pairs(floats) do
    if not active_parents[parent] then
      close_float(parent)
    end
  end
end

function M.attach(bufnr, line, decorations)
  headers[bufnr] = { line = line, decorations = decorations or {} }
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      headers[bufnr] = nil
      M.refresh()
    end,
  })
end

function M.setup(opts)
  enabled = opts == nil or opts.enabled ~= false
  close_all()
  local group = vim.api.nvim_create_augroup("SqlServerResultStickyHeader", { clear = true })
  if not enabled then
    return
  end
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinScrolled", "WinResized" }, {
    group = group,
    callback = function()
      vim.schedule(M.refresh)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      close_float(tonumber(args.match))
    end,
  })
end

function M.get_window(parent)
  local float = floats[parent]
  return float and vim.api.nvim_win_is_valid(float.winid) and float.winid or nil
end

return M
