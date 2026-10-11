local generated_buffer = require("sqlserver.ui.generated_buffer")
local M = {}
local next_id = 0
local expressions = {}
local inspectors = {}
local configured_prefix

function M.which_key_items(bufnr)
  local state = inspectors[bufnr or vim.api.nvim_get_current_buf()]
  return state and state.items() or {}
end

function M.perform(action)
  local state = inspectors[vim.api.nvim_get_current_buf()]
  if not state or not state.actions[action] then
    vim.notify("This action is unavailable in the current cell view", vim.log.levels.WARN)
    return
  end
  return state.actions[action]()
end

function M.setup_keymaps(prefix)
  configured_prefix = prefix
  for _, state in pairs(inspectors) do
    state.attach()
  end
end

-- Capture formatexpr failure before gq's text-wrapping fallback runs.
function M.formatexpr()
  local state = expressions[vim.api.nvim_get_current_buf()]
  local ok, result = pcall(vim.fn.eval, state.expression)
  state.failed = state.failed or not ok or result ~= 0
  return state.failed and 1 or 0
end

local function geometry(bufnr, notice)
  local available_height = vim.o.lines - vim.o.cmdheight
  -- Reserve space for both borders and cap the complete float at 90% of
  -- the editor. Small values retain enough room for context and controls.
  if vim.o.columns < 3 or available_height < 3 then
    return nil
  end
  local max_width = math.max(1, math.min(math.floor(vim.o.columns * 0.9) - 2, vim.o.columns - 2))
  local max_height = math.max(1, math.min(math.floor(available_height * 0.9) - 2, available_height - 2))
  local width, height = math.min(72, max_width), math.min(8, max_height)
  if bufnr then
    vim.api.nvim_buf_call(bufnr, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local widths = {}
      for index, line in ipairs(lines) do
        widths[index] = vim.fn.strdisplaywidth(line)
        width = math.min(max_width, math.max(width, widths[index] + 2))
        if width == max_width then
          break
        end
      end
      local rows = notice and 1 or 0 -- Only exceptional values need a status winbar.
      for index, line in ipairs(lines) do
        local line_width = widths[index] or vim.fn.strdisplaywidth(line)
        rows = rows + math.max(1, math.ceil(line_width / width))
        if rows >= max_height then
          break
        end
      end
      height = math.min(max_height, math.max(height, rows))
    end)
  end
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((available_height - height - 2) / 2),
    col = math.floor((vim.o.columns - width - 2) / 2),
    style = "minimal",
    border = "rounded",
  }
end

function M.open(snapshot, context, opts)
  opts = opts or {}
  local floating = opts.display ~= "buffer"
  local config = geometry()
  if floating and not config then
    error({ code = "inspection_no_space", message = "The editor is too small to open the cell inspector" }, 0)
  end
  if #snapshot.original > 8 * 1024 * 1024 then
    error({
      code = "inspection_too_large",
      message = "Inspector limit is 8 MiB; original remains available through result copying",
    }, 0)
  end
  next_id = next_id + 1
  local origin = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(origin)
  local transaction =
    generated_buffer.create({ name = "sqlserver-cell://" .. next_id, scratch = true, listed = not floating })
  local bufnr = transaction.bufnr
  local winid
  local function present_buffer()
    if opts.open_results_in then
      opts.open_results_in(bufnr)
    else
      vim.cmd("split")
      vim.api.nvim_win_set_buf(0, bufnr)
    end
    -- Presenters may restore focus to the originating window. Find the
    -- regular window explicitly, excluding the float during promotion.
    for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
      if vim.api.nvim_win_get_config(window).relative == "" then
        vim.api.nvim_set_current_win(window)
        return window
      end
    end
    error("The configured result presenter did not display the cell buffer")
  end
  local group = vim.api.nvim_create_augroup("sqlserver-cell-" .. next_id, { clear = true })
  local ok, err = pcall(function()
    local raw = vim.split(snapshot.is_null and "[SQL NULL]" or snapshot.original, "\n", { plain = true })
    transaction.set_lines(raw)
    vim.bo[bufnr].filetype = snapshot.filetype
    vim.bo[bufnr].readonly = false
    local status = snapshot.status
    local notice = snapshot.notice
    vim.api.nvim_buf_call(bufnr, function()
      if snapshot.is_null or not snapshot.complete or snapshot.original == "" or snapshot.filetype == "text" then
        return
      end
      if #snapshot.original > 1024 * 1024 then
        status = status .. "; formatting skipped above 1 MiB"
        notice = notice or "Formatting skipped (>1 MiB)"
        return
      end
      if snapshot.status:find("invalid JSON", 1, true) then
        return
      end
      local expression = vim.bo.formatexpr
      if expression ~= "" or vim.bo.formatprg ~= "" then
        expressions[bufnr] = { expression = expression }
        if expression ~= "" then
          vim.bo.formatexpr = "v:lua.require'sqlserver.results.ui.inspection'.formatexpr()"
        end
        local formatted = pcall(vim.cmd, "silent keepjumps normal! gggqG")
        local failed = expressions[bufnr].failed or (expression == "" and vim.v.shell_error ~= 0)
        expressions[bufnr] = nil
        vim.bo.formatexpr = expression
        if not formatted or failed then
          transaction.set_lines(raw)
          status = status .. "; formatting failed, showing raw content"
          notice = "Formatting failed · raw value"
        end
      end
    end)
    local formatted = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local can_toggle = not vim.deep_equal(raw, formatted)
    local showing_raw = not can_toggle
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].readonly = true
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].bufhidden = floating and "wipe" or "hide"
    vim.b[bufnr].sqlserver_cell_info = vim.deepcopy(context)
    vim.b[bufnr].sqlserver_cell_status = status
    if floating then
      config = geometry(bufnr, notice)
      config.title = " Cell value "
      winid = vim.api.nvim_open_win(bufnr, true, config)
    else
      winid = present_buffer()
    end
    local function configure_window()
      vim.wo[winid].spell = false
      vim.wo[winid].wrap = true
      vim.wo[winid].linebreak = false
      vim.wo[winid].breakindent = false
      vim.wo[winid].showbreak = ""
      vim.wo[winid].winbar = notice and ("%#DiagnosticWarn#" .. notice:gsub("%%", "%%%%")) or ""
    end
    configure_window()
    local source_name = vim.api.nvim_buf_is_valid(context.source_bufnr)
        and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(context.source_bufnr), ":t")
      or "query"
    local label = string.format(
      "%s · Execution %s · Result %d · Row %d · Column %d (%s)",
      source_name,
      context.execution_id,
      context.result,
      context.row,
      context.column,
      context.column_name
    )
    if floating then
      vim.api.nvim_win_set_config(winid, {
        title = " " .. vim.fn.strcharpart(
          (context.column_name .. " · row " .. context.row):gsub("[\r\n]", " "),
          0,
          math.max(0, config.width - 4)
        ) .. " ",
      })
    end
    local function close()
      local restore_focus = vim.api.nvim_get_current_win() == winid
      if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
        local closed = pcall(vim.api.nvim_win_close, winid, true)
        if not closed then
          local replacement = vim.api.nvim_buf_is_loaded(context.result_bufnr) and context.result_bufnr
            or vim.api.nvim_create_buf(true, true)
          vim.api.nvim_win_set_buf(winid, replacement)
        end
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      if
        restore_focus
        and vim.api.nvim_win_is_valid(origin)
        and vim.api.nvim_win_get_buf(origin) == context.result_bufnr
      then
        vim.api.nvim_set_current_win(origin)
        pcall(vim.api.nvim_win_set_cursor, origin, cursor)
      end
    end
    local actions = { close = close }
    actions.info = function()
      vim.notify(
        table.concat({
          label,
          status,
          "",
          "Esc / :SQLServer CloseCellInspector  Close and return to results",
          can_toggle and ":SQLServer ToggleCellFormat  Toggle raw / formatted content"
            or "No alternative formatted representation available",
          floating and ":SQLServer OpenCellBuffer  Open in a regular buffer"
            or "Use normal Vim selection and yank commands to copy",
        }, "\n"),
        vim.log.levels.INFO,
        { title = "Cell inspector" }
      )
    end
    local attach
    actions.format = function()
      if not can_toggle then
        vim.notify("No alternative formatted representation is available", vim.log.levels.INFO)
        return
      end
      vim.bo[bufnr].readonly = false
      vim.bo[bufnr].modifiable = true
      showing_raw = not showing_raw
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, showing_raw and raw or formatted)
      vim.bo[bufnr].modified = false
      vim.bo[bufnr].modifiable = false
      vim.bo[bufnr].readonly = true
      if floating then
        local resized = geometry(bufnr, notice)
        vim.api.nvim_win_set_config(winid, resized)
      end
      attach()
    end
    actions.open = function()
      if floating then
        local previous = winid
        vim.bo[bufnr].bufhidden = "hide"
        vim.bo[bufnr].buflisted = true
        local position = vim.api.nvim_win_get_cursor(previous)
        if vim.api.nvim_win_is_valid(origin) then
          vim.api.nvim_set_current_win(origin)
        else
          vim.cmd("wincmd p")
        end
        winid = present_buffer()
        floating = false
        configure_window()
        vim.api.nvim_win_set_cursor(winid, position)
        vim.api.nvim_win_close(previous, true)
        attach()
      end
    end
    local previous_prefix
    local function items()
      local result = {}
      if can_toggle then
        table.insert(result, { "f", actions.format, desc = showing_raw and "Show Formatted Value" or "Show Raw Value" })
      end
      if floating then
        table.insert(result, { "o", actions.open, desc = "Open Cell in Buffer" })
      end
      return result
    end
    attach = function()
      if previous_prefix then
        for _, suffix in ipairs({ "f", "o", "q", "i" }) do
          pcall(vim.keymap.del, "n", previous_prefix .. suffix, { buffer = bufnr })
        end
      end
      previous_prefix = configured_prefix
      if configured_prefix then
        for _, item in ipairs(items()) do
          vim.keymap.set("n", configured_prefix .. item[1], item[2], { buffer = bufnr, desc = item.desc })
        end
      end
    end
    inspectors[bufnr] = { actions = actions, items = items, attach = attach }
    attach()
    vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, desc = "Close cell inspector" })
    vim.api.nvim_create_autocmd("VimResized", {
      group = group,
      callback = function()
        if floating and vim.api.nvim_win_is_valid(winid) then
          local resized = geometry(bufnr, notice)
          if resized then
            vim.api.nvim_win_set_config(winid, resized)
          else
            close()
          end
        end
      end,
    })
    for _, owner in ipairs({ context.result_bufnr, context.source_bufnr }) do
      vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
        group = group,
        buffer = owner,
        once = true,
        callback = function()
          vim.schedule(close)
        end,
      })
    end
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        inspectors[bufnr] = nil
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end,
    })
  end)
  if not ok then
    inspectors[bufnr] = nil
    expressions[bufnr] = nil
    pcall(vim.api.nvim_del_augroup_by_id, group)
    transaction.rollback()
    error(err, 0)
  end
  transaction.commit(function() end)
  return { bufnr = bufnr, winid = winid, status = vim.b[bufnr].sqlserver_cell_status }
end

return M
