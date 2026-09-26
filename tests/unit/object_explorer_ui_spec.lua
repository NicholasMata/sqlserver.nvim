local explorer = require("sqlserver.objects.ui.explorer")
local model = require("sqlserver.objects.explorer")

local T = MiniTest.new_set()

local function with_snacks(fake, callback)
  local loaded, preload = package.loaded.snacks, package.preload.snacks
  package.loaded.snacks, package.preload.snacks = fake, nil
  local ok, err = pcall(callback)
  package.loaded.snacks, package.preload.snacks = loaded, preload
  assert(ok, err)
end

local function service_node(path, label, object_type, leaf, metadata)
  return model.from_service({
    nodePath = path,
    parentNodePath = path:match("(.+)/[^/]+$"),
    label = label,
    objectType = object_type,
    isLeaf = leaf,
    metadata = metadata,
  })
end

local function fake_snacks(callback)
  local options
  local picker = {
    closed = false,
    matcher = { opts = {} },
    refresh_count = 0,
    refresh = function(self)
      self.refresh_count = self.refresh_count + 1
    end,
    focus = function() end,
    close = function(self)
      self.closed = true
      if options.on_close then
        options.on_close(self)
      end
    end,
  }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      select = function(_, _, done)
        done(nil)
      end,
      pick = function(opts)
        options = opts
        picker.matcher.opts = opts.matcher
        return picker
      end,
    },
  }, function()
    callback(picker, function()
      return options
    end)
  end)
end

T["Object Explorer reports unavailable Snacks"] = function()
  local loaded, preload = package.loaded.snacks, package.preload.snacks
  package.loaded.snacks = nil
  package.preload.snacks = function()
    error("missing")
  end
  local picker, err = explorer.open({ root = service_node("database", "TestDb", "Database", false) })
  package.loaded.snacks, package.preload.snacks = loaded, preload
  assert(picker == nil)
  assert(err == "Object Explorer requires snacks.nvim with its picker enabled")
end

T["Object Explorer renders the service root without synthetic nodes"] = function()
  fake_snacks(function(picker, get_options)
    local root = service_node("server", "localhost", "Server", false)
    local opened = explorer.open({ root = root })
    assert(opened == picker)
    local items = get_options().finder()
    assert(#items == 1)
    assert(items[1].node == root and items[1].id == "server" and items[1].label == "localhost")
  end)
end

T["Object Explorer expands and collapses real service nodes"] = function()
  fake_snacks(function(picker, get_options)
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      { nodePath = "database/Tables", label = "Tables", objectType = "Folder", isLeaf = false },
    })
    root.children[1].expanded = true
    model.set_service_children(root.children[1], {
      {
        nodePath = "database/Tables/dbo.Person",
        label = "Person",
        objectType = "Table",
        isLeaf = false,
        metadata = { name = "Person", schema = "dbo", metadataTypeName = "Table" },
      },
    })
    explorer.open({ root = root })
    local options = get_options()
    assert(#options.finder() == 3)

    local tables = options.finder()[2]
    options.actions.object_collapse(picker, tables)
    assert(#options.finder() == 2)
    tables = options.finder()[2]
    options.actions.object_collapse(picker, tables)
    assert(#options.finder() == 2)
    options.actions.object_toggle(picker, tables)
    assert(#options.finder() == 3)
  end)
end

T["Object Explorer search renders only matches and their ancestors"] = function()
  fake_snacks(function(picker, get_options)
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      { nodePath = "database/Tables", label = "Tables", objectType = "Folder", isLeaf = false },
      { nodePath = "database/Views", label = "Views", objectType = "Folder", isLeaf = false },
      { nodePath = "database/Procedures", label = "Stored Procedures", objectType = "Folder", isLeaf = false },
    })
    model.set_service_children(root.children[1], {
      {
        nodePath = "database/Tables/dbo.Person",
        label = "dbo.Person",
        objectType = "Table",
        isLeaf = false,
        metadata = { name = "Person", schema = "dbo", metadataTypeName = "Table" },
      },
    })
    model.set_service_children(root.children[2], {
      {
        nodePath = "database/Views/dbo.Cars",
        label = "dbo.Cars",
        objectType = "View",
        isLeaf = true,
        metadata = { name = "Cars", schema = "dbo", metadataTypeName = "View" },
      },
    })
    explorer.open({ root = root })
    local options = get_options()

    assert(options.filter.transform(picker, { pattern = "Person" }))
    local found = options.finder()
    assert(#found == 4 and found[1].search_all and found[1].label == "Search all objects…")
    assert(found[2].label == "TestDb" and found[3].label == "Tables" and found[4].label == "dbo.Person")

    assert(options.filter.transform(picker, { pattern = "Nothing" }))
    local empty = options.finder()
    assert(#empty == 2 and empty[1].search_all and empty[1].label == "Search all objects…")
    assert(empty[2].placeholder and empty[2].label == "No matching loaded objects")
    assert(options.format(empty[2], picker)[1][1] == "No matching loaded objects")
    assert(options.actions.object_toggle(picker, empty[2]) == nil)
    options.actions.object_collapse(picker, empty[2])
    options.actions.object_actions(picker, empty[2])

    assert(options.filter.transform(picker, { pattern = "" }))
    assert(#options.finder() == 4)
  end)
end

T["Object Explorer searches all nodes with progress cancellation and caching"] = function()
  fake_snacks(function(picker, get_options)
    local requests, completions = {}, {}
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      { nodePath = "database/Tables", label = "Tables", objectType = "Folder", isLeaf = false },
      { nodePath = "database/Views", label = "Views", objectType = "Folder", isLeaf = false },
    })
    explorer.open({
      root = root,
      on_expand = function(node, _, done)
        requests[#requests + 1] = node.nodePath
        completions[node.nodePath] = done
      end,
      on_error = error,
    })
    local options = get_options()
    options.filter.transform(picker, { pattern = "Missing" })
    local search_all = options.finder()[1]
    options.confirm(picker, search_all)
    assert(vim.deep_equal(requests, { "database/Tables" }))
    local loading = options.finder()
    assert(loading[1].search_loading and loading[1].label:find("press c to cancel", 1, true))

    assert(options.actions.object_cancel_search(picker))
    assert(options.finder()[1].label == "Cancelling object search…")
    completions["database/Tables"]({
      { nodePath = "database/Tables/dbo.Person", label = "dbo.Person", objectType = "Table", isLeaf = true },
      { nodePath = "database/Tables/dbo.Person", label = "dbo.Person", objectType = "Table", isLeaf = true },
    })
    assert(root.children[1].loaded and #root.children[1].children == 1 and not root.children[2].loaded)

    search_all = options.finder()[1]
    options.confirm(picker, search_all)
    assert(vim.deep_equal(requests, { "database/Tables", "database/Views" }))
    local refreshes_before_views = picker.refresh_count
    completions["database/Views"]({
      { nodePath = "database/Views/dbo.Cars", label = "dbo.Cars", objectType = "View", isLeaf = false },
    })
    completions["database/Views/dbo.Cars"]({})
    assert(vim.wait(1000, function()
      return picker.refresh_count == refreshes_before_views + 1
    end))
    local complete = options.finder()
    assert(#complete == 1 and complete[1].label == "No matching objects")
    assert(not options.actions.object_cancel_search(picker))
  end)
end

T["Object Explorer loads children by their service node path"] = function()
  fake_snacks(function(_, get_options)
    local requested
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    explorer.open({
      root = root,
      on_expand = function(node, force, done)
        requested = { path = node.nodePath, force = force }
        done({ { nodePath = "database/Tables", label = "Tables", objectType = "Folder", isLeaf = false } })
      end,
      on_error = error,
    })
    local options = get_options()
    options.actions.object_toggle(nil, options.finder()[1])
    assert(vim.deep_equal(requested, { path = "database", force = false }))
    assert(options.finder()[2].id == "database/Tables")
  end)
end

T["Object Explorer removes disclosure from a loaded empty node"] = function()
  fake_snacks(function(_, get_options)
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      { nodePath = "database/Empty", label = "Empty", objectType = "Folder", isLeaf = false },
    })
    explorer.open({
      root = root,
      on_expand = function(_, _, done)
        done({})
      end,
      on_error = error,
    })
    local options = get_options()
    local empty = options.finder()[2]
    assert(empty.node.isLeaf == false and not empty.node.loaded)
    options.actions.object_toggle(nil, empty)
    empty = options.finder()[2]
    assert(empty.node.loaded and #empty.node.children == 0)
    assert(options.actions.object_toggle(nil, empty) == nil)
    local formatted = options.format(empty, {})
    assert(formatted[1][1] == "  ")
  end)
end

T["Object Explorer expands and collapses all lazy service nodes"] = function()
  fake_snacks(function(picker, get_options)
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      { nodePath = "database/Tables", label = "Tables", objectType = "Tables", isLeaf = false },
    })
    local requested = {}
    explorer.open({
      root = root,
      on_expand = function(node, _, done)
        requested[#requested + 1] = node.nodePath
        if node.label == "Tables" then
          done({
            { nodePath = node.nodePath .. "/dbo.Person", label = "dbo.Person", objectType = "Table", isLeaf = false },
          })
        else
          done({})
        end
      end,
      on_error = error,
    })
    local options = get_options()
    options.actions.object_expand_all(picker)
    assert(vim.deep_equal(requested, { "database/Tables", "database/Tables/dbo.Person" }))
    assert(#options.finder() == 3)

    options.actions.object_collapse_all(picker)
    local collapsed = options.finder()
    assert(#collapsed == 2 and collapsed[1].label == "TestDb" and collapsed[2].label == "Tables")
  end)
end

T["Object Explorer suppresses duplicate loads and preserves collapse while loading"] = function()
  fake_snacks(function(picker, get_options)
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      { nodePath = "database/Tables", label = "Tables", objectType = "Tables", isLeaf = false },
    })
    local complete
    local requests = 0
    explorer.open({
      root = root,
      on_expand = function(_, _, done)
        requests = requests + 1
        complete = done
      end,
      on_error = error,
    })
    local options = get_options()
    local tables = options.finder()[2]
    options.actions.object_toggle(picker, tables)
    options.actions.object_toggle(picker, tables)
    assert(requests == 1 and tables.node.loading)

    options.actions.object_collapse(picker, tables)
    complete({
      { nodePath = "database/Tables/dbo.Person", label = "dbo.Person", objectType = "Table", isLeaf = false },
    })
    assert(tables.node.loaded and not tables.node.loading)
    assert(#options.finder() == 2)
  end)
end

T["Object Explorer presents K actions in a cursor-relative context menu"] = function()
  local picker_options
  local selected_items
  local selected_options
  local selected_callback
  local restored_focus
  local copied
  local picker = {
    closed = false,
    matcher = { opts = {} },
    input = { win = { win = vim.api.nvim_get_current_win() } },
    refresh = function() end,
    focus = function(_, window)
      restored_focus = window
    end,
  }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      pick = function(options)
        picker_options = options
        picker.matcher.opts = options.matcher
        return picker
      end,
      select = function(items, options, callback)
        selected_items = items
        selected_options = options
        selected_callback = callback
      end,
    },
  }, function()
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      {
        nodePath = "database/Tables/dbo.Person",
        label = "dbo.Person",
        objectType = "Table",
        isLeaf = false,
        metadata = { name = "Person", schema = "dbo", metadataTypeName = "Table" },
      },
    })
    explorer.open({
      root = root,
      on_copy = function(value)
        copied = value
      end,
    })
    local person = picker_options.finder()[2]
    picker_options.actions.object_actions(picker, person)

    assert(#selected_items > 1)
    assert(selected_options.prompt == "[dbo].[Person]")
    assert(selected_options.snacks.focus == "list")
    local formatted = selected_options.snacks.format({ item = selected_items[1], idx = 1 })
    assert(formatted[1][1] == selected_items[1].icon .. "  " .. selected_items[1].label)
    assert(not formatted[1][1]:match("^%d+%."))
    local layout = selected_options.snacks.layout.layout
    assert(layout.relative == "cursor" and layout.row == 1 and layout.col == 0)
    assert(layout.border == "rounded" and layout.title == "{title}" and layout.title_pos == "left")
    assert(layout.height == #selected_items + 2 and layout[1].win == "list")
    assert(selected_options.snacks.layout.preset == nil)
    selected_callback(nil)
    assert(vim.wait(1000, function()
      return restored_focus == "input" and vim.fn.mode():find("^n") ~= nil
    end))
    restored_focus = nil
    selected_callback(vim.iter(selected_items):find(function(action)
      return action.id == "copy_qualified_name"
    end))
    assert(vim.wait(1000, function()
      return copied == "[dbo].[Person]" and restored_focus == "input" and vim.fn.mode():find("^n") ~= nil
    end))
  end)
end

T["Object Explorer closes its owning session callback"] = function()
  fake_snacks(function(picker)
    local closed = 0
    explorer.open({
      bufnr = 8123,
      root = service_node("database", "TestDb", "Database", false),
      on_close = function()
        closed = closed + 1
      end,
    })
    assert(explorer.close(8123))
    assert(picker.closed and closed == 1)
  end)
end

T["Object Explorer renders and searches service node details"] = function()
  fake_snacks(function(picker, get_options)
    local root = service_node("database", "TestDb", "Database", false)
    root.expanded = true
    model.set_service_children(root, {
      {
        nodePath = "database/Tables/dbo.Person/Keys/PK_Person",
        label = "PK_Person",
        objectType = "Key",
        nodeSubType = "PrimaryKey",
        nodeStatus = "Disabled",
        errorMessage = "Key metadata is unavailable",
        isLeaf = true,
      },
    })
    explorer.open({ root = root })
    local options = get_options()
    local key = options.finder()[2]
    local formatted = options.format(key, picker)
    assert(formatted[3][1] == "PK_Person" and formatted[3][2] == "DiagnosticError")
    assert(formatted[4][1] == " · PrimaryKey · Disabled · Key metadata is unavailable")
    assert(formatted[4][2] == "SnacksPickerComment")

    assert(options.filter.transform(picker, { pattern = "Disabled" }))
    local matches = options.finder()
    assert(matches[#matches].label == "PK_Person")
  end)
end

return T
