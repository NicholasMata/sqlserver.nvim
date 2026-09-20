local object_tree = require("sqlserver.objects.explorer")
local object_actions = require("sqlserver.objects.actions")

local M, active = {}, {}

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

function M.focus(bufnr)
  local picker = active[bufnr]
  if not picker or picker.closed then
    return false
  end
  picker:focus("list")
  return true
end

function M.open(context)
  local snacks, snacks_error = require_snacks()
  if not snacks then
    return nil, snacks_error
  end
  if context.bufnr and M.focus(context.bufnr) then
    return active[context.bufnr], nil
  end

  local root = assert(context.root, "Object Explorer requires a SQL Tools Service root node")
  local expanded, search_expanded = {}, {}
  local searching, picker = false, nil
  local search_pattern = ""
  local search_loading, search_cancelling = false, false
  local search_loaded_count = 0
  local refresh_pending = false

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
    return picker and not picker.closed and (not context.is_active or context.is_active())
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
    if node.loading then
      return false
    end
    node.loading = true
    refresh(picker)
    context.on_expand(node, force, function(children, err)
      if not is_active() then
        return
      end
      if err then
        node.loading = false
        context.on_error(err.message or tostring(err))
        refresh(picker)
        if callback then
          callback(false)
        end
        return
      end
      object_tree.set_service_children(node, children)
      refresh(picker)
      if callback then
        callback(true)
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

  local function select_action(object, callback)
    local actions = object_actions.for_object(object)
    local width = #object_actions.qualified_name(object) + 4
    for _, action in ipairs(actions) do
      width = math.max(width, vim.fn.strdisplaywidth(action.label) + 6)
    end
    snacks.picker.select(actions, {
      prompt = object_actions.qualified_name(object),
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
            relative = "cursor",
            row = 1,
            col = 0,
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

  local function show_actions(current_picker, item)
    if not item or not item.object then
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
    select_action(item.object, function(action)
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
        context.on_copy(item.object.name)
        restore_mode()
      elseif action.id == "copy_qualified_name" then
        context.on_copy(object_actions.qualified_name(item.object))
        restore_mode()
      elseif action.id == "refresh" then
        load_node(item.node, true)
        restore_mode()
      end
    end)
  end

  local options = vim.tbl_deep_extend("force", {
    title = "SQL Server Object Explorer",
    finder = items,
    focus = "list",
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
      formatted[#formatted + 1] = { item.icon .. " ", "SnacksPickerIcon" }
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
          load_node(item.node, true)
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
    if context.bufnr and active[context.bufnr] == closed_picker then
      active[context.bufnr] = nil
    end
    if context.on_close then
      context.on_close()
    end
    if configured_on_close then
      configured_on_close(closed_picker)
    end
  end
  picker = snacks.picker.pick(options)
  if context.bufnr then
    active[context.bufnr] = picker
  end
  return picker, nil
end

function M.close(bufnr)
  local picker = active[bufnr]
  if not picker then
    return false
  end
  active[bufnr] = nil
  if not picker.closed then
    picker:close()
  end
  return true
end

return M
