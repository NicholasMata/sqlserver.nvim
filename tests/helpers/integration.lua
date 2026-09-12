local utils = require("sqlserver.utils")
local sql_tools_service_constants = require("sqlserver.adapters.sql_tools_service.constants")
local workspace_registry = require("sqlserver.workspace.registry")

local M = {}

function M.await(invoke, timeout)
  local co = coroutine.running()
  local completed = false
  local value
  local failure
  invoke(function(result, err)
    completed = true
    value = result
    failure = err
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co)
    end
  end)
  if not completed then
    local timed_out = false
    vim.defer_fn(function()
      if not completed and coroutine.status(co) == "suspended" then
        timed_out = true
        coroutine.resume(co)
      end
    end, timeout or 120000)
    coroutine.yield()
    assert(not timed_out, "Asynchronous operation timed out")
  end
  assert(not failure, failure and (failure.diagnostic or failure.message or tostring(failure)))
  return value
end

function M.setup()
  M.await(function(callback)
    require("sqlserver").setup({ open_results_in = "current_window" }, callback)
  end)
end

function M.new_query_buffer()
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".sql")
  vim.bo[bufnr].filetype = "sql"
  assert(
    vim.wait(30000, function()
      return M.get_sql_client(bufnr) ~= nil
    end, 10),
    "SQL Tools Service did not attach to the test buffer"
  )
  return bufnr
end

function M.connect_with(bufnr, options)
  local connection
  local ready
  local ready_error
  local client = assert(M.get_sql_client(bufnr))
  M.wait_for_all_async({
    function()
      connection = M.await(function(callback)
        require("sqlserver").connect({
          server = options.server or vim.env.DbServer,
          database = options.database or vim.env.DbDatabase,
          authenticationType = "SqlLogin",
          user = options.user,
          password = options.password,
          trustServerCertificate = true,
        }, { bufnr = bufnr }, callback)
      end)
    end,
    function()
      ready, ready_error = utils.wait_for_notification_async(bufnr, client, "textDocument/intelliSenseReady", 30000)
    end,
  })
  assert(not ready_error, ready_error and ready_error.message)
  assert(ready, "SQL Tools Service did not report that IntelliSense was ready")
  return connection
end

function M.connect(bufnr, database)
  return M.connect_with(bufnr, {
    database = database,
    user = vim.env.DbUser,
    password = vim.env.DbPassword,
  })
end

function M.cleanup()
  local workspaces = {}
  for bufnr, workspace in workspace_registry.iter() do
    table.insert(workspaces, { bufnr = bufnr, connected = workspace.get_connection() ~= nil })
  end
  for _, item in ipairs(workspaces) do
    if item.connected and vim.api.nvim_buf_is_valid(item.bufnr) then
      local _, err = pcall(function()
        M.await(function(callback)
          require("sqlserver").disconnect(item.bufnr, callback)
        end, 30000)
      end)
      if err then
        error(err, 0)
      end
    end
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype ~= "terminal" then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

function M.connected_hooks()
  local async = require("tests.helpers").async
  return {
    pre_case = async(function()
      M.cleanup()
      M.connect(M.new_query_buffer())
    end),
    post_case = async(M.cleanup),
  }
end

M.defer_async = utils.defer_async
M.get_sql_client = function(bufnr)
  return vim.lsp.get_clients({ name = sql_tools_service_constants.client_name, bufnr = bufnr })[1]
end

M.result_buffers = function(source_bufnr, execution_id)
  local candidates = vim
    .iter(vim.api.nvim_list_bufs())
    :filter(function(bufnr)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
      end
      local info = vim.b[bufnr].query_result_info
      return info and info.source_bufnr == source_bufnr
    end)
    :totable()
  if not execution_id then
    for _, bufnr in ipairs(candidates) do
      execution_id = math.max(execution_id or 0, vim.b[bufnr].query_result_info.execution_id)
    end
  end
  return vim
    .iter(candidates)
    :filter(function(bufnr)
      return vim.b[bufnr].query_result_info.execution_id == execution_id
    end)
    :totable()
end

M.get_completion_items = function()
  local client = utils.get_lsp_client()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local result, err = utils.lsp_request_async(client, "textDocument/completion", {
    textDocument = { uri = utils.lsp_file_uri() },
    -- Normal-mode cursor columns point at a character. Completion is
    -- requested at the insertion point immediately after it.
    position = { line = cursor[1] - 1, character = cursor[2] + 1 },
    context = { triggerKind = vim.lsp.protocol.CompletionTriggerKind.Invoked },
  })
  assert(not err, err and err.message or "Completion request failed")

  local items = result and (result.items or result) or {}
  return vim
    .iter(items)
    :map(function(item)
      return item.label
    end)
    :totable()
end

M.ui_select_fake = function(item)
  local original_select = vim.ui.select
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, _, on_choice)
    vim.ui.select = original_select
    local index
    if type(item) == "string" then
      index = vim.fn.index(items, item) + 1
      if index == nil or index == 0 then
        error("You tried to choose " .. item .. "when prompted but this wasn't an option", 0)
      end
    elseif type(item) == "number" then
      index = item
      if not items[index] then
        error("The index " .. index .. " is out of range in the items: " .. vim.inspect(items))
      end
      item = items[index]
    elseif type(item) == "function" then
      for candidate_index, candidate in ipairs(items) do
        if item(candidate) then
          index = candidate_index
          item = candidate
          break
        end
      end
      if not index then
        error("No picker item matched the test predicate: " .. vim.inspect(items))
      end
    end
    vim.defer_fn(function()
      on_choice(item, index)
    end, 3000)
  end
end

-- Takes a list of functions that should be run inside a coroutine,
-- runs each one and waits for all of them to finish. Must be
-- run inside a coroutine
M.wait_for_all_async = function(async_functions)
  local finished_count = 0
  local co = coroutine.running()

  for _, f in ipairs(async_functions) do
    coroutine.resume(coroutine.create(function()
      f()
      finished_count = finished_count + 1
      if finished_count == #async_functions then
        coroutine.resume(co)
      end
    end))
  end
  coroutine.yield()
end

return M
