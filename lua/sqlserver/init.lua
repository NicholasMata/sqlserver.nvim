local tools_installer = require("sqlserver.adapters.sql_tools_service.installer")
local utils = require("sqlserver.utils")
local query_results = require("sqlserver.results.ui.view")
local result_export_view = require("sqlserver.results.ui.export")
local query_selection = require("sqlserver.queries.selection")
local sql_keymaps = require("sqlserver.ui.keymaps")
local commands = require("sqlserver.ui.commands")
local default_opts = require("sqlserver.config.defaults")
local finder = require("sqlserver.objects.ui.picker")
local sql_tools_service = require("sqlserver.adapters.sql_tools_service.client")
local query_backend = require("sqlserver.adapters.sql_tools_service.query")
local workspace_module = require("sqlserver.workspace")
local workspace_registry = require("sqlserver.workspace.registry")
local activity_stream = require("sqlserver.workspace.activity_stream").create({ on_error = utils.log_error })
local activity_ui = require("sqlserver.ui.activity")
local ui_options = require("sqlserver.config.ui")
local status_ui = require("sqlserver.ui.status")
local timeout_options = require("sqlserver.config.timeouts")
local connection_profiles = require("sqlserver.connections.profiles")
local public_api = require("sqlserver.api")

local joinpath = vim.fs.joinpath
local workspace_winbar_expression = "%{%v:lua.require'sqlserver.ui.status'.winbar()%}"
local result_winbar_expression = "%{%v:lua.require'sqlserver.results.ui.view'.winbar()%}"
local custom_presenter_unsubscribe

local function apply_winbar(bufnr, opts)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    local current = vim.api.nvim_get_option_value("winbar", { win = winid })
    local desired
    if opts.ui.presenter == "default" and opts.ui.winbar.enabled then
      if workspace_registry.get(bufnr) then
        desired = workspace_winbar_expression
      elseif query_results.is_result_buffer(bufnr) then
        desired = result_winbar_expression
      end
    end
    local current_is_sqlserver = current == workspace_winbar_expression or current == result_winbar_expression
    if desired then
      if not current_is_sqlserver then
        vim.w[winid].sqlserver_previous_winbar = current
      end
      vim.api.nvim_set_option_value("winbar", desired, { win = winid })
    elseif current_is_sqlserver then
      local previous = vim.w[winid].sqlserver_previous_winbar or ""
      vim.api.nvim_set_option_value("winbar", previous, { win = winid })
      vim.w[winid].sqlserver_previous_winbar = nil
    end
  end
end

-- creates the directory if it doesn't exist
local function make_directory(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

local function read_json_file(path)
  local file = io.open(path, "r")
  if not file then
    return {}
  end
  local content = file:read("*a")
  file:close()
  return vim.json.decode(content)
end

local function write_json_file(path, table)
  local file = io.open(path, "w")
  local text = vim.json.encode(table)
  if file then
    file:write(text)
    file:close()
  else
    error("Could not open file: " .. path, 0)
  end
end

local function clean_cache()
  local in_use_connections = {}
  for bufnr, workspace in workspace_registry.iter() do
    local connection = workspace.get_connection()
    if vim.api.nvim_buf_is_loaded(bufnr) and connection then
      table.insert(in_use_connections, connection)
    end
  end
  finder.delete_unused_cache(in_use_connections)
end

local function enable_lsp(opts)
  sql_tools_service.enable(opts, {
    on_query_message = function(message, is_error, owner_uri, error_selection)
      local workspace = workspace_registry.find_by_owner_uri(owner_uri)
      local is_cancellation_message = is_error
        and workspace
        and workspace.get_state() == workspace_module.states.cancelling
      if workspace then
        workspace.record_message(message, is_error and not is_cancellation_message, error_selection)
      end
      if is_cancellation_message then
        return
      end
      if is_error then
        utils.log_error(message)
      end
      opts.view_messages_in(message, is_error, error_selection)
    end,
    on_connection_changed = function(result)
      local workspace = workspace_registry.find_by_owner_uri(result.ownerUri)
      if not (result.connection and workspace) then
        return
      end

      coroutine.resume(coroutine.create(function()
        workspace.connection_changed_async(result)
      end))

      clean_cache()
    end,
    on_attach = function(client, bufnr)
      if not workspace_registry.get(bufnr) then
        local workspace = workspace_module.create({
          bufnr = bufnr,
          backend = query_backend.create(bufnr, client, opts.timeouts),
          objects = finder,
          activity_stream = activity_stream,
        })
        workspace_registry.attach(bufnr, workspace)
        apply_winbar(bufnr, opts)
      end
    end,
    on_exit = function(code, signal)
      if code ~= 0 or signal ~= 0 then
        utils.log_error(string.format("SQL Tools Service stopped unexpectedly (exit %d, signal %d)", code, signal))
      end
    end,
  })
end

local function ensure_sql_buffer_name(bufnr)
  if vim.api.nvim_buf_get_name(bufnr) ~= "" then
    return false
  end

  vim.api.nvim_buf_set_name(bufnr, vim.fs.abspath(("untitled-%d.sql"):format(bufnr)))
  vim.b[bufnr].is_temp_name = true
  return true
end

local function set_auto_commands(opts)
  vim.api.nvim_create_augroup("AutoNameSQL", { clear = true })

  -- Reset the buffer to the file name upon saving
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = "AutoNameSQL",
    pattern = "*.sql",
    callback = function(args)
      local buf = args.buf
      if vim.b[buf].is_temp_name then
        local written_name = vim.fn.fnamemodify(vim.fn.expand("<afile>"), ":t")

        vim.cmd("file " .. written_name)
        vim.b[buf].is_temp_name = nil
      end
    end,
  })

  local function configure_sql_buffer(bufnr)
    ensure_sql_buffer_name(bufnr)
    for option, value in pairs(opts.sql_buffer_options or {}) do
      vim.api.nvim_set_option_value(option, value, { buf = bufnr })
    end
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = "AutoNameSQL",
    pattern = "sql",
    callback = function(args)
      configure_sql_buffer(args.buf)
    end,
  })

  -- FileType may already have fired when setup() is called from an SQL buffer.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "sql" then
      configure_sql_buffer(bufnr)
    end
  end

  -- Release the SQL Tools Service connection and object cache with the buffer.
  vim.api.nvim_create_autocmd("BufDelete", {
    group = "AutoNameSQL",
    callback = function(args)
      local workspace = workspace_registry.detach(args.buf)
      if workspace then
        coroutine.resume(coroutine.create(function()
          workspace.dispose_async()
          clean_cache()
        end))
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = "AutoNameSQL",
    callback = function(args)
      apply_winbar(args.buf, opts)
    end,
  })
end

local plugin_opts

local sqlserver_window
local show_results_buffer_options = {
  current_window = function(bufnr)
    vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr })
    vim.api.nvim_set_current_buf(bufnr)
  end,
  split = function(bufnr)
    local original_window = vim.api.nvim_get_current_win()

    -- open a split if we haven't done already
    if
      not (sqlserver_window and vim.api.nvim_win_is_valid(sqlserver_window)) or sqlserver_window == original_window
    then
      vim.cmd("split")
      sqlserver_window = vim.api.nvim_get_current_win()
    end

    vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr })
    vim.api.nvim_win_set_buf(sqlserver_window, bufnr)
    vim.api.nvim_set_current_win(original_window)
  end,
  vsplit = function(bufnr)
    local original_window = vim.api.nvim_get_current_win()

    -- open a split if we haven't done already
    if
      not (sqlserver_window and vim.api.nvim_win_is_valid(sqlserver_window)) or sqlserver_window == original_window
    then
      vim.cmd("vsplit")
      sqlserver_window = vim.api.nvim_get_current_win()
    end

    vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr })
    vim.api.nvim_win_set_buf(sqlserver_window, bufnr)
    vim.api.nvim_set_current_win(original_window)
  end,
}

-- If the open_results_in is a string, sets it to the appropriate function
local function set_show_results_option(opts)
  if type(opts.open_results_in) == "string" and show_results_buffer_options[opts.open_results_in] then
    opts.open_results_in = show_results_buffer_options[opts.open_results_in]
  elseif type(opts.open_results_in) == "function" then
    return
  else
    utils.log_error(
      vim.inspect(opts.open_results_in)
        .. " is not a valid option for open_results_in. Must be one of: "
        .. table.concat(vim.tbl_keys(show_results_buffer_options), ", ")
        .. ", or a function"
    )
  end
end

local message_buffer
local message_buffer_error_ns = vim.api.nvim_create_namespace("sqlserver_error_highlight")
local clear_message_buffer = function()
  if message_buffer and vim.api.nvim_buf_is_valid(message_buffer) then
    vim.api.nvim_set_option_value("modifiable", true, { buf = message_buffer })
    vim.api.nvim_buf_set_lines(message_buffer, 0, -1, false, {})
    vim.api.nvim_set_option_value("modifiable", false, { buf = message_buffer })
  end
end

local view_message_options = {
  activity = function() end,
  notification = function(message, is_error)
    if not is_error then
      utils.log_info(message)
    end
  end,
  buffer = function(message, is_error)
    if not (message_buffer and vim.api.nvim_buf_is_valid(message_buffer)) then
      message_buffer = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(message_buffer, "sql messages")
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = message_buffer })
      vim.api.nvim_set_option_value("bufhidden", "hide", { buf = message_buffer })
      vim.api.nvim_set_option_value("swapfile", false, { buf = message_buffer })
      vim.api.nvim_set_option_value("readonly", true, { buf = message_buffer })
      vim.api.nvim_set_option_value("modifiable", false, { buf = message_buffer })
      plugin_opts.open_results_in(message_buffer)
    end
    -- Append a line at the end
    local lines = vim.api.nvim_buf_line_count(message_buffer)
    vim.api.nvim_set_option_value("modifiable", true, { buf = message_buffer })
    local message_lines = vim.split(message:gsub("\r", ""), "\n")
    vim.api.nvim_buf_set_lines(message_buffer, lines, lines, false, message_lines)

    -- Apply the 'Error' highlight group to the line
    if is_error then
      vim.api.nvim_buf_set_extmark(message_buffer, message_buffer_error_ns, lines, 0, {
        end_row = lines + #message_lines,
        hl_group = "Error",
      })
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = message_buffer })
  end,
}

-- if the view_messages_in option is a string, sets it to the appropriate function
local function set_view_message_option(opts)
  if type(opts.view_messages_in) == "string" and view_message_options[opts.view_messages_in] then
    opts.view_messages_in = view_message_options[opts.view_messages_in]
  elseif type(opts.view_messages_in) == "function" then
    return
  else
    utils.log_error(
      vim.inspect(opts.view_messages_in)
        .. " is not a valid option for view_messages_in. Must be one of: "
        .. table.concat(vim.tbl_keys(view_message_options), ", ")
        .. ", or a function"
    )
  end
end

local function setup_async(opts)
  opts = opts or {}
  opts = vim.tbl_deep_extend("keep", opts or {}, default_opts)
  if type(opts.results.sticky_header) ~= "boolean" then
    error("results.sticky_header must be true or false", 0)
  end
  if
    type(opts.results.history_limit) ~= "number"
    or opts.results.history_limit < 1
    or opts.results.history_limit % 1 ~= 0
  then
    error("results.history_limit must be a positive integer", 0)
  end
  opts.timeouts = timeout_options.normalize(opts.timeouts)
  finder.setup(opts.timeouts)
  query_results.setup(opts.results)
  opts.ui.winbar = ui_options.normalize_winbar(opts.ui.winbar)
  opts.connections_file = opts.connections_file or joinpath(opts.data_dir, "connections.json")
  set_show_results_option(opts)
  set_view_message_option(opts)
  if custom_presenter_unsubscribe then
    custom_presenter_unsubscribe()
    custom_presenter_unsubscribe = nil
  end
  activity_ui.setup(opts.ui)
  if opts.ui.presenter == "default" then
    status_ui.setup(opts.ui.winbar)
    activity_ui.setup(opts.ui, activity_stream)
  elseif type(opts.ui.presenter) == "function" then
    custom_presenter_unsubscribe = activity_stream.subscribe(opts.ui.presenter)
  elseif opts.ui.presenter ~= false then
    error("ui.presenter must be 'default', false, or a function", 0)
  end

  make_directory(opts.data_dir)

  -- if the opts specify a tools file path, don't download.
  if opts.tools_file then
    if vim.fn.filereadable(opts.tools_file) == 0 then
      error("SQL Tools Service executable was not found at " .. opts.tools_file, 0)
    end
    if vim.fn.executable(opts.tools_file) == 0 then
      error("SQL Tools Service file is not executable: " .. opts.tools_file, 0)
    end
  else
    local config_file = joinpath(opts.data_dir, "config.json")
    local config = read_json_file(config_file)
    local release = tools_installer.get_release(opts.tools_version)
    local tools_file = sql_tools_service.default_executable(opts)

    -- download if it's a first time setup or the last downloaded is old
    if
      vim.fn.filereadable(tools_file) == 0
      or vim.fn.executable(tools_file) == 0
      or config.tools_version ~= release.version
    then
      local downloaded, err = tools_installer.download_tools_async(release, opts.data_dir)
      if not downloaded then
        error("Could not install SQL Tools Service: " .. (err or "unknown error"), 0)
      end
      config.tools_version = release.version
      config.last_downloaded_from = nil
      write_json_file(config_file, config)
    end
  end

  set_auto_commands(opts)
  enable_lsp(opts)
  for bufnr in workspace_registry.iter() do
    apply_winbar(bufnr, opts)
  end

  plugin_opts = opts
  public_api.configure(opts)
end

local edit_connections = function(opts)
  if vim.fn.filereadable(opts.connections_file) == 0 then
    utils.log_info("Connections json file not found. Creating...")
    local default_connections = [=[
{
  "Example (edit this)": {
    "server": "localhost",
    "database": "master",
    "authenticationType" : "SqlLogin",
    "user" : "Admin",
    "password" : "Your_Password",
    "trustServerCertificate" : true
  }
}
]=]
    vim.fn.writefile(vim.split(default_connections, "\n"), opts.connections_file)
  end
  vim.cmd.edit(opts.connections_file)
end

local function get_connections(opts)
  return connection_profiles.load(opts.connections_file)
end

local function prepare_connection(profile, name)
  local connection = connection_profiles.resolve(profile, name)
  if connection.promptForPassword then
    connection.password = vim.fn.inputsecret("password for " .. (connection.server or ""))
  end
  connection_profiles.validate(connection, name)
  return connection
end

local function await_public(invoke)
  local co = coroutine.running()
  local completed = false
  local result
  local api_err
  invoke(function(value, err)
    completed = true
    result = value
    api_err = err
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co)
    end
  end)
  if not completed then
    coroutine.yield()
  end
  if api_err then
    error(api_err.message, 0)
  end
  return result
end

local function switch_database_async(buf)
  if buf == nil then
    buf = vim.api.nvim_get_current_buf()
  end
  local workspace = workspace_registry.get(buf)
  if not workspace then
    error("No SQL Server lsp is attached. Create a new query or open an exising one.", 0)
  end
  if workspace.get_state() ~= workspace_module.states.connected then
    error("You need to connect first", 0)
  end

  local db = utils.ui_select_async(workspace.list_databases_async(), { prompt = "Choose database" })
  utils.safe_assert(db, "No database chosen")

  -- get the connect params first, because they get set
  -- to nil when we disconnect
  local connect_params = workspace.get_connect_params()
  -- disconnect, change the database and connect again
  workspace.disconnect_async()

  connect_params.connection.options.database = db

  workspace.connect_async(connect_params)
end

local connect_async = function(opts, workspace)
  local json = get_connections(opts)
  if not json then
    edit_connections(opts)
    return false
  end

  local con_name = utils.ui_select_async(vim.tbl_keys(json), { prompt = "Choose connection" })
  if not con_name then
    utils.log_info("No connection chosen")
    return false
  end

  local con = prepare_connection(json[con_name], con_name)

  await_public(function(callback)
    public_api.connect(con, { bufnr = workspace.bufnr, profile_name = con_name, refresh_objects = false }, callback)
  end)

  if con.promptForDatabase then
    switch_database_async()
  end
  return true
end

local function new_query_async(name)
  -- The language server requires all files to have a unique name.
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  if name then
    vim.api.nvim_buf_set_name(buf, vim.fs.abspath(name))
  else
    ensure_sql_buffer_name(buf)
  end
  vim.cmd("setfiletype sql")
  vim.b[buf].is_temp_name = true

  local client = sql_tools_service.wait_for_attach_async(buf, plugin_opts.timeouts.lsp_attach)
  return buf, client
end

local function sanitized_definition_name(object)
  local qualified_name = object.schema and object.schema ~= "" and (object.schema .. "." .. object.name) or object.name
  return (qualified_name:gsub('[<>:"/\\|?*%c]', "_")) .. ".sql"
end

local function buffer_named(name)
  return vim.iter(vim.api.nvim_list_bufs()):find(function(bufnr)
    return vim.api.nvim_buf_is_valid(bufnr) and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t") == name
  end)
end

local function focus_buffer(bufnr)
  local windows = vim.fn.win_findbuf(bufnr)
  if #windows > 0 then
    vim.api.nvim_set_current_win(windows[1])
  else
    vim.api.nvim_set_current_buf(bufnr)
  end
end

local function unique_definition_name(name)
  if not buffer_named(name) then
    return name
  end
  local stem = name:gsub("%.sql$", "")
  local index = 2
  while buffer_named(string.format("%s (%d).sql", stem, index)) do
    index = index + 1
  end
  return string.format("%s (%d).sql", stem, index)
end

local function open_object_definition_async(source_workspace, item)
  local name = sanitized_definition_name(item.object)
  local existing = buffer_named(name)
  if existing then
    local choice = utils.ui_select_async({ "Focus open buffer", "Open another buffer" }, {
      prompt = name .. " is already open",
    })
    if choice == "Focus open buffer" then
      focus_buffer(existing)
      return existing
    elseif choice ~= "Open another buffer" then
      return nil
    end
    name = unique_definition_name(name)
  end

  local connect_params = source_workspace.get_connect_params()
  local connection = connect_params and connect_params.connection and connect_params.connection.options or {}
  local bufnr = new_query_async(name)
  local definition_workspace = workspace_registry.get(bufnr)
  definition_workspace.connect_async(connect_params)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(item.script, "\n"))
  vim.b[bufnr].sqlserver_object = {
    server = connection.server,
    database = connection.database,
    id = item.object.id,
    schema = item.object.schema,
    name = item.object.name,
    type = item.object.type,
  }
  return bufnr
end

local function new_default_query_async(opts)
  utils.wait_for_schedule_async()

  local connections = get_connections(opts)
  if not (connections and connections.default) then
    utils.log_info("Add a connection called 'default'")
    edit_connections(opts)
    return
  end
  local connection = prepare_connection(connections.default, "default")

  local buf = new_query_async()
  local workspace = workspace_registry.get(buf)
  if not workspace then
    error("CRITICAL: Lsp attached without a SQL workspace")
  end

  await_public(function(callback)
    public_api.connect(
      connection,
      { bufnr = workspace.bufnr, profile_name = "default", refresh_objects = false },
      callback
    )
  end)

  if connection.promptForDatabase then
    switch_database_async(buf)
  end
  workspace.initialise_objects_async()
end

--- If the current buffer is empty, put the query into this buffer. Otherwise,
--- Open a new buffer with the same connection and put the query there
local function insert_query_into_buffer(query)
  if vim.trim(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false))) == "" then
    vim.api.nvim_buf_set_lines(0, 0, 0, false, vim.split(query, "\n"))
    return 0
  end

  local workspace = workspace_registry.get()
  if not workspace then
    error("Connect to a database first", 0)
  end

  local connect_params = workspace.get_connect_params()
  local buf = new_query_async()
  workspace = workspace_registry.get(buf)
  workspace.connect_async(connect_params)
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, vim.split(query, "\n"))
  return buf
end

local function backup_database_async(workspace)
  if workspace.get_state() ~= workspace_module.states.connected then
    error("Connect to a database first", 0)
  end
  local connect_params = workspace.get_connect_params()
  if
    not (
      connect_params
      and connect_params.connection
      and connect_params.connection.options
      and connect_params.connection.options.database
    )
  then
    error("No connection found", 0)
  end
  local database = connect_params.connection.options.database
  local dir = vim.fs.joinpath(vim.fn.getcwd(), database .. ".bak")
  local query = string.format(
    [[BACKUP DATABASE [%s]
-- Change to your backup location
TO DISK = N'%s'
WITH 
INIT, -- Remove if not overwriting
STATS = 25]],
    database,
    dir
  )

  insert_query_into_buffer(query)
end

local function restore_database_async(workspace)
  if workspace.get_state() ~= workspace_module.states.connected then
    error("Connect to a server first", 0)
  end

  local file = vim.fn.input("Enter .bak file path:", "", "file")
  if not file or file == "" then
    error("No file chosen", 0)
  end

  local internal_files = utils.get_query_result_async(
    workspace.execute_async({ kind = "buffer", text = "RESTORE FILELISTONLY FROM DISK = '" .. file .. "'" })
  )

  local headers = utils.get_query_result_async(
    workspace.execute_async({ kind = "buffer", text = "RESTORE HEADERONLY FROM DISK = '" .. file .. "'" })
  )[1]

  local database = headers.DatabaseName

  local size = tonumber(headers.BackupSize)
  local stats = 25
  if size <= 2000000000 then -- <= 2GB
    stats = 25
  else
    stats = 10
  end

  local data_path = utils.get_query_result_async(workspace.execute_async({
    kind = "buffer",
    text = "SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS DefaultDataPath",
  }))[1].DefaultDataPath

  local moves = vim
    .iter(internal_files)
    :map(function(file)
      return "MOVE N'"
        .. file.LogicalName
        .. "' TO N'"
        .. vim.fs.joinpath(data_path, vim.fs.basename(file.PhysicalName))
        .. "',"
    end)
    :join("\n")

  local query = string.format(
    [[-- WARNING: Read and understand this before executing!
USE [master]
ALTER DATABASE [%s] SET SINGLE_USER WITH ROLLBACK IMMEDIATE -- drop connections
RESTORE DATABASE [%s] FROM  DISK = N'%s' WITH
FILE = 1,
%s
REPLACE, -- overwrite existing
STATS = %s
ALTER DATABASE [%s] SET MULTI_USER]],
    database,
    database,
    file,
    moves,
    stats,
    database
  )

  insert_query_into_buffer(query)
end

local function connect_to_default(workspace, opts)
  utils.wait_for_schedule_async()

  local connections = get_connections(opts)
  if not (connections and connections.default) then
    utils.log_info("Add a connection called 'default'")
    edit_connections(opts)
    return
  end

  local connection = prepare_connection(connections.default, "default")

  await_public(function(callback)
    public_api.connect(
      connection,
      { bufnr = workspace.bufnr, profile_name = "default", refresh_objects = false },
      callback
    )
  end)

  if connection.promptForDatabase then
    switch_database_async()
  end
end

local function export_to_file_async(result_info, selection, extension, file, notify)
  local subset_params = result_info.subset_params
  local existing = vim.uv.fs_stat(file)
  if existing and existing.type ~= "file" then
    utils.log_error("Export path exists and is not a file: " .. file)
    return
  end
  if existing then
    local choice = utils.ui_select_async({ "Overwrite", "Cancel" }, {
      prompt = "Export file already exists. Replace it?",
    })
    if choice ~= "Overwrite" then
      return
    end
  end

  await_public(function(callback)
    public_api.export_results({
      result_set = { locator = subset_params },
      path = file,
      format = extension,
      selection = selection,
    }, callback)
  end)

  if notify ~= false then
    utils.log_info("Exported query results to " .. file)
  end
end

local function save_excel_results_async(result_info, selection)
  local file = utils.ui_input_async({
    prompt = "Export Excel filename: ",
    completion = "file",
  })
  if file == nil then
    return
  end
  if file == "" then
    utils.log_error("Enter a filename to export the query results")
    return
  end
  if file:lower():sub(-5) ~= ".xlsx" then
    utils.log_error("Excel export filename must end with .xlsx")
    return
  end
  export_to_file_async(result_info, selection, "xlsx", file)
end

local function open_text_results_async(result_info, selection, format)
  local path = vim.fn.tempname() .. "." .. format
  local ok, err = pcall(function()
    export_to_file_async(result_info, selection, format, path, false)
    result_export_view.open(path, format, result_info)
  end)
  vim.fn.delete(path)
  if not ok then
    error(err, 0)
  end
  utils.log_info("Opened query results as " .. format:upper())
end

local function export_query_results_async(result_info, selection)
  utils.wait_for_schedule_async()
  local format = utils.ui_select_async({ "csv", "json", "xml", "xlsx" }, {
    prompt = "Open query results as:",
    format_item = function(item)
      return item == "xlsx" and "Excel (.xlsx)" or item:upper()
    end,
  })
  if not format then
    return
  end
  if format == "xlsx" then
    save_excel_results_async(result_info, selection)
  else
    open_text_results_async(result_info, selection, format)
  end
end

local command_handlers = {
  new_query = function()
    utils.try_resume(coroutine.create(function()
      new_query_async()
    end))
  end,

  -- Look for the connection called "default", prompt to choose a database in that server,
  -- connect to that database and open a new buffer for querying (very useful!)
  new_default_query = function()
    utils.try_resume(coroutine.create(function()
      new_default_query_async(plugin_opts)
    end))
  end,

  -- Prompts for a database to switch to that is on the currently
  -- connected server
  switch_database = function(callback)
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    utils.try_resume(coroutine.create(function()
      switch_database_async()
      workspace.initialise_objects_async()
      clean_cache()
      if callback then
        callback()
      end
    end))
  end,

  -- Connect the current buffer (you'll be prompted to choose a connection)
  connect = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    utils.try_resume(coroutine.create(function()
      if connect_async(plugin_opts, workspace) then
        workspace.initialise_objects_async()
      end
    end))
  end,

  reconnect = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server workspace is attached to this buffer")
      return
    end
    public_api.reconnect(workspace.bufnr, function(_, err)
      if err then
        utils.log_error(err.message)
      end
    end)
  end,

  edit_connections = function()
    edit_connections(plugin_opts)
  end,

  -- Rebuilds the sql object and intellisense cache
  refresh_cache = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    if workspace.get_state() ~= workspace_module.states.connected then
      utils.log_error("You are currently " .. workspace.get_state())
      return
    end
    public_api.refresh_objects(workspace.bufnr, function(_, err)
      if err then
        utils.log_error(err.message)
      end
    end)

    -- refresh the intellisense cache, fire and forget
    local success, msg = pcall(function()
      workspace.rebuild_intellisense()
    end)
    if not success then
      utils.log_error(msg)
    end
  end,

  disconnect = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    utils.try_resume(coroutine.create(function()
      await_public(function(callback)
        public_api.disconnect(workspace.bufnr, callback)
      end)
      clean_cache()
    end))
  end,

  execute_query = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    utils.try_resume(coroutine.create(function()
      local request = query_selection.current()
      if workspace.get_state() == workspace_module.states.disconnected then
        connect_to_default(workspace, plugin_opts)
      end
      clear_message_buffer()
      local execution = await_public(function(callback)
        public_api.execute({ bufnr = workspace.bufnr, request = request }, callback)
      end)
      if not execution.cancelled then
        query_results.show(execution.result_sets, plugin_opts, workspace.bufnr, execution.dispose)
      end
    end))
  end,

  execute_buffer = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    utils.try_resume(coroutine.create(function()
      local request = query_selection.buffer()
      if workspace.get_state() == workspace_module.states.disconnected then
        connect_to_default(workspace, plugin_opts)
      end
      clear_message_buffer()
      local execution = await_public(function(callback)
        public_api.execute({ bufnr = workspace.bufnr, request = request }, callback)
      end)
      if not execution.cancelled then
        query_results.show(execution.result_sets, plugin_opts, workspace.bufnr, execution.dispose)
      end
    end))
  end,

  cancel_query = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an existing one.")
      return
    end
    public_api.cancel(workspace.bufnr, function(_, err)
      if err then
        utils.log_error(err.message)
      end
    end)
  end,

  status = status_ui.component,

  toggle_activity = function()
    if not activity_ui.is_enabled() then
      utils.log_error("The built-in SQL Server UI is disabled")
      return
    end
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server workspace is attached to this buffer")
      return
    end
    activity_ui.toggle(workspace)
  end,

  backup_database = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an existing one.")
      return
    end
    utils.try_resume(coroutine.create(function()
      backup_database_async(workspace)
    end))
  end,

  restore_database = function()
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an existing one.")
      return
    end
    utils.try_resume(coroutine.create(function()
      restore_database_async(workspace)
    end))
  end,

  export_query_results = function(opts)
    local result_info = vim.b.query_result_info
    if not result_info then
      utils.log_error("Go to a query result buffer to save results")
      return
    end
    local selection
    if opts and opts.selection then
      local selection_error
      selection, selection_error = query_results.visual_selection()
      if not selection then
        utils.log_error(selection_error)
        return
      end
    end
    utils.try_resume(coroutine.create(function()
      export_query_results_async(result_info, selection)
    end))
  end,

  next_result = function()
    if not query_results.next_result() then
      utils.log_error("Go to a query result buffer with multiple results")
    end
  end,

  previous_result = function()
    if not query_results.previous_result() then
      utils.log_error("Go to a query result buffer with multiple results")
    end
  end,

  next_execution = function()
    if not query_results.next_execution(plugin_opts.open_results_in) then
      utils.log_error("No other query execution is available")
    end
  end,

  previous_execution = function()
    if not query_results.previous_execution(plugin_opts.open_results_in) then
      utils.log_error("No other query execution is available")
    end
  end,

  remove_result = function()
    local result_buffer = vim.api.nvim_get_current_buf()
    if not query_results.can_remove_result(result_buffer) then
      utils.log_error("Go to a query result buffer to remove a result")
      return
    end
    vim.ui.select({ "Remove", "Cancel" }, {
      prompt = "Remove this result?",
    }, function(choice)
      if choice == "Remove" and not query_results.remove_result(result_buffer) then
        utils.log_error("The query result is no longer available")
      end
    end)
  end,

  copy_result_cell = function()
    if not query_results.copy_cell() then
      utils.log_error("Move the cursor to a query result cell")
    end
  end,

  copy_result_selection = function()
    local ok, err, copied = query_results.copy_selection_as_html()
    if not ok then
      utils.log_error(err)
      return
    end
    utils.log_info(("Copied %d rows × %d columns as HTML"):format(copied.rows, copied.columns))
  end,

  show_results = function()
    local workspace = workspace_registry.get()
    local bufnr = workspace and workspace.bufnr or nil
    if not query_results.show_results(plugin_opts.open_results_in, bufnr) then
      utils.log_info("No query results are available")
    end
  end,

  find_object = function(callback)
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    if workspace.get_state() ~= workspace_module.states.connected then
      utils.log_error("You are currently " .. workspace.get_state())
      return
    end

    if workspace.is_refreshing() then
      workspace.record_message("Database objects are still refreshing", false)
      return
    end

    utils.try_resume(coroutine.create(function()
      local item = workspace.find_object_async("query")
      if not item then
        return
      end
      local buf = insert_query_into_buffer(item.script)
      workspace = workspace_registry.get(buf)
      if plugin_opts.execute_generated_select_statements and item.execute_immediately then
        clear_message_buffer()
        local execution = await_public(function(api_callback)
          public_api.execute({ bufnr = workspace.bufnr, text = item.script, scope = "buffer" }, api_callback)
        end)
        query_results.show(execution.result_sets, plugin_opts, workspace.bufnr, execution.dispose)
      end
      if callback then
        callback()
      end
    end))
  end,

  show_object_definition = function(callback)
    local workspace = workspace_registry.get()
    if not workspace then
      utils.log_error("No SQL Server lsp is attached. Create a new query or open an exising one.")
      return
    end
    if workspace.get_state() ~= workspace_module.states.connected then
      utils.log_error("You are currently " .. workspace.get_state())
      return
    end

    if workspace.is_refreshing() then
      workspace.record_message("Database objects are still refreshing", false)
      return
    end

    utils.try_resume(coroutine.create(function()
      local item = workspace.find_object_async("definition")
      if not item then
        return
      end
      local definition_buffer = open_object_definition_async(workspace, item)
      if not definition_buffer then
        return
      end
      if callback then
        callback()
      end
    end))
  end,
}

local M = {
  current_connection = public_api.current_connection,
  execute = public_api.execute,
  cancel = public_api.cancel,
  refresh_objects = public_api.refresh_objects,
  list_objects = public_api.list_objects,
  script_object = public_api.script_object,
  export_results = public_api.export_results,
  status = status_ui.component,
  commands = command_handlers,
}

for name, handler in pairs(command_handlers) do
  if M[name] == nil then
    M[name] = handler
  end
end

M.connect = function(profile, opts, callback)
  if profile == nil then
    return command_handlers.connect()
  end
  return public_api.connect(profile, opts, callback)
end

M.reconnect = function(bufnr, callback)
  if callback == nil then
    return command_handlers.reconnect()
  end
  return public_api.reconnect(bufnr, callback)
end

M.disconnect = function(bufnr, callback)
  if callback == nil then
    return command_handlers.disconnect()
  end
  return public_api.disconnect(bufnr, callback)
end

M.set_keymaps = function(prefix)
  sql_keymaps.set_keymaps(prefix, command_handlers)
end

---Subscribe to structured workspace activity events.
---@param subscriber fun(workspace: SqlServerWorkspace, event: SqlServerActivityEvent)
---@return fun unsubscribe
M.subscribe_activity = function(subscriber)
  return activity_stream.subscribe(subscriber)
end

M.setup = function(opts, callback)
  utils.try_resume(coroutine.create(function()
    setup_async(opts)
    commands.setup(command_handlers)
    sql_keymaps.set_keymaps(plugin_opts.keymap_prefix, command_handlers)
    if callback ~= nil then
      callback()
    end
  end))
end

return M
