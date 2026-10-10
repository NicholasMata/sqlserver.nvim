local object_tree = require("sqlserver.objects.explorer")
local object_actions = require("sqlserver.objects.actions")
local agent_tree = require("sqlserver.agent.explorer")
local agent_inspector = require("sqlserver.agent.inspector")
local agent_history = require("sqlserver.agent.ui.history")
local agent_properties = require("sqlserver.agent.ui.properties")

local M, active, navigation = {}, {}, {}

local function focus_explorer(picker)
  picker:focus("input")
  vim.cmd("stopinsert")
end

local function require_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker or type(snacks.picker.pick) ~= "function" then
    return nil, "Object Explorer requires snacks.nvim with its picker enabled"
  end
  return snacks
end

local function can_expand(node)
  if node.isLeaf == true then
    return false
  end
  if node.loaded then
    return #(node.children or {}) > 0
  end
  return node.isLeaf == false
end

function M.focus(bufnr, target)
  local picker = active[bufnr]
  if not picker or picker.closed then
    return false
  end
  focus_explorer(picker)
  if target and navigation[bufnr] then
    navigation[bufnr](target)
  end
  return true
end

function M.open(context)
  local snacks, snacks_error = require_snacks()
  if not snacks then
    return nil, snacks_error
  end
  if context.bufnr and M.focus(context.bufnr, context.focus_target) then
    return active[context.bufnr], nil
  end

  local root = assert(context.root, "Object Explorer requires a SQL Tools Service root node")
  local expanded, search_expanded = {}, {}
  local searching, picker = false, nil
  local search_pattern = ""
  local search_loading, search_cancelling = false, false
  local search_loaded_count = 0
  local refresh_pending = false
  local job_selection = 0
  local closed = false
  local job_windows, job_pickers = {}, {}
  local pending_details

  local function remember(node)
    if node.expanded then
      expanded[node.id] = true
    end
    for _, child in ipairs(node.children or {}) do
      remember(child)
    end
  end
  remember(root)

  local function is_active()
    return not closed and picker and not picker.closed and (not context.is_active or context.is_active())
  end

  local function contains_node(parent, node)
    if parent == node then
      return true
    end
    for _, child in ipairs(parent.children or {}) do
      if contains_node(child, node) then
        return true
      end
    end
    return false
  end

  local function cancel_details()
    if not pending_details then
      return
    end
    local node = pending_details
    pending_details = nil
    node.detail_generation = (node.detail_generation or 0) + 1
    node.loading = false
    node.detail_callbacks = nil
    if context.on_cancel_details then
      context.on_cancel_details()
    end
  end

  local function close_job_views()
    local windows, pickers = job_windows, job_pickers
    job_windows, job_pickers = {}, {}
    for child in pairs(pickers) do
      if child ~= picker and not child.closed then
        child:close()
      end
    end
    for win in pairs(windows) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  end

  local function open_job_float(open, first, second)
    local selection = job_selection
    local win
    local function on_close()
      job_windows[win] = nil
      if is_active() and selection == job_selection and not next(job_windows) and not next(job_pickers) then
        focus_explorer(picker)
      end
    end
    win = second and open(first, second, on_close) or open(first, on_close)
    job_windows[win] = true
  end

  local function has_unloaded(node)
    if node.isLeaf ~= true and not node.loaded then
      return true
    end
    return vim.iter(node.children or {}):any(has_unloaded)
  end

  local function items()
    local result = {}
    local function append_item(node, parent, is_expanded)
      local item = {
        id = node.id,
        sort = string.format("%08d", #result + 1),
        text = searching and search_pattern or node.label,
        label = node.label,
        icon = node.icon,
        kind = node.object and "object" or "group",
        object = node.object,
        node = node,
        parent = parent,
        expanded = is_expanded,
        loading = node.loading,
      }
      result[#result + 1] = item
      return item
    end

    local function append(node, parent)
      local is_expanded = expanded[node.id] == true
      local item = append_item(node, parent, is_expanded)
      if is_expanded then
        for index, child in ipairs(node.children or {}) do
          local child_item = append(child, item)
          child_item.last = index == #node.children
        end
      end
      return item
    end

    local function matches(node)
      local searchable = { node.label }
      vim.list_extend(searchable, object_tree.details(node))
      return #vim.fn.matchfuzzy(searchable, search_pattern) > 0
    end

    local function project(node, include_all)
      local matched = include_all or matches(node)
      local children = {}
      if include_all then
        for _, child in ipairs(node.children or {}) do
          children[#children + 1] = project(child, true)
        end
      else
        for _, child in ipairs(node.children or {}) do
          local projected = project(child, false)
          if projected then
            children[#children + 1] = projected
          end
        end
      end
      local descendant_match = #children > 0
      if not matched and not descendant_match then
        return nil
      end

      local is_expanded = search_expanded[node.id] == true or (descendant_match and search_expanded[node.id] ~= false)
      if matched and search_expanded[node.id] == true then
        children = {}
        for _, child in ipairs(node.children or {}) do
          children[#children + 1] = project(child, true)
        end
      end
      return { node = node, children = children, expanded = is_expanded }
    end

    local function render(projected, parent)
      local item = append_item(projected.node, parent, projected.expanded)
      if projected.expanded then
        for index, child in ipairs(projected.children) do
          local child_item = render(child, item)
          child_item.last = index == #projected.children
        end
      end
      return item
    end

    if searching then
      local tree_incomplete = has_unloaded(root)
      if search_loading then
        result[#result + 1] = {
          id = "sqlserver-search-loading",
          sort = string.format("%08d", #result + 1),
          text = search_pattern,
          label = search_cancelling and "Cancelling object search…"
            or ("Loading all objects… (%d nodes loaded; press c to cancel)"):format(search_loaded_count),
          placeholder = true,
          search_loading = true,
        }
      elseif tree_incomplete then
        result[#result + 1] = {
          id = "sqlserver-search-all",
          sort = string.format("%08d", #result + 1),
          text = search_pattern,
          label = "Search all objects…",
          placeholder = true,
          search_all = true,
        }
      end
      local projection = project(root, false)
      if projection then
        render(projection, nil)
      else
        result[#result + 1] = {
          id = "sqlserver-no-matches",
          sort = string.format("%08d", #result + 1),
          text = search_pattern,
          label = tree_incomplete and "No matching loaded objects" or "No matching objects",
          placeholder = true,
        }
      end
    else
      append(root)
    end
    return result
  end

  local function refresh(current_picker)
    if refresh_pending then
      return
    end
    refresh_pending = true
    vim.schedule(function()
      refresh_pending = false
      if current_picker and not current_picker.closed then
        current_picker:refresh()
      end
    end)
  end

  local function load_node(node, force, callback)
    if node.loading and not (force and node.agent_kind == "jobs") then
      if callback then
        node.load_callbacks = node.load_callbacks or {}
        node.load_callbacks[#node.load_callbacks + 1] = callback
      end
      return false
    end
    if force and node.agent_kind == "jobs" then
      job_selection = job_selection + 1
      cancel_details()
      close_job_views()
    end
    node.load_generation = (node.load_generation or 0) + 1
    local generation = node.load_generation
    node.load_callbacks = node.load_callbacks or {}
    if callback then
      node.load_callbacks[#node.load_callbacks + 1] = callback
    end
    node.loading = true
    refresh(picker)
    context.on_expand(node, force, function(children, err)
      if not is_active() or node.load_generation ~= generation or not contains_node(root, node) then
        return
      end
      local callbacks = node.load_callbacks
      node.load_callbacks = nil
      if err then
        node.loading = false
        node.errorMessage = err.message or tostring(err)
        context.on_error(err.message or tostring(err))
        refresh(picker)
        for _, done in ipairs(callbacks) do
          done(false)
        end
        return
      end
      node.errorMessage = nil
      if node.agent_kind == "jobs" then
        agent_tree.set_jobs(node, children)
      else
        object_tree.set_service_children(node, children)
      end
      refresh(picker)
      for _, done in ipairs(callbacks) do
        done(true)
      end
    end)
    return true
  end

  local function load_all(node, done)
    if search_cancelling then
      done(false)
      return
    end
    if node.isLeaf == true then
      done(true)
      return
    end

    local function visit_children()
      local index = 1
      local function visit_next(ok)
        if not ok or search_cancelling then
          done(false)
          return
        end
        local child = (node.children or {})[index]
        if not child then
          done(true)
          return
        end
        index = index + 1
        load_all(child, visit_next)
      end
      visit_next(true)
    end

    if node.loaded then
      visit_children()
      return
    end
    load_node(node, false, function(ok)
      if not ok then
        done(false)
        return
      end
      search_loaded_count = search_loaded_count + 1
      visit_children()
    end)
  end

  local function start_search_all()
    if search_loading then
      return false
    end
    search_loading = true
    search_cancelling = false
    search_loaded_count = 0
    refresh(picker)
    load_all(root, function()
      if not is_active() then
        return
      end
      search_loading = false
      search_cancelling = false
      refresh(picker)
    end)
    return true
  end

  local function cancel_search_all()
    if not search_loading or search_cancelling then
      return false
    end
    search_cancelling = true
    refresh(picker)
    return true
  end

  local function toggle(item)
    if not item or item.placeholder or not item.node or not can_expand(item.node) then
      return false
    end
    if item.node.loading then
      return false
    end
    local state = searching and search_expanded or expanded
    if not item.node.loaded then
      state[item.id] = true
      load_node(item.node, false)
      return true
    end
    state[item.id] = item.expanded and false or true
    refresh(picker)
    return true
  end

  local function set_all(node, value, state)
    if can_expand(node) then
      state[node.id] = value
    end
    for _, child in ipairs(node.children or {}) do
      set_all(child, value, state)
    end
  end

  local function expand_all(node, state, done)
    if node.isLeaf == true then
      done()
      return
    end

    local function visit_children()
      if can_expand(node) then
        state[node.id] = true
      end
      local index = 1
      local function visit_next()
        local child = (node.children or {})[index]
        if not child then
          done()
          return
        end
        index = index + 1
        expand_all(child, state, visit_next)
      end
      visit_next()
    end

    if node.loaded then
      visit_children()
      return
    end
    load_node(node, false, function(ok)
      if ok then
        visit_children()
      else
        done()
      end
    end)
  end

  local function object_action(callback)
    return function(_, item)
      if item and item.object then
        callback(item.object)
      else
        toggle(item)
      end
    end
  end

  local function node_position(current_picker, item)
    local list = current_picker.list
    local win = list and list.win and list.win.win
    if win and vim.api.nvim_win_is_valid(win) then
      local row = list:idx2row(list.cursor)
      local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), row - 1, row, false)[1] or ""
      local col = item.icon and item.icon ~= "" and line:find(item.icon, 1, true) or 1
      return win, row, col or 1
    end
  end

  local function action_position(current_picker, item)
    local win, row, col = node_position(current_picker, item)
    if win then
      local position = vim.fn.screenpos(win, row, col)
      if position.row > 0 and position.col > 0 then
        return { relative = "editor", row = position.row, col = position.col - 1 }
      end
    end
    return { relative = "cursor", row = 1, col = 0 }
  end

  local function select_action(current_picker, item, actions, callback)
    local prompt = "Actions"
    local position = action_position(current_picker, item)
    local width = vim.fn.strdisplaywidth(prompt) + 4
    for _, action in ipairs(actions) do
      width = math.max(width, vim.fn.strdisplaywidth(action.label) + 6)
    end
    snacks.picker.select(actions, {
      prompt = prompt,
      format_item = function(action)
        return action.icon .. "  " .. action.label
      end,
      snacks = {
        focus = "list",
        format = function(item)
          local action = item.item
          return { { action.icon .. "  " .. action.label } }
        end,
        layout = {
          layout = {
            relative = position.relative,
            row = position.row,
            col = position.col,
            width = math.min(width, math.max(vim.o.columns - 4, 20)),
            min_width = 20,
            height = #actions + 2,
            box = "vertical",
            border = "rounded",
            title = "{title}",
            title_pos = "left",
            { win = "list", border = "none" },
          },
        },
      },
    }, callback)
  end

  local function load_job_details(node, force, callback)
    if node.loading and not force then
      node.detail_callbacks = node.detail_callbacks or {}
      node.detail_callbacks[#node.detail_callbacks + 1] = callback
      return
    end
    if node.details and not force then
      callback(node.details)
      return
    end
    if pending_details and pending_details ~= node then
      cancel_details()
    end
    node.detail_generation = (node.detail_generation or 0) + 1
    local generation = node.detail_generation
    pending_details = node
    node.loading = true
    node.detail_callbacks = node.detail_callbacks or {}
    node.detail_callbacks[#node.detail_callbacks + 1] = callback
    refresh(picker)
    context.on_expand(node, force, function(details, err)
      if not is_active() or node.detail_generation ~= generation or not contains_node(root, node) then
        return
      end
      pending_details = nil
      node.loading = false
      local callbacks = node.detail_callbacks or {}
      node.detail_callbacks = nil
      if err then
        node.errorMessage = err.message or tostring(err)
        context.on_error(node.errorMessage)
        refresh(picker)
        return
      end
      node.errorMessage = nil
      node.details = details
      refresh(picker)
      for _, pending in ipairs(callbacks) do
        pending(details)
      end
    end)
  end

  local function open_job_view(node, section)
    job_selection = job_selection + 1
    local selection = job_selection
    if pending_details and pending_details ~= node then
      cancel_details()
    end
    close_job_views()
    load_job_details(node, false, function(details)
      if selection ~= job_selection then
        return
      end
      if section == "properties" then
        open_job_float(agent_properties.open, node.job, details)
        return
      end
      local rows = agent_inspector.history(details)
      if #rows == 0 then
        vim.notify("No history for " .. node.label, vim.log.levels.INFO, { title = "SQLServer" })
        vim.schedule(function()
          if is_active() then
            focus_explorer(picker)
          end
        end)
        return
      end
      local history_picker = snacks.picker.pick({
        title = "Job History · " .. node.label,
        items = rows,
        focus = "list",
        format = function(item)
          return { { item.label } }
        end,
        layout = { preset = "select" },
        on_close = function(child)
          job_pickers[child] = nil
          vim.schedule(function()
            if is_active() and selection == job_selection and not next(job_windows) and not next(job_pickers) then
              focus_explorer(picker)
            end
          end)
        end,
        confirm = function(current_picker, item)
          if not is_active() or selection ~= job_selection or not item or not item.detail then
            return
          end
          current_picker:close()
          open_job_float(agent_history.open, item)
        end,
      })
      job_pickers[history_picker] = true
    end)
  end

  local function show_actions(current_picker, item)
    if not item or not item.node or (not item.object and not item.node.agent_kind) then
      return
    end
    local current_window = vim.api.nvim_get_current_win()
    local return_focus = current_picker.input
        and current_picker.input.win
        and current_picker.input.win.win == current_window
        and "input"
      or "list"
    local function restore_mode()
      vim.schedule(function()
        if is_active() then
          current_picker:focus(return_focus)
          vim.cmd("stopinsert")
        end
      end)
    end
    local actions
    if item.object then
      actions = object_actions.for_object(item.object)
    elseif item.node.agent_kind == "service" or item.node.agent_kind == "jobs" then
      actions = {
        { id = "refresh_jobs", icon = "󰑐", label = "Refresh Jobs" },
        { id = "copy_name", icon = "󰆏", label = "Copy name" },
      }
    elseif item.node.agent_kind == "job" then
      actions = {
        { id = "inspect_job", icon = "󰈙", label = "Inspect job" },
        { id = "job_history", icon = "󰋚", label = "View history" },
        { id = "refresh_job", icon = "󰑐", label = "Refresh details" },
        { id = "copy_name", icon = "󰆏", label = "Copy name" },
      }
    else
      actions = { { id = "copy_name", icon = "󰆏", label = "Copy name" } }
    end
    select_action(current_picker, item, actions, function(action)
      if not action then
        restore_mode()
        return
      end
      if not is_active() then
        return
      end
      if action.id == "query" then
        context.on_query(item.object)
      elseif action.id == "definition" then
        context.on_definition(item.object)
      elseif action.id == "copy_name" then
        context.on_copy(item.object and item.object.name or item.label)
        restore_mode()
      elseif action.id == "copy_qualified_name" then
        context.on_copy(object_actions.qualified_name(item.object))
        restore_mode()
      elseif action.id == "refresh" then
        load_node(item.node, true)
        restore_mode()
      elseif action.id == "refresh_jobs" then
        local jobs = item.node.agent_kind == "jobs" and item.node or item.node.children[1]
        load_node(jobs, true)
        restore_mode()
      elseif action.id == "inspect_job" then
        open_job_view(item.node, "properties")
      elseif action.id == "job_history" then
        open_job_view(item.node, "history")
      elseif action.id == "refresh_job" then
        load_job_details(item.node, true, function() end)
        restore_mode()
      end
    end)
  end

  local function focus_target(target)
    if target ~= "jobs" then
      return
    end
    local function find_jobs(node)
      if node.agent_kind == "jobs" then
        return node
      end
      for _, child in ipairs(node.children or {}) do
        local found = find_jobs(child)
        if found then
          return found
        end
      end
    end
    local jobs = find_jobs(root)
    if not jobs then
      return
    end
    local function expand_parents(node)
      for _, child in ipairs(node.children or {}) do
        if child == jobs or expand_parents(child) then
          expanded[node.id] = true
          return true
        end
      end
      return false
    end
    expand_parents(root)
    if picker.input and picker.input.set and picker.find then
      picker.input:set("")
      picker:find()
    end
    refresh(picker)
    vim.schedule(function()
      if not is_active() or not picker.list or not picker.list.view then
        return
      end
      for index, item in ipairs(items()) do
        if item.node == jobs then
          picker.list:view(index)
          return
        end
      end
    end)
  end

  local options = vim.tbl_deep_extend("force", {
    title = "SQL Server Object Explorer",
    finder = items,
    focus = "input",
    on_show = function()
      vim.cmd("stopinsert")
    end,
    auto_close = false,
    tree = true,
    layout = { preset = "sidebar", preview = false },
    matcher = { sort_empty = false, fuzzy = true, keep_parents = false },
    sort = { fields = { "sort" } },
    filter = {
      transform = function(current_picker, filter)
        local next_pattern = tostring(filter.pattern or "")
        local next_searching = next_pattern ~= ""
        if search_pattern ~= next_pattern or searching ~= next_searching then
          local was_searching = searching
          search_pattern = next_pattern
          searching = next_searching
          if searching and not was_searching then
            search_expanded = {}
          end
          return true
        end
      end,
    },
    format = function(item, current_picker)
      if item.placeholder then
        return { { item.label, "SnacksPickerComment" } }
      end
      local formatted = snacks.picker.format.tree(item, current_picker)
      local marker = item.loading and "… " or can_expand(item.node) and (item.expanded and " " or " ") or "  "
      formatted[#formatted + 1] = { marker, "SnacksPickerTree" }
      local icon_highlight = item.node.agent_kind == "job"
          and (item.node.job.enabled == true and "SqlServerJobEnabled" or item.node.job.enabled == false and "SqlServerJobDisabled" or "SqlServerJobUnknown")
        or "SnacksPickerIcon"
      formatted[#formatted + 1] = { item.icon .. " ", icon_highlight }
      if item.node.status_icon then
        formatted[#formatted + 1] = { item.node.status_icon .. " ", item.node.status_highlight }
      end
      local label_highlight = item.node.errorMessage and "DiagnosticError"
        or item.object and "SnacksPickerFile"
        or "SnacksPickerDirectory"
      formatted[#formatted + 1] = { item.label, label_highlight }
      local details = object_tree.details(item.node)
      if #details > 0 then
        formatted[#formatted + 1] = { " · " .. table.concat(details, " · "), "SnacksPickerComment" }
      end
      return formatted
    end,
    confirm = function(current_picker, item)
      if item and item.search_all then
        start_search_all()
        return
      end
      if item and item.node and item.node.agent_kind == "job" then
        open_job_view(item.node, "properties")
        return
      end
      object_action(context.on_query)(current_picker, item)
    end,
    actions = {
      object_toggle = function(_, item)
        toggle(item)
      end,
      object_definition = object_action(context.on_definition),
      object_actions = show_actions,
      object_collapse = function(current_picker, item)
        if not item or item.placeholder or not item.node then
          return
        end
        if can_expand(item.node) then
          local state = searching and search_expanded or expanded
          state[item.id] = false
        elseif item.parent then
          local state = searching and search_expanded or expanded
          state[item.parent.id] = false
        end
        refresh(current_picker)
      end,
      object_expand_all = function(current_picker)
        expand_all(root, searching and search_expanded or expanded, function()
          if is_active() then
            refresh(current_picker)
          end
        end)
      end,
      object_collapse_all = function(current_picker)
        local state = searching and search_expanded or expanded
        set_all(root, false, state)
        state[root.id] = true
        refresh(current_picker)
      end,
      object_refresh = function(_, item)
        if item and item.node and not item.placeholder then
          if item.node.agent_kind == "service" then
            load_node(item.node.children[1], true)
          elseif item.node.agent_kind == "job" then
            load_job_details(item.node, true, function() end)
          elseif not item.node.agent_kind or item.node.agent_kind == "jobs" then
            load_node(item.node, true)
          end
        end
      end,
      object_cancel_search = cancel_search_all,
    },
    win = {
      input = {
        keys = {
          ["l"] = { "object_toggle", mode = "n", nowait = true },
          ["h"] = { "object_collapse", mode = "n", nowait = true },
          ["L"] = { "object_expand_all", mode = "n", nowait = true },
          ["H"] = { "object_collapse_all", mode = "n", nowait = true },
          ["K"] = { "object_actions", mode = "n", nowait = true },
          ["c"] = { "object_cancel_search", mode = "n", nowait = true },
          ["d"] = { "object_definition", mode = "n", nowait = true },
          ["r"] = { "object_refresh", mode = "n", nowait = true },
        },
      },
      list = {
        keys = {
          ["<CR>"] = "confirm",
          ["l"] = "object_toggle",
          ["h"] = "object_collapse",
          ["d"] = "object_definition",
          ["K"] = "object_actions",
          ["c"] = "object_cancel_search",
          ["r"] = "object_refresh",
          ["L"] = "object_expand_all",
          ["H"] = "object_collapse_all",
        },
      },
    },
  }, context.picker or {})
  options.matcher.keep_parents = false
  options.sort = { fields = { "sort" } }
  local configured_on_close = options.on_close
  options.on_close = function(closed_picker)
    closed = true
    job_selection = job_selection + 1
    cancel_details()
    close_job_views()
    local function release_node(node)
      node.load_generation = (node.load_generation or 0) + 1
      node.load_callbacks = nil
      node.loading = false
      for _, child in ipairs(node.children or {}) do
        release_node(child)
      end
    end
    release_node(root)
    if context.bufnr and active[context.bufnr] == closed_picker then
      active[context.bufnr] = nil
      navigation[context.bufnr] = nil
    end
    if context.on_close then
      context.on_close()
    end
    if configured_on_close then
      configured_on_close(closed_picker)
    end
  end
  picker = snacks.picker.pick(options)
  vim.api.nvim_set_hl(0, "SqlServerJobEnabled", { default = true, link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "SqlServerJobDisabled", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "SqlServerJobUnknown", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "SqlServerJobRunning", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "SqlServerJobWaiting", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "SqlServerJobSuspended", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "SqlServerJobIdle", { default = true, link = "Comment" })
  if context.bufnr then
    active[context.bufnr] = picker
    navigation[context.bufnr] = focus_target
  end
  if context.focus_target then
    focus_target(context.focus_target)
  end
  return picker, nil
end

function M.close(bufnr)
  local picker = active[bufnr]
  if not picker then
    return false
  end
  active[bufnr] = nil
  navigation[bufnr] = nil
  if not picker.closed then
    picker:close()
  end
  return true
end

return M
