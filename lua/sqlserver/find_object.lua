local utils = require("sqlserver.utils")
local object_script = require("sqlserver.core.object_script")
local object_explorer_timeout = 10000

---Same as utils.wait_for_notification_async but ignores any owner uri
---@param client vim.lsp.Client
---@param method string
---@param timeout integer|false
---@return any result
---@return lsp.ResponseError? error
local wait_for_notification_async = function(client, method, timeout)
  local this = coroutine.running()
  local resumed = false
  local handler
  handler = function(err, result, _)
    if not resumed then
      resumed = true
      utils.unregister_lsp_handler(client, method, handler)
      utils.try_resume(this, result, err)
    end
    return result, err
  end
  utils.register_lsp_handler(client, method, handler)
  if timeout then
    vim.defer_fn(function()
      if not resumed then
        resumed = true
        utils.unregister_lsp_handler(client, method, handler)
        utils.try_resume(
          this,
          nil,
          vim.lsp.rpc_response_error(
            vim.lsp.protocol.ErrorCodes.UnknownErrorCode,
            "Waiting for the lsp to call " .. method .. " timed out"
          )
        )
      end
    end, timeout)
  end
  return coroutine.yield()
end

local get_session_async = function(client, connection_options)
  connection_options = vim.deepcopy(connection_options)
  connection_options.ServerName = connection_options.server
  connection_options.DatabaseName = connection_options.database
  connection_options.UserName = connection_options.user
  connection_options.EnclaveAttestationProtocol = connection_options.attestationProtocol

  -- For some reason, if there is no display name set on the connection parameters then
  -- the language server will treat this as a default/system database:
  -- https://github.com/microsoft/sqltoolsservice/blob/49036c6196e73c3791bca5d31e97a16afee00772/src/Microsoft.SqlTools.ServiceLayer/ObjectExplorer/ObjectExplorerService.cs#L537
  connection_options.DatabaseDisplayName = connection_options.DatabaseDisplayName or connection_options.database

  local _, request_err = utils.lsp_request_async(client, "objectexplorer/createsession", connection_options)
  if request_err then
    error("SQL Tools Service could not start object exploration: " .. request_err.message, 0)
  end
  local response, err = wait_for_notification_async(client, "objectexplorer/sessioncreated", object_explorer_timeout)
  if response and response.rootNode and response.rootNode.objectType == "Server" then
    -- If we connect to a system database then the root node will be the server.
    -- So we need to set a target path to navigate to first so that we only search the database we connect to
    response.target_path = response.rootNode.nodePath
      .. "/Databases/System Databases/"
      .. connection_options.DatabaseName
  end
  if err then
    error("SQL Server object exploration timed out", 0)
  end
  if not (response and response.rootNode and response.sessionId) then
    error("SQL Tools Service returned an invalid object explorer session", 0)
  end
  return response
end

--[[
  scriptOptions Possible values:
    ScriptCreate
    ScriptDrop
    ScriptCreateDrop
    ScriptSelect


  public enum ScriptingOperationType
  {
      Select = 0,
      Create = 1,
      Insert = 2,
      Update = 3,
      Delete = 4,
      Execute = 5,
      Alter = 6
  }
--]]
local supported_node_types = {}
for _, object_type in ipairs(object_script.supported_types()) do
  supported_node_types[object_type] = true
end

local object_branch_patterns = {
  "/Tables",
  "/Views",
  "/Programmability/Stored Procedures",
  "/Programmability/Functions",
}

local function is_object_branch(node_path, database_path)
  if node_path == database_path then
    return true
  end

  local relative_path = node_path:sub(#database_path + 1)
  if relative_path == "/Programmability" then
    return true
  end

  return vim.iter(object_branch_patterns):any(function(branch)
    return relative_path == branch or vim.startswith(relative_path, branch .. "/")
  end)
end

local get_object_cache_async = function(lsp_client, connection_options, cancellation_token)
  utils.wait_for_schedule_async()
  local session = get_session_async(lsp_client, connection_options)
  utils.safe_assert(session and session.sessionId)

  local session_id = session.sessionId
  local root_path = session.rootNode.nodePath
  local cache = {}
  local expand_count = 0
  local co = coroutine.running()
  local expand_complete
  local finished = false

  local clean_up_and_return = function(return_value, err)
    if finished then
      return
    end
    finished = true
    lsp_client:request("objectExplorer/closeSession", {
      sessionId = session_id,
    }, function(close_err, result, _, _)
      session_id = nil
      return result, close_err
    end)
    utils.unregister_lsp_handler(lsp_client, "objectexplorer/expandCompleted", expand_complete)
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co, return_value, err)
    end
  end

  local expand = function(path)
    expand_count = expand_count + 1
    vim.schedule(function()
      -- check for cancellation every time we expand a node in the tree
      if cancellation_token.cancel then
        clean_up_and_return(nil, "cancelled")
        return
      end
      lsp_client:request("objectexplorer/expand", {
        sessionId = session_id,
        nodePath = path,
      }, function(err, result, _, _)
        if err then
          clean_up_and_return(nil, "SQL Tools Service could not expand database objects: " .. err.message)
        end
        return result, err
      end)
    end)
  end

  expand_complete = function(notification_err, expand_result, _)
    if finished then
      return
    end
    if notification_err then
      clean_up_and_return(nil, "SQL Tools Service could not expand database objects: " .. notification_err.message)
      return
    end
    if not (expand_result and type(expand_result.nodes) == "table") then
      clean_up_and_return(nil, "SQL Tools Service returned an invalid object expansion")
      return
    end
    for _, node in ipairs(expand_result.nodes) do
      if supported_node_types[node.objectType] then
        if
          type(node.nodePath) ~= "string"
          or type(node.parentNodePath) ~= "string"
          or type(node.metadata) ~= "table"
          or type(node.metadata.name) ~= "string"
          or type(node.metadata.schema) ~= "string"
          or type(node.metadata.metadataTypeName) ~= "string"
        then
          clean_up_and_return(nil, "SQL Tools Service returned an invalid database object")
          return
        end
        local path = node.parentNodePath
        local root_path_length = #root_path
        if session.target_path then
          root_path_length = #session.target_path
        end
        node.picker_path = string.sub(path, root_path_length + 2, #path) .. "/"
        node.text = node.picker_path .. node.label
        table.insert(cache, node)
      elseif not node.nodePath then
        utils.log_info("no node path")
        utils.log_info(node)
      elseif session.target_path and vim.startswith(session.target_path, node.nodePath) then
        -- We are on our way to the target, expand
        expand(node.nodePath)
      elseif session.target_path and is_object_branch(node.nodePath, session.target_path) then
        -- Only traverse branches containing supported object types.
        expand(node.nodePath)
      elseif not session.target_path and is_object_branch(node.nodePath, root_path) then
        expand(node.nodePath)
      end
    end

    expand_count = expand_count - 1
    if expand_count == 0 then
      clean_up_and_return(cache)
    end
  end

  utils.register_lsp_handler(lsp_client, "objectexplorer/expandCompleted", expand_complete)

  if object_explorer_timeout then
    vim.defer_fn(function()
      if not finished then
        clean_up_and_return(nil, "SQL Server object refresh timed out")
      end
    end, object_explorer_timeout)
  end

  expand(session.rootNode.nodePath)
  local result, err = coroutine.yield()
  if err then
    return nil, err
  end
  return result
end

local generate_script_async = function(item, client, owner_uri, intent)
  local spec = object_script.for_intent(item.objectType, intent)
  local scripting_params = {
    scriptDestination = "ToEditor",
    scriptingObjects = {
      {
        type = item.metadata.metadataTypeName,
        schema = item.metadata.schema,
        name = item.metadata.name,
      },
    },
    scriptOptions = {
      scriptCreateDrop = spec.script_create_drop,
      typeOfDataToScript = "SchemaOnly",
      scriptStatistics = "ScriptStatsNone",
    },
    ownerURI = owner_uri,
    operation = spec.operation,
  }
  local res, script_err = utils.lsp_request_async(client, "scripting/script", scripting_params)
  if script_err then
    error("SQL Tools Service could not script the selected object: " .. script_err.message, 0)
  end

  if not (res and res.script) then
    error("Error generating script (no script returned from language server)", 0)
  end

  return {
    -- strip carriage returns
    script = res.script:gsub("\r", ""),
    execute_immediately = spec.execute_immediately == true,
  }
end

-- one cache per server and db (ie per connect opts)
local global_cache = {}

local function connection_key(connection_options)
  if type(connection_options) ~= "table" then
    return connection_options
  end

  return vim.json.encode({
    server = connection_options.server,
    database = connection_options.database,
    user = connection_options.user,
    authentication_type = connection_options.authenticationType,
  })
end

local function is_refreshing(connection_options)
  local key = connection_key(connection_options)

  return (
    global_cache[key]
    and global_cache[key].refresh_coroutine
    and type(global_cache[key].refresh_coroutine) == "thread"
    and coroutine.status(global_cache[key].refresh_coroutine) ~= "dead"
  )
end

-- Initialises the cache, unless it already exists
-- If force is true, then gets a new cache and overwrites
local initialise_cache_async = function(lsp_client, connection_options, force)
  local key = connection_key(connection_options)
  if not global_cache[key] then
    global_cache[key] = {}
  end

  -- don't refresh if we are already refreshing or have refreshed previously
  if (global_cache[key].cache or is_refreshing(key)) and not force then
    return
  end

  -- cancel any currently running
  if global_cache[key].cancellation_token then
    global_cache[key].cancellation_token.cancel = true
  end
  local cancellation_token = { cancel = false }
  global_cache[key].cancellation_token = cancellation_token

  local refresh_coroutine = coroutine.running()
  global_cache[key].refresh_coroutine = refresh_coroutine
  vim.cmd("redrawstatus")
  local new_cache, refresh_error = get_object_cache_async(lsp_client, connection_options, cancellation_token)
  if global_cache[key] and global_cache[key].refresh_coroutine == refresh_coroutine then
    global_cache[key].refresh_coroutine = nil
    global_cache[key].cancellation_token = nil
  end
  if refresh_error == "cancelled" or cancellation_token.cancel then
    return { cancelled = true }
  end
  if refresh_error then
    error(refresh_error, 0)
  end
  if not cancellation_token.cancel then
    global_cache[key].cache = new_cache
  end
  return { cancelled = false, count = #new_cache }
end

-- Picker
local picker_icons = {
  ScalarValuedFunction = "󰡱",
  StoredProcedure = "󰯁",
  TableValuedFunction = "󰡱",
  Table = "",
  View = "󱂬",
}

local pick_item_async = function(cache, title)
  local co = coroutine.running()

  local success, snacks = pcall(require, "snacks")
  if not success then
    return utils.ui_select_async(cache, {
      prompt = title,
      format_item = function(item)
        return table.concat({
          picker_icons[item.nodeType],
          " ",
          item.picker_path,
          item.label,
        })
      end,
    })
  end

  snacks.picker.pick({
    title = title,
    layout = "select",
    items = cache,
    format = function(item)
      return {
        { picker_icons[item.nodeType], "SnacksPickerIcon" },
        { " " },
        { item.label },
        { " " },
        { item.picker_path, "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      coroutine.resume(co, item)
    end,
    cancel = function(picker)
      picker:close()
      coroutine.resume(co, nil)
    end,
  })
  return coroutine.yield()
end

local find_async = function(connection_options, lsp_client, owner_uri, intent)
  local title = intent == "definition" and "Object Definition" or "Find Query"
  if connection_options and connection_options.database and connection_options.server then
    title = connection_options.server .. " | " .. connection_options.database
  end
  local key = connection_key(connection_options)
  local cache = {}
  if global_cache[key] and global_cache[key].cache then
    cache = global_cache[key].cache
  end

  local item = pick_item_async(cache, title)
  if not item then
    return
  end
  return generate_script_async(item, lsp_client, owner_uri, intent)
end

local function cached_items(connection_options)
  local entry = global_cache[connection_key(connection_options)]
  return entry and entry.cache or {}
end

local function has_cache(connection_options)
  local entry = global_cache[connection_key(connection_options)]
  return entry ~= nil and entry.cache ~= nil
end

local function public_object(item)
  local metadata = item.metadata or {}
  return {
    id = item.nodePath or item.text,
    name = metadata.name or item.label,
    schema = metadata.schema,
    type = item.objectType or item.nodeType,
    path = item.picker_path,
  }
end

local function list_objects(connection_options, filters)
  filters = filters or {}
  return vim
    .iter(cached_items(connection_options))
    :filter(function(item)
      local object = public_object(item)
      return (not filters.name or object.name == filters.name)
        and (not filters.schema or object.schema == filters.schema)
        and (not filters.type or object.type == filters.type)
    end)
    :map(public_object)
    :totable()
end

local function script_object_async(connection_options, client, owner_uri, opts)
  local target = opts.object or opts
  local item = vim.iter(cached_items(connection_options)):find(function(candidate)
    local object = public_object(candidate)
    if target.id then
      return object.id == target.id
    end
    return object.name == target.name
      and (not target.schema or object.schema == target.schema)
      and (not target.type or object.type == target.type)
  end)
  if not item then
    error("SQL Server object was not found in the current metadata cache", 0)
  end
  return generate_script_async(item, client, owner_uri, opts.intent or "definition")
end

local function delete_unused_cache(in_use_connections)
  -- convert to keys first
  local in_use = {}
  for _, in_use_connection in ipairs(in_use_connections) do
    local key = connection_key(in_use_connection)
    in_use[key] = true
  end

  for cache_key, entry in pairs(global_cache) do
    if not in_use[cache_key] then
      if entry.cancellation_token then
        entry.cancellation_token.cancel = true
      end
      global_cache[cache_key] = nil
    end
  end
end

return {
  setup = function(timeouts)
    object_explorer_timeout = timeouts.object_explorer
  end,
  initialise_cache_async = initialise_cache_async,
  delete_unused_cache = delete_unused_cache,
  is_refreshing = is_refreshing,
  has_cache = has_cache,
  find_async = find_async,
  list = list_objects,
  script_async = script_object_async,
}
