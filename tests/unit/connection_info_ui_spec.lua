local connection_info_ui = require("sqlserver.ui.connection_info")

local T = MiniTest.new_set()

local function find_mapping(bufnr, lhs)
  return vim.iter(vim.api.nvim_buf_get_keymap(bufnr, "n")):find(function(mapping)
    return mapping.lhs == lhs
  end)
end

T["Connection information view renders safe server metadata"] = function()
  local info = {
    username = "app_user",
    server = "localhost",
    database = "ApplicationDb",
    connection_id = "connection-123",
    server_connection_id = "57",
    is_supported_version = true,
    server_info = {
      version = "16.0.1000.6",
      edition = "Developer Edition",
      level = "RTM",
      engine_edition_id = 3,
      is_cloud = false,
      machine_name = "sqlserver",
      os_version = "Linux",
      cpu_count = 8,
      physical_memory_mb = 4096,
    },
  }
  local source_bufnr = vim.api.nvim_create_buf(false, true)
  local workspace = {
    bufnr = source_bufnr,
    get_connection_info = function()
      return vim.deepcopy(info)
    end,
  }

  connection_info_ui.setup({ height = 10 })
  local bufnr = connection_info_ui.show(workspace)
  local contents = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  assert(vim.bo[bufnr].filetype == "sqlserver-connection")
  assert(vim.bo[bufnr].buftype == "nofile")
  assert(vim.bo[bufnr].modifiable == false)
  assert(vim.bo[bufnr].readonly == true)
  assert(contents:find("Username          app_user", 1, true))
  assert(contents:find("Session ID        57", 1, true))
  assert(contents:find("Supported         Yes", 1, true))
  assert(contents:find("Version           16.0.1000.6", 1, true))
  assert(contents:find("Cloud             No", 1, true))
  assert(contents:find("Physical memory   4096 MB", 1, true))
  assert(not contents:lower():find("password", 1, true))
  assert(not contents:lower():find("token", 1, true))

  assert(find_mapping(bufnr, "r").desc == "Refresh SQL Server connection information")
  assert(find_mapping(bufnr, "q").desc == "Close SQL Server connection information")
  assert(find_mapping(bufnr, "?").desc == "Show connection information mappings")
  assert(vim.api.nvim_win_get_height(0) == 10)

  info.database = "ChangedDb"
  assert(connection_info_ui.render(source_bufnr))
  contents = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  assert(contents:find("Database          ChangedDb", 1, true))

  vim.api.nvim_buf_delete(source_bufnr, { force = true })
  assert(not vim.api.nvim_buf_is_valid(bufnr), "Deleting the SQL source must dispose its connection information")
end

T["Connection information view handles unavailable metadata"] = function()
  local lines = connection_info_ui.format_lines({
    get_connection_info = function()
      return { server = "localhost", server_info = {} }
    end,
  })
  local contents = table.concat(lines, "\n")
  assert(contents:find("Username          —", 1, true))
  assert(contents:find("Server            localhost", 1, true))
  assert(contents:find("Session ID        —", 1, true))
end

T["Connection information view sizes itself from its source window"] = function()
  local source_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(source_bufnr)
  local source_height = vim.api.nvim_win_get_height(0)
  local workspace = {
    bufnr = source_bufnr,
    get_connection_info = function()
      return { server = "localhost", server_info = {} }
    end,
  }
  local expected = math.min(#connection_info_ui.format_lines(workspace), math.max(1, math.floor(source_height * 0.5)))

  connection_info_ui.setup({ height = "auto" })
  local bufnr = connection_info_ui.show(workspace)
  assert(vim.api.nvim_win_get_height(0) == expected)

  vim.api.nvim_buf_delete(source_bufnr, { force = true })
  assert(not vim.api.nvim_buf_is_valid(bufnr))
end

return T
