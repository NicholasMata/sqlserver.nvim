local M = {}

M.statuses = {
  pending = "pending",
  running = "running",
  succeeded = "succeeded",
  failed = "failed",
  cancelled = "cancelled",
}

local terminal_statuses = {
  [M.statuses.succeeded] = true,
  [M.statuses.failed] = true,
  [M.statuses.cancelled] = true,
}

local function default_clock()
  return (vim.uv or vim.loop).hrtime()
end

local function copy(value)
  return value == nil and nil or vim.deepcopy(value)
end

local function merge_details(current, update)
  if update == nil then
    return current
  end
  return vim.tbl_deep_extend("force", current or {}, copy(update))
end

---@class SqlServerOperationSnapshot
---@field id integer
---@field kind string
---@field title string
---@field message string
---@field phase string
---@field status "pending"|"running"|"succeeded"|"failed"|"cancelled"
---@field source_bufnr? integer
---@field created_at_ns integer
---@field started_at_ns? integer
---@field completed_at_ns? integer
---@field duration_ms? number
---@field details? table
---@field error? table

---@class SqlServerOperation
---@field id integer
---@field snapshot fun(): SqlServerOperationSnapshot
---@field start fun(update?: table): boolean
---@field update fun(update: table): boolean
---@field succeed fun(update?: table): boolean
---@field fail fun(error: table, update?: table): boolean
---@field cancel fun(update?: table): boolean
---@field is_terminal fun(): boolean

---@param opts? { clock?: fun(): integer, on_error?: fun(message: string) }
function M.create(opts)
  opts = opts or {}
  local clock = opts.clock or default_clock
  local on_error = opts.on_error
  local operations = {}
  local handles = {}
  local subscribers = {}
  local next_operation_id = 0
  local next_subscriber_id = 0
  local disposed = false

  local manager = {}

  local function publish(state)
    local snapshot = copy(state)
    local current = {}
    for _, subscriber in pairs(subscribers) do
      table.insert(current, subscriber)
    end
    for _, subscriber in ipairs(current) do
      local ok, err = pcall(subscriber, copy(snapshot))
      if not ok and on_error then
        pcall(on_error, "SQL Server operation subscriber failed: " .. tostring(err))
      end
    end
  end

  local function complete(state, status, update, operation_error)
    if terminal_statuses[state.status] then
      return false
    end
    if status == M.statuses.succeeded and state.status ~= M.statuses.running then
      error("Only a running operation can succeed", 0)
    end
    if update then
      state.phase = update.phase or state.phase
      state.message = update.message or state.message
      state.details = merge_details(state.details, update.details)
    end
    state.status = status
    state.error = copy(operation_error)
    state.completed_at_ns = clock()
    local duration_start = state.started_at_ns or state.created_at_ns
    state.duration_ms = (state.completed_at_ns - duration_start) / 1e6
    publish(state)
    return true
  end

  local function create_operation(spec)
    assert(not disposed, "Operation manager is disposed")
    assert(type(spec) == "table", "Operation specification is required")
    assert(type(spec.kind) == "string" and spec.kind ~= "", "Operation kind is required")
    assert(type(spec.title) == "string" and spec.title ~= "", "Operation title is required")
    assert(type(spec.message) == "string" and spec.message ~= "", "Operation message is required")

    next_operation_id = next_operation_id + 1
    local state = {
      id = next_operation_id,
      kind = spec.kind,
      title = spec.title,
      message = spec.message,
      phase = spec.phase or spec.kind,
      status = M.statuses.pending,
      source_bufnr = spec.source_bufnr,
      created_at_ns = clock(),
      details = copy(spec.details),
    }
    operations[state.id] = state

    local operation = { id = state.id }

    function operation.snapshot()
      return copy(state)
    end

    function operation.is_terminal()
      return terminal_statuses[state.status] == true
    end

    function operation.start(update)
      if terminal_statuses[state.status] then
        return false
      end
      if state.status ~= M.statuses.pending then
        error("Only a pending operation can start", 0)
      end
      update = update or {}
      state.phase = update.phase or state.phase
      state.message = update.message or state.message
      state.details = merge_details(state.details, update.details)
      state.status = M.statuses.running
      state.started_at_ns = clock()
      publish(state)
      return true
    end

    function operation.update(update)
      assert(type(update) == "table", "Operation update is required")
      if terminal_statuses[state.status] then
        return false
      end
      if state.status ~= M.statuses.running then
        error("Only a running operation can be updated", 0)
      end
      state.phase = update.phase or state.phase
      state.message = update.message or state.message
      state.details = merge_details(state.details, update.details)
      publish(state)
      return true
    end

    function operation.succeed(update)
      return complete(state, M.statuses.succeeded, update)
    end

    function operation.fail(operation_error, update)
      assert(type(operation_error) == "table", "A structured operation error is required")
      return complete(state, M.statuses.failed, update, operation_error)
    end

    function operation.cancel(update)
      return complete(state, M.statuses.cancelled, update)
    end

    handles[state.id] = operation
    publish(state)
    return operation
  end

  function manager.create_operation(spec)
    return create_operation(spec)
  end

  function manager.start(spec)
    local operation = create_operation(spec)
    operation.start()
    return operation
  end

  function manager.get(operation_id)
    return copy(operations[operation_id])
  end

  function manager.active()
    local active = {}
    for _, state in pairs(operations) do
      if not terminal_statuses[state.status] then
        table.insert(active, copy(state))
      end
    end
    table.sort(active, function(left, right)
      return left.id < right.id
    end)
    return active
  end

  function manager.latest_active()
    local active = manager.active()
    return active[#active]
  end

  function manager.cancel_all(update)
    local count = 0
    for _, state in ipairs(manager.active()) do
      if handles[state.id].cancel(update) then
        count = count + 1
      end
    end
    return count
  end

  function manager.operation(operation_id)
    return handles[operation_id]
  end

  function manager.subscribe(subscriber)
    assert(type(subscriber) == "function", "An operation subscriber function is required")
    assert(not disposed, "Operation manager is disposed")
    next_subscriber_id = next_subscriber_id + 1
    local subscriber_id = next_subscriber_id
    subscribers[subscriber_id] = subscriber
    local subscribed = true
    return function()
      if subscribed then
        subscribers[subscriber_id] = nil
        subscribed = false
      end
    end
  end

  function manager.dispose(update)
    if disposed then
      return false
    end
    manager.cancel_all(update or { message = "Operation cancelled" })
    subscribers = {}
    disposed = true
    return true
  end

  return manager
end

return M
