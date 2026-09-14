local object_tree = require("sqlserver.objects.explorer")
local object_actions = require("sqlserver.objects.actions")

local M = {}
local active = {}

local function require_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker or type(snacks.picker.pick) ~= "function" then
    return nil, "Object Explorer requires snacks.nvim with its picker enabled"
  end
  return snacks
end

---@param context table
---@return table? picker
---@return string? error
function M.open(context)
  local snacks, snacks_error = require_snacks()
  if not snacks then
    return nil, snacks_error
  end
  if context.bufnr and active[context.bufnr] and not active[context.bufnr].closed then
    active[context.bufnr]:focus("list")
    return active[context.bufnr], nil
  end

  local root = object_tree.build(context.connection, context.objects)
  local expanded = { [root.id] = true, [root.children[1].id] = true }
  local picker
  local searching = false

  local function items()
    local result = {}
    local function append(current, parent)
      local item = {
        id = current.id,
        sort = string.format("%08d", #result + 1),
        text = current.label,
        label = current.label,
        icon = current.icon,
        kind = current.kind,
        object = current.object,
        node = current,
        parent = parent,
        expanded = searching or expanded[current.id] == true,
      }
      result[#result + 1] = item
      if item.expanded then
        for index, child in ipairs(current.children) do
          local child_item = append(child, item)
          child_item.last = index == #current.children
        end
      end
      return item
    end
    append(root)
    return result
  end

  local function refresh(current_picker)
    if current_picker.refresh then
      current_picker:refresh()
    else
      current_picker:find({ refresh = true })
    end
  end

  local function set_all(current, value)
    if current.loadable and not current.loaded then
      return
    end
    if #current.children > 0 then
      expanded[current.id] = value or nil
      for _, child in ipairs(current.children) do
        set_all(child, value)
      end
    end
  end

  local function leave_search(current_picker)
    if not searching then
      return
    end
    searching = false
    current_picker.matcher.opts.keep_parents = false
    current_picker.input:set("", "")
    current_picker:focus("list")
  end

  local function expand_all_async(current, done)
    if picker.closed then
      return
    end
    expanded[current.id] = true
    local function visit_child(index)
      if index > #current.children then
        done()
        return
      end
      expand_all_async(current.children[index], function()
        visit_child(index + 1)
      end)
    end
    if current.loadable and not current.loaded then
      context.on_expand(current.object or { id = current.id }, function(children, err)
        if err then
          context.on_error(err.message or tostring(err))
          done()
          return
        end
        object_tree.set_children(current, children)
        refresh(picker)
        visit_child(1)
      end)
      return
    end
    visit_child(1)
  end

  local function toggle(picker, item)
    if not item or (#item.node.children == 0 and not item.node.loadable) then
      return false
    end
    leave_search(picker)
    if item.node.loadable and not item.node.loaded then
      context.on_expand(item.node.object or { id = item.node.id }, function(children, err)
        if picker.closed then
          return
        end
        if err then
          context.on_error(err.message or tostring(err))
          return
        end
        object_tree.set_children(item.node, children)
        expanded[item.id] = true
        refresh(picker)
      end)
      return true
    end
    expanded[item.id] = not expanded[item.id]
    refresh(picker)
    return true
  end

  local function object_action(callback)
    return function(picker, item)
      if not item or not item.object then
        toggle(picker, item)
        return
      end
      callback(item.object)
    end
  end

  local function refresh_object(item)
    context.on_expand(item.object, function(children, err)
      if picker.closed then
        return
      end
      if err then
        context.on_error(err.message or tostring(err))
        return
      end
      object_tree.set_children(item.node, children)
      expanded[item.id] = true
      refresh(picker)
    end)
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

  local function show_actions(_, item)
    if not item or not item.object then
      return
    end
    select_action(item.object, function(action)
      if not action or picker.closed then
        return
      end
      if action.id == "query" then
        context.on_query(item.object)
      elseif action.id == "definition" then
        context.on_definition(item.object)
      elseif action.id == "copy_name" then
        context.on_copy(item.object.name)
      elseif action.id == "copy_qualified_name" then
        context.on_copy(object_actions.qualified_name(item.object))
      elseif action.id == "refresh" then
        refresh_object(item)
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
        local next_searching = not filter:is_empty()
        if searching ~= next_searching then
          searching = next_searching
          current_picker.matcher.opts.keep_parents = searching
          return true
        end
      end,
    },
    format = function(item, current_picker)
      local formatted = snacks.picker.format.tree(item, current_picker)
      local can_expand = #item.node.children > 0 or item.node.loadable
      local marker = can_expand and (item.expanded and " " or " ") or "  "
      formatted[#formatted + 1] = { marker, "SnacksPickerTree" }
      formatted[#formatted + 1] = { item.icon .. " ", "SnacksPickerIcon" }
      formatted[#formatted + 1] =
        { item.label, item.kind == "object" and "SnacksPickerFile" or "SnacksPickerDirectory" }
      return formatted
    end,
    confirm = function(current_picker, item)
      object_action(context.on_query)(current_picker, item)
    end,
    actions = {
      object_toggle = function(current_picker, item)
        toggle(current_picker, item)
      end,
      object_definition = object_action(context.on_definition),
      object_actions = show_actions,
      object_collapse = function(current_picker, item)
        leave_search(current_picker)
        if item and expanded[item.id] then
          expanded[item.id] = nil
        elseif item and item.parent then
          expanded[item.parent.id] = nil
        else
          return
        end
        refresh(current_picker)
      end,
      object_expand_all = function(current_picker)
        leave_search(current_picker)
        expand_all_async(root, function()
          refresh(current_picker)
        end)
      end,
      object_collapse_all = function(current_picker)
        leave_search(current_picker)
        set_all(root, false)
        expanded[root.id] = true
        expanded[root.children[1].id] = true
        refresh(current_picker)
      end,
      object_refresh = function(current_picker)
        context.on_refresh(function(objects, err)
          if current_picker.closed then
            return
          end
          if err then
            context.on_error(err.message or tostring(err))
            return
          end
          root = object_tree.build(context.connection, objects)
          expanded[root.id] = true
          expanded[root.children[1].id] = true
          refresh(current_picker)
        end)
      end,
    },
    win = {
      list = {
        keys = {
          ["<CR>"] = "confirm",
          ["l"] = "object_toggle",
          ["h"] = "object_collapse",
          ["d"] = "object_definition",
          ["K"] = "object_actions",
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

---@param bufnr integer
---@return boolean
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
