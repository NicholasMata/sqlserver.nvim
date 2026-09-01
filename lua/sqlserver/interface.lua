-- Handles how the user user interfaces with this plugin, i.e. keymaps and user commands
local utils = require("sqlserver.utils")
local workspace_module = require("sqlserver.core.workspace")
local workspace_registry = require("sqlserver.core.workspace_registry")

return {
  set_keymaps = function(prefix, M)
    if not prefix then
      return
    end

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
            return with_activity({
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
            })
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
          local save_result = {
            "s",
            M.save_query_results,
            desc = "Save Query Results",
            icon = { icon = "", color = "green" },
          }

          return { save_result, keymaps.new_query, keymaps.new_default_query, keymaps.edit_connections }
        else
          return { keymaps.new_query, keymaps.new_default_query, keymaps.edit_connections }
        end
      end

      wk.add(normal_group)

      local visual_group = vim.tbl_deep_extend("keep", wkeygroup, {})
      visual_group.mode = "v"
      visual_group.expand = function()
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
        if vim.b.query_result_info then
          M.save_query_results()
        else
          M.switch_database()
        end
      end)
    end
  end,

  set_user_commands = function(M)
    local commands = {
      Activity = M.toggle_activity,
      Connect = M.connect,
      Reconnect = M.reconnect,
      Disconnect = M.disconnect,
      BackupDatabase = M.backup_database,
      RestoreDatabase = M.restore_database,
      ExecuteQuery = M.execute_query,
      ExecuteBuffer = M.execute_buffer,
      RefreshCache = M.refresh_cache,
      EditConnections = M.edit_connections,
      SwitchDatabase = M.switch_database,
      NewQuery = M.new_query,
      NewDefaultQuery = M.new_default_query,
      SaveQueryResults = M.save_query_results,
      NextResult = M.next_result,
      PreviousResult = M.previous_result,
      Find = M.find_object,
      ObjectDefinition = M.show_object_definition,
      CancelQuery = M.cancel_query,
    }

    local complete = function(_, _, _)
      local workspace = workspace_registry.get()
      if vim.b.query_result_info then
        return {
          "NewQuery",
          "NewDefaultQuery",
          "EditConnections",
          "SaveQueryResults",
          "NextResult",
          "PreviousResult",
        }
      elseif not workspace then
        return {
          "NewQuery",
          "NewDefaultQuery",
          "EditConnections",
        }
      end

      local state = workspace.get_state()
      local states = workspace_module.states
      local function with_activity(items)
        table.insert(items, 1, "Activity")
        return items
      end
      if state == states.connecting then
        return with_activity({
          "NewQuery",
          "NewDefaultQuery",
          "EditConnections",
        })
      elseif state == states.executing then
        return with_activity({
          "NewQuery",
          "NewDefaultQuery",
          "EditConnections",
          "CancelQuery",
        })
      elseif state == states.connected then
        return with_activity({
          "NewQuery",
          "NewDefaultQuery",
          "EditConnections",
          "RefreshCache",
          "ExecuteQuery",
          "ExecuteBuffer",
          "Disconnect",
          "SwitchDatabase",
          "BackupDatabase",
          "RestoreDatabase",
          "Find",
          "ObjectDefinition",
        })
      elseif state == states.disconnected then
        local items = {
          "NewQuery",
          "NewDefaultQuery",
          "EditConnections",
          "Connect",
        }
        if workspace.can_reconnect() then
          table.insert(items, "Reconnect")
        end
        return with_activity(items)
      elseif state == states.cancelling then
        return with_activity({
          "NewQuery",
          "NewDefaultQuery",
          "EditConnections",
        })
      else
        utils.log_error("Entered unrecognised query state: " .. state)
        return {}
      end
    end

    vim.api.nvim_create_user_command("SQLServer", function(args)
      local command = commands[args.args]
      if not command then
        error("No such command " .. args.args, 0)
      end
      command()
    end, { nargs = 1, complete = complete })
  end,
}
