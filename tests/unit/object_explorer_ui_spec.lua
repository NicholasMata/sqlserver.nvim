local explorer = require("sqlserver.objects.ui.explorer")

local T = MiniTest.new_set()

local function with_snacks(fake, callback)
  local previous_loaded = package.loaded.snacks
  local previous_preload = package.preload.snacks
  package.loaded.snacks = fake
  package.preload.snacks = nil
  local ok, err = pcall(callback)
  package.loaded.snacks = previous_loaded
  package.preload.snacks = previous_preload
  assert(ok, err)
end

T["Object explorer reports unavailable Snacks without affecting setup"] = function()
  local previous_loaded = package.loaded.snacks
  local previous_preload = package.preload.snacks
  package.loaded.snacks = nil
  package.preload.snacks = function()
    error("missing")
  end
  local picker, err = explorer.open({ connection = {}, objects = {} })
  package.loaded.snacks = previous_loaded
  package.preload.snacks = previous_preload
  assert(picker == nil)
  assert(err == "Object Explorer requires snacks.nvim with its picker enabled")
end

T["Object explorer rejects Snacks without its picker"] = function()
  with_snacks({}, function()
    local picker, err = explorer.open({ connection = {}, objects = {} })
    assert(picker == nil)
    assert(err == "Object Explorer requires snacks.nvim with its picker enabled")
  end)
end

T["Object explorer expands nodes and dispatches object actions"] = function()
  local picker_options
  local find_count = 0
  local filter_empty = true
  local picker = {
    main = nil,
    filter = function()
      return {
        is_empty = function()
          return filter_empty
        end,
      }
    end,
    find = function()
      find_count = find_count + 1
    end,
    norm = function(_, callback)
      callback()
    end,
  }
  local queried
  local defined
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      pick = function(options)
        picker_options = options
        picker.matcher = { opts = options.matcher }
        return picker
      end,
    },
  }, function()
    local opened, err = explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = { { id = "person", name = "Person", schema = "dbo", type = "Table", path = "Tables/" } },
      on_query = function(object)
        queried = object
      end,
      on_definition = function(object)
        defined = object
      end,
      on_refresh = function() end,
      on_error = error,
    })
    assert(opened == picker and err == nil)

    local items = picker_options.finder()
    assert(#items == 3)
    assert(items[1].label == "localhost" and items[2].label == "TestDb")
    assert(items[3].label == "Tables")

    filter_empty = false
    assert(picker_options.filter.transform(picker, picker:filter()))
    assert(#picker_options.finder() == 4)
    filter_empty = true
    assert(picker_options.filter.transform(picker, picker:filter()))

    picker_options.confirm(picker, items[3])
    items = picker_options.finder()
    assert(items[4].label == "Person")

    picker_options.confirm(picker, items[4])
    picker_options.actions.object_definition(picker, items[4])
    assert(vim.wait(1000, function()
      return queried ~= nil and defined ~= nil
    end))
    assert(queried.id == "person" and defined.id == "person")
    assert(find_count == 1)
  end)
end

T["Object explorer redraws through cursor-preserving refresh"] = function()
  local picker_options
  local refresh_count = 0
  local cursor = 5
  local picker = {
    refresh = function()
      assert(cursor == 5)
      refresh_count = refresh_count + 1
    end,
    find = function()
      error("Tree redraw bypassed cursor-preserving refresh")
    end,
    norm = function(_, callback)
      callback()
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
        picker.matcher = { opts = options.matcher }
        return picker
      end,
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = { { id = "person", name = "Person", schema = "dbo", type = "Table", path = "Tables/" } },
      on_query = function() end,
      on_definition = function() end,
      on_refresh = function() end,
      on_expand = function(_, callback)
        callback({})
      end,
      on_error = error,
    })
    local function press(key)
      local action = picker_options.win.list.keys[key]
      picker_options.actions[action](picker)
    end
    press("L")
    assert(#picker_options.finder() == 4)
    press("H")
    assert(#picker_options.finder() == 3)
    assert(refresh_count == 3)
    assert(picker_options.matcher.keep_parents == false)
    assert(picker_options.win.list.keys.L == "object_expand_all")
    assert(picker_options.win.list.keys.H == "object_collapse_all")
    assert(picker_options.win.list.keys.E == nil and picker_options.win.list.keys.C == nil)
  end)
end

T["Object explorer retains parents only while searching"] = function()
  local picker_options
  local filter_empty = true
  local picker = {
    matcher = { opts = {} },
    filter = function()
      return {
        is_empty = function()
          return filter_empty
        end,
      }
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
    },
  }, function()
    explorer.open({ connection = {}, objects = {} })
    assert(not picker.matcher.opts.keep_parents)
    filter_empty = false
    assert(picker_options.filter.transform(picker, picker:filter()))
    assert(picker.matcher.opts.keep_parents)
    filter_empty = true
    assert(picker_options.filter.transform(picker, picker:filter()))
    assert(not picker.matcher.opts.keep_parents)
  end)
end

T["Object explorer search retains tree order with ancestors"] = function()
  local picker_options
  local picker = { matcher = { opts = {} } }
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
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = {
        { id = "person", name = "Person", schema = "dbo", type = "Table", path = "Tables/" },
        { id = "person-view", name = "PersonView", schema = "dbo", type = "View", path = "Views/" },
      },
    })
    picker_options.filter.transform(picker, {
      is_empty = function()
        return false
      end,
    })

    local included = {}
    for _, item in ipairs(picker_options.finder()) do
      if item.label:find("Person", 1, true) then
        local current = item
        while current do
          included[current.id] = current
          current = current.parent
        end
      end
    end
    local visible = vim.tbl_values(included)
    table.sort(visible, function(left, right)
      return left.sort < right.sort
    end)
    assert(vim.deep_equal(
      vim.tbl_map(function(item)
        return item.label
      end, visible),
      { "localhost", "TestDb", "Tables", "Person", "Views", "PersonView" }
    ))
    assert(vim.deep_equal(picker_options.sort.fields, { "sort" }))
  end)
end

T["Object explorer tree mappings work after searching"] = function()
  local picker_options
  local cleared_search = 0
  local focused_list = 0
  local picker = {
    matcher = { opts = {} },
    input = {
      set = function(_, pattern, search)
        assert(pattern == "" and search == "")
        cleared_search = cleared_search + 1
      end,
    },
    focus = function(_, target)
      assert(target == "list")
      focused_list = focused_list + 1
    end,
    refresh = function() end,
    norm = function(_, callback)
      callback()
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
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = { { id = "person", name = "Person", schema = "dbo", type = "Table", path = "Tables/" } },
      on_expand = function(_, callback)
        callback({})
      end,
    })
    local tables = picker_options.finder()[3]
    local function press(key, item)
      local action = picker_options.win.list.keys[key]
      assert(type(action) == "string")
      picker_options.actions[action](picker, item)
    end

    assert(picker_options.filter.transform(picker, {
      is_empty = function()
        return false
      end,
    }))
    press("l", tables)
    assert(#picker_options.finder() == 4)
    assert(cleared_search == 1 and focused_list == 1)
    assert(picker_options.filter.transform(picker, {
      is_empty = function()
        return false
      end,
    }))
    press("h", tables)
    assert(#picker_options.finder() == 3)
    assert(cleared_search == 2 and focused_list == 2)

    assert(picker_options.filter.transform(picker, {
      is_empty = function()
        return false
      end,
    }))
    press("L")
    assert(#picker_options.finder() == 4)
    assert(cleared_search == 3 and focused_list == 3)

    assert(picker_options.filter.transform(picker, {
      is_empty = function()
        return false
      end,
    }))
    press("H")
    assert(#picker_options.finder() == 3)
    assert(cleared_search == 4 and focused_list == 4)
  end)
end

T["Object explorer focuses an existing workspace picker"] = function()
  local pick_count = 0
  local focus_count = 0
  local picker = {
    closed = false,
    close = function(self)
      self.closed = true
    end,
    focus = function(_, target)
      assert(target == "list")
      focus_count = focus_count + 1
    end,
  }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      pick = function()
        pick_count = pick_count + 1
        return picker
      end,
    },
  }, function()
    local context = {
      bufnr = 8123,
      connection = {},
      objects = {},
      on_query = function() end,
      on_definition = function() end,
      on_refresh = function() end,
      on_error = error,
    }
    explorer.open(context)
    explorer.open(context)
    assert(pick_count == 1 and focus_count == 1)
    assert(explorer.close(context.bufnr))
  end)
end

T["Object explorer refreshes its tree and accepts picker layout overrides"] = function()
  local picker_options
  local picker = {
    filter = function()
      return {
        is_empty = function()
          return true
        end,
      }
    end,
    find = function() end,
    norm = function(_, callback)
      callback()
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
        return picker
      end,
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = {},
      picker = { layout = { preset = "right" } },
      on_query = function() end,
      on_definition = function() end,
      on_refresh = function(callback)
        callback({ { id = "person", name = "Person", schema = "dbo", type = "Table", path = "Tables/" } })
      end,
      on_error = error,
    })
    assert(picker_options.layout.preset == "right")
    picker_options.actions.object_refresh(picker)
    local items = picker_options.finder()
    assert(items[1].label == "localhost")
    assert(items[3].label == "Tables")
  end)
end

T["Object explorer search includes every loaded detail type with ancestors"] = function()
  local picker_options
  local picker = {
    closed = false,
    matcher = { opts = {} },
    refresh = function() end,
    focus = function() end,
    input = { set = function() end },
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
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = { { id = "person", name = "Person", type = "Table", path = "Tables/" } },
      on_expand = function(object, callback)
        if object.id == "person" then
          callback({
            { id = "columns", label = "Columns", type = "Folder", expandable = true },
            { id = "keys", label = "Keys", type = "Folder", expandable = true },
            { id = "constraints", label = "Constraints", type = "Folder", expandable = true },
            { id = "indexes", label = "Indexes", type = "Folder", expandable = true },
            { id = "statistics", label = "Statistics", type = "Folder", expandable = true },
            { id = "triggers", label = "Triggers", type = "Folder", expandable = true },
            { id = "future", label = "Future Detail", type = "FutureNode" },
          })
        else
          callback({})
        end
      end,
      on_error = error,
    })
    picker_options.actions.object_expand_all(picker)
    picker_options.filter.transform(picker, {
      is_empty = function()
        return false
      end,
    })

    local labels = vim.tbl_map(function(item)
      return item.label
    end, picker_options.finder())
    for _, label in ipairs({
      "localhost",
      "TestDb",
      "Tables",
      "Person",
      "Columns",
      "Keys",
      "Constraints",
      "Indexes",
      "Statistics",
      "Triggers",
      "Future Detail",
    }) do
      assert(vim.tbl_contains(labels, label), "Missing loaded search item: " .. label)
    end
  end)
end

T["Object explorer expand all continues after a child load failure"] = function()
  local picker_options
  local errors = {}
  local loaded = {}
  local picker = {
    closed = false,
    matcher = { opts = {} },
    refresh = function() end,
    focus = function() end,
    input = { set = function() end },
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
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = {
        { id = "broken", name = "Broken", type = "Table", path = "Tables/" },
        { id = "healthy", name = "Healthy", type = "Table", path = "Tables/" },
      },
      on_expand = function(object, callback)
        loaded[#loaded + 1] = object.id
        if object.id == "broken" then
          callback(nil, { message = "permission denied" })
        else
          callback({ { id = "healthy/Columns", label = "Columns", type = "Folder" } })
        end
      end,
      on_error = function(message)
        errors[#errors + 1] = message
      end,
    })
    picker_options.actions.object_expand_all(picker)
    assert(vim.deep_equal(loaded, { "broken", "healthy" }))
    assert(vim.deep_equal(errors, { "permission denied" }))
    assert(vim.tbl_contains(
      vim.tbl_map(function(item)
        return item.label
      end, picker_options.finder()),
      "Columns"
    ))
  end)
end

T["Object explorer opens contextual actions with K"] = function()
  local picker_options
  local selected_title
  local copied
  local refreshed
  local queried
  local defined
  local selected_action = "copy_qualified_name"
  local picker = {
    closed = false,
    matcher = { opts = {} },
    refresh = function() end,
    norm = function()
      error("Object action focused the source window before scripting completed")
    end,
  }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      select = function(actions, opts, callback)
        selected_title = opts.prompt
        assert(opts.snacks.focus == "list")
        assert(opts.snacks.layout.layout.relative == "cursor")
        assert(opts.snacks.layout.layout[1].win == "list")
        assert(opts.format_item(actions[1]):find(actions[1].label, 1, true))
        callback(vim.iter(actions):find(function(action)
          return action.id == selected_action
        end))
      end,
      pick = function(options)
        picker_options = options
        picker.matcher.opts = options.matcher
        return picker
      end,
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = {
        { id = "person", name = "Person", schema = "dbo", type = "Table", path = "Tables/" },
      },
      on_copy = function(text)
        copied = text
      end,
      on_expand = function(object, callback)
        refreshed = object
        callback({})
      end,
      on_query = function(object)
        queried = object
      end,
      on_definition = function(object)
        defined = object
      end,
      on_error = error,
    })
    local tables = picker_options.finder()[3]
    picker_options.actions.object_toggle(picker, tables)
    local person = picker_options.finder()[4]
    local action = picker_options.win.list.keys.K
    assert(action == "object_actions")
    picker_options.actions[action](picker, person)
    assert(selected_title == "[dbo].[Person]")
    assert(copied == "[dbo].[Person]")

    selected_action = "query"
    picker_options.actions[action](picker, person)
    selected_action = "definition"
    picker_options.actions[action](picker, person)
    assert(vim.wait(1000, function()
      return queried ~= nil and defined ~= nil
    end))
    selected_action = "refresh"
    picker_options.actions[action](picker, person)
    assert(refreshed == person.object)
  end)
end

T["Object explorer covers formatting and defensive tree actions"] = function()
  local picker_options
  local errors = {}
  local refresh_count = 0
  local picker = {
    closed = false,
    matcher = { opts = {} },
    find = function(_, opts)
      assert(opts.refresh)
      refresh_count = refresh_count + 1
    end,
    focus = function() end,
    input = { set = function() end },
  }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return { { "tree" } }
        end,
      },
      pick = function(options)
        picker_options = options
        picker.matcher.opts = options.matcher
        return picker
      end,
    },
  }, function()
    explorer.open({
      connection = { server = "localhost", database = "TestDb" },
      objects = { { id = "person", name = "Person", type = "Table", path = "Tables/" } },
      on_query = function() end,
      on_definition = function() end,
      on_expand = function(_, callback)
        callback({ { id = "column", label = "ID", type = "Column" } })
      end,
      on_refresh = function(callback)
        callback(nil, { message = "refresh failed" })
      end,
      on_error = function(message)
        errors[#errors + 1] = message
      end,
    })

    local items = picker_options.finder()
    picker_options.actions.object_toggle(picker, nil)
    picker_options.actions.object_toggle(picker, items[3])
    local person = picker_options.finder()[4]
    picker_options.actions.object_collapse_all(picker)
    picker_options.actions.object_toggle(picker, picker_options.finder()[3])
    person = picker_options.finder()[4]
    picker_options.actions.object_toggle(picker, person)
    local column = picker_options.finder()[5]
    picker_options.actions.object_toggle(picker, column)

    local formatted = picker_options.format(picker_options.finder()[4], picker)
    assert(#formatted == 4)
    assert(formatted[2][1] == " ")
    assert(formatted[4][1] == "Person")

    picker_options.actions.object_collapse(picker, column)
    assert(#picker_options.finder() == 4)
    picker_options.actions.object_collapse(picker, nil)
    picker_options.actions.object_refresh(picker)
    assert(vim.deep_equal(errors, { "refresh failed" }))
    assert(refresh_count >= 3)
  end)
end

T["Object explorer reports lazy and contextual refresh failures"] = function()
  local picker_options
  local selected_action
  local expansion_callbacks = {}
  local errors = {}
  local picker = { closed = false, matcher = { opts = {} }, refresh = function() end }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      select = function(_, _, callback)
        callback(selected_action)
      end,
      pick = function(options)
        picker_options = options
        return picker
      end,
    },
  }, function()
    explorer.open({
      connection = {},
      objects = { { id = "person", name = "Person", type = "Table", path = "Tables/" } },
      on_expand = function(_, callback)
        expansion_callbacks[#expansion_callbacks + 1] = callback
      end,
      on_error = function(message)
        errors[#errors + 1] = message
      end,
    })
    picker_options.actions.object_toggle(picker, picker_options.finder()[3])
    local person = picker_options.finder()[4]
    picker_options.actions.object_toggle(picker, person)
    expansion_callbacks[1](nil, { message = "expand failed" })

    selected_action = { id = "refresh" }
    picker_options.actions.object_actions(picker, person)
    expansion_callbacks[2](nil, { message = "detail refresh failed" })

    picker_options.actions.object_actions(picker, person)
    picker.closed = true
    expansion_callbacks[3]({})
    assert(vim.deep_equal(errors, { "expand failed", "detail refresh failed" }))
  end)
end

T["Object explorer ignores callbacks after its picker closes"] = function()
  local picker_options
  local expand_callback
  local refresh_callback
  local selected_callback
  local refresh_count = 0
  local picker = {
    closed = false,
    matcher = { opts = {} },
    refresh = function()
      refresh_count = refresh_count + 1
    end,
  }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      select = function(_, _, callback)
        selected_callback = callback
      end,
      pick = function(options)
        picker_options = options
        return picker
      end,
    },
  }, function()
    explorer.open({
      connection = {},
      objects = { { id = "person", name = "Person", type = "Table", path = "Tables/" } },
      on_expand = function(_, callback)
        expand_callback = callback
      end,
      on_refresh = function(callback)
        refresh_callback = callback
      end,
      on_error = error,
    })
    picker_options.actions.object_toggle(picker, picker_options.finder()[3])
    local person = picker_options.finder()[4]
    picker_options.actions.object_toggle(picker, person)
    picker_options.actions.object_actions(picker, person)
    picker_options.actions.object_refresh(picker)

    picker.closed = true
    local refreshes_before_close = refresh_count
    expand_callback({})
    refresh_callback({})
    selected_callback({ id = "query" })
    picker_options.actions.object_expand_all(picker)
    assert(refresh_count == refreshes_before_close)
  end)
end

T["Object explorer dispatches copy-name and ignores empty actions"] = function()
  local picker_options
  local selected_action
  local copied = {}
  local picker = { closed = false, matcher = { opts = {} }, refresh = function() end }
  with_snacks({
    picker = {
      format = {
        tree = function()
          return {}
        end,
      },
      select = function(_, _, callback)
        callback(selected_action)
      end,
      pick = function(options)
        picker_options = options
        return picker
      end,
    },
  }, function()
    explorer.open({
      connection = {},
      objects = { { id = "person", name = "Person", type = "Table", path = "Tables/" } },
      on_copy = function(value)
        copied[#copied + 1] = value
      end,
    })
    picker_options.actions.object_toggle(picker, picker_options.finder()[3])
    local person = picker_options.finder()[4]
    picker_options.actions.object_actions(picker, nil)
    picker_options.actions.object_actions(picker, person)
    selected_action = { id = "copy_name" }
    picker_options.actions.object_actions(picker, person)
    assert(vim.deep_equal(copied, { "Person" }))
  end)
end

T["Object explorer removes closed pickers and close is idempotent"] = function()
  local picker_options
  local configured_close_count = 0
  local picker = {
    closed = false,
    close = function(self)
      self.closed = true
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
        return picker
      end,
    },
  }, function()
    explorer.open({
      bufnr = 9341,
      connection = {},
      objects = {},
      picker = {
        on_close = function(closed)
          assert(closed == picker)
          configured_close_count = configured_close_count + 1
        end,
      },
    })
    picker_options.on_close(picker)
    assert(configured_close_count == 1)
    assert(not explorer.close(9341))

    picker.closed = true
    explorer.open({ bufnr = 9342, connection = {}, objects = {} })
    assert(explorer.close(9342))
  end)
end

return T
