-- Handles how the user user interfaces with this plugin, i.e. keymaps and user commands
local utils = require("sqlserver.utils")
local workspace_module = require("sqlserver.workspace")
local workspace_registry = require("sqlserver.workspace.registry")
local query_results = require("sqlserver.results.ui.view")
local result_keymaps = require("sqlserver.results.ui.keymaps")

return {
  set_keymaps = function(prefix, M)
    if not prefix then
      return
    end

    result_keymaps.setup(prefix, M)

    local keymaps = {
      activity = { "a", M.toggle_activity, desc = "Activity", icon = { icon = "󰋼", color = "blue" } },
      new_query = { "n", M.new_query, desc = "New Query", icon = { icon = "", color = "yellow" } },
      connect = { "c", M.connect, desc = "Connect", icon = { icon = "󱘖", color = "green" } },
      reconnect = { "R", M.reconnect, desc = "Reconnect", icon = { icon = "󰑓", color = "yellow" } },
      disconnect = { "q", M.disconnect, desc = "Disconnect", icon = { icon = "", color = "red" } },
      cancel_query = { "l", M.cancel_query, desc = "Cancel Query", icon = { icon = "", color = "red" } },
      execute_query = {
        "x",
        M.execute_query,
        desc = "Execute Query",
        mode = { "n", "v" },
        icon = { icon = "", color = "green" },
      },
      execute_buffer = {
        "X",
        M.execute_buffer,
        desc = "Execute Buffer",
        icon = { icon = "", color = "green" },
      },
      edit_connections = {
        "e",
        M.edit_connections,
        desc = "Edit Connections",
        icon = { icon = "󰅩", color = "grey" },
      },
      refresh_cache = {
        "r",
        M.refresh_cache,
        desc = "Refresh Cache",
        icon = { icon = "", color = "grey" },
      },
      new_default_query = {
        "d",
        M.new_default_query,
        desc = "New Default Query",
        icon = { icon = "", color = "yellow" },
      },
      find_object = {
        "f",
        M.find_object,
        desc = "Find Query",
        icon = { icon = "", color = "green" },
      },
      object_definition = {
        "o",
        M.show_object_definition,
        desc = "Object Definition",
        icon = { icon = "󰈙", color = "blue" },
      },
      show_results = {
        "v",
        M.show_results,
        desc = "Show Results",
        icon = { icon = "󰦨", color = "blue" },
      },
    }

    local success, wk = pcall(require, "which-key")
    if success then
      local function with_activity(items)
        table.insert(items, 1, keymaps.activity)
        return items
      end

      local wkeygroup = {
        prefix,
        group = "sqlserver",
        icon = { icon = "", color = "yellow" },
      }

      local normal_group = vim.tbl_deep_extend("keep", wkeygroup, {})
      normal_group.expand = function()
        local workspace = workspace_registry.get()
        if workspace then
          local state = workspace.get_state()
          local states = workspace_module.states
          if state == states.connecting then
            return with_activity({
              keymaps.new_query,
              keymaps.new_default_query,
              keymaps.edit_connections,
            })
          elseif state == states.executing then
            return with_activity({
              keymaps.new_query,
              keymaps.new_default_query,
              keymaps.edit_connections,
              keymaps.cancel_query,
            })
          elseif state == states.connected then
            local items = {
              keymaps.new_query,
              keymaps.new_default_query,
              keymaps.edit_connections,
              keymaps.refresh_cache,
              keymaps.execute_query,
              keymaps.execute_buffer,
              keymaps.disconnect,
              {
                "s",
                M.switch_database,
                desc = "Switch Database",
                icon = { icon = "", color = "yellow" },
              },
              keymaps.find_object,
              keymaps.object_definition,
            }
            if query_results.has_results(workspace.bufnr) then
              table.insert(items, keymaps.show_results)
            end
            return with_activity(items)
          elseif state == states.disconnected then
            local items = {
              keymaps.new_query,
              keymaps.new_default_query,
              keymaps.edit_connections,
              keymaps.connect,
              {
                "x",
                M.execute_query,
                desc = "Execute On Default",
                mode = { "n", "v" },
                icon = { icon = "", color = "green" },
              },
              {
                "X",
                M.execute_buffer,
                desc = "Execute Buffer On Default",
                icon = { icon = "", color = "green" },
              },
            }
            if workspace.can_reconnect() then
              table.insert(items, keymaps.reconnect)
            end
            if query_results.has_results(workspace.bufnr) then
              table.insert(items, keymaps.show_results)
            end
            return with_activity(items)
          elseif state == states.cancelling then
            return with_activity({
              keymaps.new_query,
              keymaps.new_default_query,
              keymaps.edit_connections,
            })
          else
            utils.log_error("Entered unrecognised query state: " .. state)
            return {}
          end
        elseif vim.b.query_result_info then
          return result_keymaps.which_key_items(M)
        else
          local items = { keymaps.new_query, keymaps.new_default_query, keymaps.edit_connections }
          if query_results.has_results() then
            table.insert(items, keymaps.show_results)
          end
          return items
        end
      end

      wk.add(normal_group)

      local visual_group = vim.tbl_deep_extend("keep", wkeygroup, {})
      visual_group.mode = "v"
      visual_group.expand = function()
        if vim.b.query_result_info then
          return result_keymaps.which_key_visual_items(M)
        end
        local workspace = workspace_registry.get()
        if not workspace then
          return { keymaps.new_query, keymaps.new_default_query, keymaps.edit_connections }
        end

        local state = workspace.get_state()
        local states = workspace_module.states
        if state == states.connecting or state == states.executing or state == states.disconnected then
          return {}
        elseif state == states.connected then
          return { keymaps.execute_query }
        else
          utils.log_error("Entered unrecognised query state: " .. state)
          return {}
        end
      end

      wk.add(visual_group)
    else
      for _, m in pairs(keymaps) do
        vim.keymap.set(m.mode or "n", prefix .. m[1], m[2], { desc = m.desc })
      end
      vim.keymap.set("n", prefix .. "s", function()
        M.switch_database()
      end, { desc = "Switch Database" })
    end
  end,
}
