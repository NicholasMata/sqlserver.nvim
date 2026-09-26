local workspace_registry = require("sqlserver.workspace.registry")
local connection_profiles = require("sqlserver.connections.profiles")
local query_selection = require("sqlserver.queries.selection")
local query_summary = require("sqlserver.queries.summary")
local result_sets = require("sqlserver.results.collection")

local M = {}
local config

local function api_error(code, message, cause)
  return { code = code, message = message, cause = cause }
end

local function normalize_error(code, err)
  if type(err) == "table" and err.code and err.message then
    return err
  end
  if type(err) == "table" and err.message then
    return api_error(code, err.message, err.diagnostic)
  end
  return api_error(code, tostring(err))
end

local function require_callback(callback)
  assert(type(callback) == "function", "A completion callback(result, error) is required")
end

local function run(code, callback, operation)
  require_callback(callback)
  local co = coroutine.create(function()
    local ok, result = pcall(operation)
    if ok then
      pcall(callback, result, nil)
    else
      pcall(callback, nil, normalize_error(code, result))
    end
  end)
  local resumed, err = coroutine.resume(co)
  if not resumed then
    pcall(callback, nil, normalize_error(code, err))
  end
end

local function require_config()
  if not config then
    error(api_error("not_setup", "Call require('sqlserver').setup() before using the public API"), 0)
  end
  return config
end

local function get_workspace(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local workspace = workspace_registry.get(bufnr)
  if not workspace then
    error(api_error("workspace_not_found", "No SQL Server workspace is attached to buffer " .. bufnr), 0)
  end
  return workspace
end

local function resolve_profile(profile, name)
  local opts = require_config()
  if type(profile) == "string" then
    local profiles = connection_profiles.load(opts.connections_file) or {}
    name = profile
    profile = profiles[name]
    if not profile then
      error(api_error("profile_not_found", "SQL Server connection profile '" .. name .. "' was not found"), 0)
    end
  elseif type(profile) ~= "table" then
    error(api_error("invalid_argument", "connect() requires a profile name or profile table"), 0)
  end
  name = name or "custom"
  local resolved = connection_profiles.resolve(profile, name)
  connection_profiles.validate(resolved, name)
  return resolved
end

function M.configure(opts)
  config = opts
end

local function initialize_connection_async(workspace, lifecycle)
  if not lifecycle then
    error(api_error("connection_cancelled", "SQL Server connection was cancelled"), 0)
  end
  lifecycle.update("loading_metadata", "Loading database objects")
  local refreshed, refresh_result = pcall(workspace.initialise_objects_async, false, { silent = true })
  if not refreshed then
    lifecycle.fail("Connection initialization failed", refresh_result)
    error(refresh_result, 0)
  elseif refresh_result and refresh_result.cancelled then
    lifecycle.fail("Connection initialization cancelled", refresh_result)
    error(api_error("connection_cancelled", "SQL Server connection initialization was cancelled"), 0)
  end
  if not lifecycle.complete() then
    error(api_error("connection_cancelled", "SQL Server connection was cancelled"), 0)
  end
end

---@param profile string|table
---@param opts? { bufnr?: integer, profile_name?: string, refresh_objects?: boolean }
---@param callback fun(connection?: table, error?: table)
function M.connect(profile, opts, callback)
  opts = opts or {}
  run("connection_failed", callback, function()
    local workspace = get_workspace(opts.bufnr)
    local connection = resolve_profile(profile, opts.profile_name)
    local _, lifecycle = workspace.connect_async(
      { connection = { options = connection } },
      { defer_completion = opts.refresh_objects ~= false }
    )
    if lifecycle then
      initialize_connection_async(workspace, lifecycle)
    end
    return connection_profiles.public_view(workspace.get_connection())
  end)
end

---@param bufnr? integer
---@param callback fun(result?: table, error?: table)
function M.reconnect(bufnr, callback)
  run("connection_failed", callback, function()
    local workspace = get_workspace(bufnr)
    local _, lifecycle = workspace.reconnect_async({ defer_completion = true })
    initialize_connection_async(workspace, lifecycle)
    return connection_profiles.public_view(workspace.get_connection())
  end)
end

---@param bufnr? integer
---@param callback fun(result?: table, error?: table)
function M.disconnect(bufnr, callback)
  run("disconnect_failed", callback, function()
    local workspace = get_workspace(bufnr)
    workspace.disconnect_async()
    return { bufnr = workspace.bufnr, disconnected = true }
  end)
end

---@param bufnr? integer
---@return table?
---@return table? error
function M.current_connection(bufnr)
  local ok, result = pcall(function()
    local connection = get_workspace(bufnr).get_connection()
    return connection and connection_profiles.public_view(connection) or nil
  end)
  if ok then
    return result, nil
  end
  return nil, normalize_error("workspace_not_found", result)
end

local function execution_request(opts)
  if opts.request then
    return vim.deepcopy(opts.request)
  end
  if opts.text then
    return { kind = opts.scope == "buffer" and "buffer" or "selection", text = opts.text }
  end
  if opts.scope == "buffer" then
    return query_selection.buffer(opts.bufnr)
  end
  return query_selection.statement(opts.bufnr)
end

---@param opts? { bufnr?: integer, scope?: "statement"|"selection"|"buffer", text?: string, request?: SqlServerQueryRequest, _present?: fun(execution: table): boolean }
---@param callback fun(result?: table, error?: table)
function M.execute(opts, callback)
  opts = opts or {}
  run("query_failed", callback, function()
    local workspace = get_workspace(opts.bufnr)
    local raw, lifecycle = workspace.execute_async(execution_request(opts), { defer_completion = true })
    if not raw then
      return { cancelled = true, result_sets = {} }
    end
    lifecycle.update("loading_results", "Loading query results")
    local configured = require_config()
    local query_id = raw._sqlserver_query_id
    local collected_ok, collected =
      pcall(result_sets.collect_async, raw, configured.results.max_rows, workspace.fetch_result_rows_async)
    if not collected_ok then
      pcall(workspace.dispose_query_async, query_id)
      lifecycle.fail("Loading query results failed", collected)
      error(collected, 0)
    end
    for _, result_set in ipairs(collected) do
      result_set.locator._sqlserver_query_id = query_id
    end
    local released = false
    local execution = {
      cancelled = false,
      summary = query_summary.create(raw),
      result_sets = collected,
      dispose = function()
        if released then
          return false
        end
        released = true
        return workspace.release_query(query_id)
      end,
    }
    if opts._present then
      if not lifecycle.update("rendering_results", "Rendering query results") then
        lifecycle.complete()
        return { cancelled = true, result_sets = {} }
      end
      local presented, presentation_error = pcall(opts._present, execution)
      if not presented then
        execution.dispose()
        lifecycle.fail("Rendering query results failed", presentation_error)
        error(presentation_error, 0)
      end
    end

    if not lifecycle.complete() then
      return { cancelled = true, result_sets = {} }
    end
    if #collected == 0 then
      execution.dispose()
    end
    return execution
  end)
end

---@param bufnr? integer
---@param callback fun(result?: table, error?: table)
function M.cancel(bufnr, callback)
  run("cancellation_failed", callback, function()
    local workspace = get_workspace(bufnr)
    workspace.cancel_async()
    return { bufnr = workspace.bufnr, cancellation_requested = true }
  end)
end

---@param bufnr? integer
---@param callback fun(result?: table, error?: table)
function M.refresh_objects(bufnr, callback)
  run("object_refresh_failed", callback, function()
    return get_workspace(bufnr).initialise_objects_async(true)
  end)
end

---@param opts? { bufnr?: integer, name?: string, schema?: string, type?: string }
---@param callback fun(objects?: table[], error?: table)
function M.list_objects(opts, callback)
  opts = opts or {}
  run("object_list_failed", callback, function()
    local workspace = get_workspace(opts.bufnr)
    if workspace.is_refreshing() and not workspace.has_object_cache() then
      error(api_error("metadata_refreshing", "Database objects are still refreshing"), 0)
    end
    return workspace.list_objects({ name = opts.name, schema = opts.schema, type = opts.type })
  end)
end

---@param opts { bufnr?: integer, object?: table, id?: string, name?: string, schema?: string, type?: string, intent?: "query"|"definition" }
---@param callback fun(script?: table, error?: table)
function M.script_object(opts, callback)
  opts = opts or {}
  run("object_script_failed", callback, function()
    local workspace = get_workspace(opts.bufnr)
    if workspace.is_refreshing() and not workspace.has_object_cache() then
      error(api_error("metadata_refreshing", "Database objects are still refreshing"), 0)
    end
    return workspace.script_object_async(opts)
  end)
end

local function validate_result_selection(selection)
  if selection == nil then
    return
  end
  if type(selection) ~= "table" then
    error(api_error("invalid_argument", "export_results() selection must be a table"), 0)
  end
  for _, name in ipairs({ "row_start", "row_end", "column_start", "column_end" }) do
    local value = selection[name]
    if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
      error(api_error("invalid_argument", "selection." .. name .. " must be a non-negative integer"), 0)
    end
  end
  if selection.row_start > selection.row_end or selection.column_start > selection.column_end then
    error(api_error("invalid_argument", "export_results() selection bounds are reversed"), 0)
  end
end

---@param opts { result_set?: SqlServerResultSet, bufnr?: integer, path: string, format?: string, selection?: SqlServerResultSelection, _present?: fun(path: string, format: string): any }
---@param callback fun(result?: table, error?: table)
function M.export_results(opts, callback)
  opts = opts or {}
  run("export_failed", callback, function()
    if type(opts.path) ~= "string" or opts.path == "" then
      error(api_error("invalid_argument", "export_results() requires a path"), 0)
    end
    local result_set = opts.result_set
    if not result_set and opts.bufnr then
      local info = vim.b[opts.bufnr].query_result_info
      result_set = info and { locator = info.subset_params } or nil
    end
    if not (result_set and result_set.locator) then
      error(api_error("invalid_argument", "export_results() requires a result_set or result buffer"), 0)
    end
    validate_result_selection(opts.selection)
    local format = opts.format or opts.path:match("%.([^.]+)$")
    format = format and format:lower() or nil
    local workspace = workspace_registry.find_by_owner_uri(result_set.locator.ownerUri)
    if not workspace then
      error(api_error("result_unavailable", "The query workspace is no longer available for export"), 0)
    end
    local _, lifecycle = workspace.export_result_async(result_set.locator, opts.path, format, {
      timeout = require_config().timeouts.export,
      selection = opts.selection,
      defer_completion = opts._present ~= nil,
    })
    if lifecycle == false then
      error(api_error("export_cancelled", "Query result export was cancelled"), 0)
    end
    if lifecycle then
      if not lifecycle.update("opening_buffer", "Opening export buffer") then
        error(api_error("export_cancelled", "Query result export was cancelled"), 0)
      end
      local presented, presentation_result = pcall(opts._present, opts.path, format)
      if not presented then
        lifecycle.fail("Opening export buffer failed", presentation_result)
        error(presentation_result, 0)
      elseif presentation_result == false then
        lifecycle.cancel("Export cancelled")
        error(api_error("export_cancelled", "Query result export was cancelled"), 0)
      end
      if not lifecycle.complete() then
        error(api_error("export_cancelled", "Query result export was cancelled"), 0)
      end
    end
    return { path = opts.path, format = format, selection = vim.deepcopy(opts.selection) }
  end)
end

return M
