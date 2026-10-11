local cell = require("sqlserver.results.cell")
local inspection = require("sqlserver.results.inspection")
local view = require("sqlserver.results.ui.view")
local T = MiniTest.new_set()

T["Cell inspection distinguishes NULL empty and structured values"] = function()
  local null = inspection.create(cell.create({ is_null = true, display_value = "NULL" }))
  assert(null.is_null and null.status == "SQL NULL")
  assert(not inspection.copy(null))
  local empty = inspection.create(cell.create({ display_value = "" }))
  assert(empty.status == "Empty string")
  assert(inspection.copy(empty, "a") and vim.fn.getreg("a") == "")
  assert(inspection.create(cell.create({ display_value = "null" })).filetype == "text")
  assert(inspection.create(cell.create({ display_value = "null" }), nil, "json").filetype == "json")
  assert(inspection.create(cell.create({ display_value = '{"x":"😀"}' })).filetype == "json")
  assert(inspection.create(cell.create({ display_value = "{invalid}" })).filetype == "text")
  assert(inspection.create(cell.create({ display_value = "<x/>" })).filetype == "text")
  assert(inspection.create(cell.create({ display_value = "<x/>" }), { type_name = "xml" }).filetype == "xml")
  local invalid = inspection.create(cell.create({ display_value = "{bad}" }), nil, "json")
  assert(invalid.status:find("invalid JSON", 1, true))
  local partial =
    inspection.create(cell.create({ display_value = "part", completeness = "possibly_truncated", limit = 10 }))
  assert(partial.status:find("limit 10", 1, true) and not inspection.copy(partial))
  assert(partial.notice:find("Possibly truncated", 1, true))
  assert(not inspection.create(cell.create({ display_value = "<x/>" }), { type_name = "xml" }).notice)
end

local function show(value, metadata, presenter)
  view.clear()
  local source = vim.api.nvim_create_buf(false, true)
  view.show({
    require("sqlserver.results.result_set").create({
      columns = { "Payload" },
      column_metadata = { metadata or {} },
      rows = { { cell.create({ display_value = value }) } },
      row_count = 1,
      locator = {},
    }),
  }, {
    results = { max_cell_width = 8, history_limit = 2 },
    open_results_in = presenter or function(buf)
      if vim.b[buf].sqlserver_cell_info then
        vim.cmd("split")
      end
      vim.api.nvim_set_current_buf(buf)
    end,
  }, source)
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  return source, vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
end

T["Cell inspector focuses resizes returns and follows result ownership"] = function()
  local value = "Grüße 😀\n" .. string.rep("long value", 10000) .. "\n"
  local source, result, origin = show(value)
  local opened = view.inspect_cell()
  assert(vim.api.nvim_get_current_win() == opened.winid)
  assert(vim.bo[opened.bufnr].readonly and not vim.bo[opened.bufnr].modifiable)
  assert(not vim.wo[opened.winid].spell)
  assert(vim.wo[opened.winid].winbar == "", "Complete values should not show a status banner")
  assert(vim.api.nvim_win_get_config(opened.winid).footer == nil, "Inspector should not show a footer hint")
  assert(table.concat(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false), "\n") == value)
  vim.cmd("normal! ggVGy")
  assert(vim.fn.getreg('"') == value .. "\n")
  assert(vim.b[opened.bufnr].sqlserver_cell_info.row == 1)
  vim.api.nvim_exec_autocmds("VimResized", {})
  assert(vim.api.nvim_win_get_width(opened.winid) <= vim.o.columns)
  require("sqlserver.results.ui.inspection").perform("close")
  assert(not vim.api.nvim_buf_is_valid(opened.bufnr))
  assert(
    vim.api.nvim_get_current_win() == origin and vim.api.nvim_get_current_buf() == result,
    vim.inspect({
      current_win = vim.api.nvim_get_current_win(),
      origin = origin,
      current_buf = vim.api.nvim_get_current_buf(),
      result = result,
    })
  )
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 3, 0 }))
  opened = view.inspect_cell()
  vim.api.nvim_win_set_buf(origin, source)
  vim.api.nvim_buf_delete(result, { force = true })
  vim.wait(100, function()
    return not vim.api.nvim_buf_is_valid(opened.bufnr)
  end, 10)
  assert(
    not vim.api.nvim_buf_is_valid(opened.bufnr),
    vim.inspect({
      valid_result = vim.api.nvim_buf_is_valid(result),
      eventignore = vim.o.eventignore,
    })
  )
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end

T["Inspector scales to content and keeps its capped border in bounds on resize"] = function()
  local columns, lines, cmdheight = vim.o.columns, vim.o.lines, vim.o.cmdheight
  local source = show("one line")
  local opened = view.inspect_cell()
  local small = vim.api.nvim_win_get_config(opened.winid)
  assert(small.width <= 72 and small.height <= 8)
  assert(vim.wo[opened.winid].wrap)
  require("sqlserver.results.ui.inspection").perform("close")
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
  source = show(string.rep("界😀", 10000))
  opened = view.inspect_cell()
  local ok, err = pcall(function()
    for _, size in ipairs({ { 200, 60, 1 }, { 80, 24, 3 }, { 20, 10, 1 }, { 160, 50, 0 } }) do
      vim.o.columns, vim.o.lines, vim.o.cmdheight = size[1], size[2], size[3]
      vim.api.nvim_exec_autocmds("VimResized", {})
      local config = vim.api.nvim_win_get_config(opened.winid)
      local available_height = vim.o.lines - vim.o.cmdheight
      assert(config.width + 2 >= math.floor(vim.o.columns * 0.9))
      assert(config.height + 2 >= math.floor(available_height * 0.9))
      assert(config.row >= 0 and config.col >= 0)
      assert(config.col + config.width + 2 <= vim.o.columns)
      assert(config.row + config.height + 2 <= available_height)
    end
  end)
  vim.o.columns, vim.o.lines, vim.o.cmdheight = columns, lines, cmdheight
  require("sqlserver.results.ui.inspection").perform("close")
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
  assert(ok, err)
end

T["Formatting preserves original and recovers raw content on failure"] = function()
  local source = show('{"x":1}', { type_name = "nvarchar" })
  local group = vim.api.nvim_create_augroup("test-cell-format", { clear = true })
  local fail = false
  _G.sqlserver_test_cell_format = function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "formatted" })
    return fail and 1 or 0
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "json",
    callback = function()
      vim.bo.formatexpr = "v:lua.sqlserver_test_cell_format()"
    end,
  })
  local opened = view.inspect_cell()
  local function format_label()
    for _, item in ipairs(require("sqlserver.results.ui.inspection").which_key_items()) do
      if item[1] == "f" then
        return item.desc
      end
    end
  end
  assert(format_label() == "Show Raw Value")
  assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == "formatted")
  assert(inspection.copy(inspection.create(cell.create({ display_value = '{"x":1}' })), "a"))
  assert(vim.fn.getreg("a") == '{"x":1}')
  require("sqlserver.results.ui.inspection").perform("format")
  assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == '{"x":1}')
  assert(format_label() == "Show Formatted Value")
  require("sqlserver.results.ui.inspection").perform("format")
  assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == "formatted")
  require("sqlserver.results.ui.inspection").perform("open")
  assert(vim.api.nvim_get_current_buf() == opened.bufnr)
  require("sqlserver.results.ui.inspection").perform("format")
  assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == '{"x":1}')
  require("sqlserver.results.ui.inspection").perform("format")
  assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == "formatted")
  require("sqlserver.results.ui.inspection").perform("close")
  fail = true
  opened = view.inspect_cell()
  assert(vim.api.nvim_buf_get_lines(opened.bufnr, 0, -1, false)[1] == '{"x":1}')
  assert(opened.status:find("formatting failed", 1, true))
  assert(vim.wo[opened.winid].winbar:find("Formatting failed", 1, true))
  vim.api.nvim_buf_delete(source, { force = true })
  vim.wait(100, function()
    return not vim.api.nvim_buf_is_valid(opened.bufnr)
  end, 10)
  assert(not vim.api.nvim_buf_is_valid(opened.bufnr))
  vim.api.nvim_del_augroup_by_id(group)
  _G.sqlserver_test_cell_format = nil
  view.clear()
end

T["Inspection reports size limits and cleans up with retained history"] = function()
  local source, result, origin = show(string.rep("x", 8 * 1024 * 1024 + 1))
  local ok, err = pcall(view.inspect_cell)
  assert(not ok and err.code == "inspection_too_large")
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })

  source, result, origin = show("retained")
  local opened = view.inspect_cell()
  -- A newer execution evicts the owning result at history_limit=1.
  view.show({
    require("sqlserver.results.result_set").create({
      columns = { "Payload" },
      rows = { { cell.create({ display_value = "new" }) } },
      row_count = 1,
      locator = {},
    }),
  }, {
    results = { history_limit = 1, max_cell_width = 8 },
    open_results_in = function(buf)
      vim.api.nvim_win_set_buf(origin, buf)
    end,
  }, source)
  assert(vim.wait(200, function()
    return not vim.api.nvim_buf_is_valid(opened.bufnr)
  end, 10))
  assert(not vim.api.nvim_buf_is_valid(result))
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
end

T["Cells open in regular buffers and floats promote without losing their presentation"] = function()
  local source, result, origin = show("first\nsecond")
  local opened = view.inspect_cell({ display = "buffer" })
  assert(vim.api.nvim_win_get_config(opened.winid).relative == "")
  assert(vim.bo[opened.bufnr].buflisted and vim.bo[opened.bufnr].bufhidden == "hide")
  assert(vim.api.nvim_win_get_buf(origin) == result)
  local buffer = opened.bufnr
  vim.cmd("close")
  assert(vim.api.nvim_buf_is_valid(buffer), "Regular cell buffers survive closing their window")
  assert(vim.api.nvim_get_current_win() == origin)
  opened = view.inspect_cell()
  vim.api.nvim_win_set_cursor(opened.winid, { 2, 2 })
  require("sqlserver.results.ui.inspection").perform("open")
  local promoted = vim.api.nvim_get_current_win()
  assert(not vim.api.nvim_win_is_valid(opened.winid))
  assert(vim.api.nvim_win_get_config(promoted).relative == "")
  assert(vim.api.nvim_get_current_buf() == opened.bufnr)
  assert(vim.bo[opened.bufnr].buflisted and vim.wo[promoted].wrap and not vim.wo[promoted].spell)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(promoted), { 2, 2 }))
  local mappings = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(opened.bufnr, "n")) do
    mappings[mapping.lhs] = true
  end
  assert(not mappings.yic and not mappings.o)
  require("sqlserver.results.ui.inspection").perform("close")
  assert(vim.api.nvim_get_current_win() == origin)
  assert(not vim.api.nvim_buf_is_valid(opened.bufnr))
  vim.api.nvim_buf_delete(source, { force = true })
  assert(vim.wait(100, function()
    return not vim.api.nvim_buf_is_valid(buffer)
  end, 10))
  view.clear()
end

T["Inspector plugin menu replaces unrelated actions and preserves native commands"] = function()
  local source = show("plain text")
  local ui = require("sqlserver.results.ui.inspection")
  local opened = view.inspect_cell()
  local previous_wk = package.loaded["which-key"]
  local menus = {}
  package.loaded["which-key"] = {
    add = function(menu)
      table.insert(menus, menu)
    end,
  }
  local ok, err = pcall(function()
    require("sqlserver.ui.keymaps").set_keymaps("\\m", require("sqlserver").commands)
    local actions = menus[1].expand()
    local keys = {}
    for _, item in ipairs(actions) do
      keys[item[1]] = true
    end
    assert(keys.o and not keys.q and not keys.i and not keys.f and not keys.n and not keys.d and not keys.v)
    assert(#menus[2].expand() == 0)
    for _, key in ipairs({ "R", "o", "q", "?", "f" }) do
      assert(vim.fn.maparg(key, "n") == "", "Inspector should preserve native " .. key)
    end
    assert(vim.fn.maparg("\\mo", "n", false, true).buffer == 1)
    ui.setup_keymaps("\\s")
    assert(vim.fn.maparg("\\mo", "n") == "")
    assert(vim.fn.maparg("\\so", "n", false, true).buffer == 1)
    ui.perform("open")
    assert(vim.fn.maparg("\\so", "n") == "")
    ui.setup_keymaps(nil)
    assert(vim.fn.maparg("\\sf", "n") == "")
  end)
  package.loaded["which-key"] = previous_wk
  ui.setup_keymaps(nil)
  ui.perform("close")
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
  assert(not vim.api.nvim_buf_is_valid(opened.bufnr))
  assert(ok, err)
end

T["Inspector fallback prefix cannot invoke global plugin actions"] = function()
  local source, _, origin = show("plain text")
  local ui = require("sqlserver.results.ui.inspection")
  local loaded, preload = package.loaded["which-key"], package.preload["which-key"]
  package.loaded["which-key"] = nil
  package.preload["which-key"] = function()
    error("WhichKey unavailable in this test")
  end
  local calls = 0
  local commands = setmetatable({}, {
    __index = function()
      return function()
        calls = calls + 1
      end
    end,
  })
  local opened
  local ok, err = pcall(function()
    require("sqlserver.ui.keymaps").set_keymaps("\\z", commands)
    opened = view.inspect_cell()
    local function invoke(key, mode)
      vim.fn.maparg("\\z" .. key, mode or "n", false, true).callback()
    end
    for _, key in ipairs({ "a", "i", "n", "c", "R", "q", "l", "x", "X", "e", "r", "d", "f", "b", "v", "s" }) do
      invoke(key)
    end
    invoke("x", "x")
    assert(calls == 0, "Unavailable cell actions must not invoke global plugin commands")
    invoke("o")
    assert(vim.api.nvim_get_current_buf() == opened.bufnr)
    assert(not vim.api.nvim_win_is_valid(opened.winid))
    invoke("o")
    invoke("f")
    invoke("q")
    assert(calls == 0, "Promoted buffers must retain contextual prefix behavior")
    ui.perform("close")
    vim.api.nvim_set_current_win(origin)
    invoke("f")
    invoke("q")
    assert(calls == 2, "Global commands must still work outside inspectors")
  end)
  package.loaded["which-key"], package.preload["which-key"] = loaded, preload
  for _, mode in ipairs({ "n", "x", "s" }) do
    for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
      if mapping.lhs:sub(1, 2) == "\\z" then
        vim.keymap.del(mode, mapping.lhs)
      end
    end
  end
  ui.setup_keymaps(nil)
  if opened and vim.api.nvim_buf_is_valid(opened.bufnr) then
    vim.api.nvim_set_current_buf(opened.bufnr)
    ui.perform("close")
  end
  view.clear()
  vim.api.nvim_buf_delete(source, { force = true })
  assert(ok, err)
end

T["Direct and promoted cell buffers use the result presenter and split direction"] = function()
  local below, right = vim.o.splitbelow, vim.o.splitright
  local ok, err = pcall(function()
    for _, command in ipairs({ "split", "vsplit", "current_window" }) do
      for _, after in ipairs({ false, true }) do
        vim.o.splitbelow, vim.o.splitright = after, after
        for _, promote in ipairs({ false, true }) do
          local presentations = 0
          local source, result, origin = show("first\nsecond", nil, function(buf)
            if vim.b[buf].sqlserver_cell_info then
              presentations = presentations + 1
              if command ~= "current_window" then
                vim.cmd(command)
              end
              vim.api.nvim_win_set_buf(0, buf)
              -- The built-in split presenters restore the origin's focus.
              vim.cmd("wincmd p")
            else
              vim.api.nvim_set_current_buf(buf)
            end
          end)
          local opened = view.inspect_cell({ display = promote and "float" or "buffer" })
          if promote then
            vim.api.nvim_win_set_cursor(0, { 2, 2 })
            require("sqlserver.results.ui.inspection").perform("open")
            assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 2 }))
          end
          assert(presentations == 1)
          assert(vim.api.nvim_get_current_buf() == opened.bufnr)
          assert(vim.api.nvim_win_get_config(0).relative == "")
          local position = vim.api.nvim_win_get_position(0)
          local original = vim.api.nvim_win_get_position(origin)
          if command == "current_window" then
            assert(vim.api.nvim_get_current_win() == origin)
          else
            assert(vim.api.nvim_win_get_buf(origin) == result)
            local axis = command == "split" and 1 or 2
            assert(after and position[axis] > original[axis] or not after and position[axis] < original[axis])
          end
          require("sqlserver.results.ui.inspection").perform("close")
          view.clear()
          vim.api.nvim_buf_delete(source, { force = true })
        end
      end
    end
  end)
  vim.o.splitbelow, vim.o.splitright = below, right
  assert(ok, err)
end

T["Adapter marks service storage boundaries without fetching again"] = require("tests.helpers").async(function()
  local utils = require("sqlserver.utils")
  local original_client, original_request = utils.get_lsp_client, utils.lsp_request_async
  local values = { string.rep("😀", 32767) .. "x", string.rep("x", 65534), "0x" .. string.rep("FF", 65535) }
  local requests = 0
  utils.get_lsp_client = function()
    return {}
  end
  utils.lsp_request_async = function(_, method)
    assert(method == "query/subset")
    requests = requests + 1
    return {
      resultSubset = {
        rows = { vim.tbl_map(function(value)
          return { displayValue = value }
        end, values) },
      },
    }
  end
  local ok, rows = pcall(
    require("sqlserver.adapters.sql_tools_service.query").get_result_rows_async,
    { rowsCount = 1 },
    { { is_long = true }, { is_long = true }, { is_long = true, type_name = "varbinary" } }
  )
  utils.get_lsp_client, utils.lsp_request_async = original_client, original_request
  assert(ok, tostring(rows))
  assert(requests == 1)
  assert(rows[1][1].completeness == "possibly_truncated")
  assert(rows[1][2].completeness == "complete")
  assert(rows[1][3].completeness == "possibly_truncated")
end)

return T
