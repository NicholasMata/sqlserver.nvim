local operations = require("sqlserver.workspace.operations")

local T = MiniTest.new_set()

local function manager_with_clock(on_error)
  local now = 1000000000
  local manager = operations.create({
    clock = function()
      return now
    end,
    on_error = on_error,
  })
  return manager, function(value)
    now = value
  end
end

T["Operations follow the complete lifecycle"] = function()
  local manager, set_time = manager_with_clock()
  local operation = manager.create_operation({
    kind = "query",
    title = "SQL Server query",
    message = "Waiting to execute",
    phase = "pending",
    source_bufnr = 12,
    details = { scope = "statement" },
  })

  assert(operation.snapshot().status == "pending")
  set_time(1100000000)
  assert(operation.start({ phase = "executing", message = "Executing query" }))
  set_time(1300000000)
  assert(operation.update({ phase = "loading_results", message = "Loading results", details = { batches = 2 } }))
  set_time(1600000000)
  assert(operation.succeed({ phase = "complete", message = "Query completed", details = { rows = 5 } }))

  local snapshot = operation.snapshot()
  assert(snapshot.id == 1)
  assert(snapshot.kind == "query")
  assert(snapshot.source_bufnr == 12)
  assert(snapshot.status == "succeeded")
  assert(snapshot.phase == "complete")
  assert(snapshot.duration_ms == 500)
  assert(snapshot.details.scope == "statement")
  assert(snapshot.details.batches == 2)
  assert(snapshot.details.rows == 5)
end

T["Operations reject invalid transitions"] = function()
  local manager = manager_with_clock()
  local pending = manager.create_operation({ kind = "query", title = "Query", message = "Pending" })

  assert(not pcall(pending.update, { message = "Invalid" }))
  assert(not pcall(pending.succeed, { message = "Invalid" }))
  assert(pending.start())
  assert(not pcall(pending.start))
  assert(pending.cancel({ message = "Cancelled" }))
  assert(not pending.update({ message = "Late update" }))
  assert(not pending.succeed({ message = "Late success" }))
  assert(not pending.fail({ code = "late" }, { message = "Late failure" }))
  assert(not pending.cancel({ message = "Late cancellation" }))
  assert(pending.snapshot().message == "Cancelled")
end

T["Failed operations preserve structured errors"] = function()
  local manager = manager_with_clock()
  local operation = manager.start({ kind = "connection", title = "Connection", message = "Connecting" })
  local err = { code = "authentication_failed", message = "Login failed", retryable = true }

  assert(operation.fail(err, { phase = "complete", message = "Connection failed" }))
  err.message = "changed"
  local snapshot = operation.snapshot()
  assert(snapshot.status == "failed")
  assert(snapshot.error.code == "authentication_failed")
  assert(snapshot.error.message == "Login failed")
  assert(snapshot.error.retryable)
end

T["Operation snapshots cannot mutate stored state"] = function()
  local manager = manager_with_clock()
  local operation = manager.start({
    kind = "metadata",
    title = "Metadata",
    message = "Loading",
    details = { database = "master" },
  })
  local snapshot = operation.snapshot()
  snapshot.message = "Changed"
  snapshot.details.database = "other"

  assert(operation.snapshot().message == "Loading")
  assert(operation.snapshot().details.database == "master")
end

T["Managers track concurrent operations deterministically"] = function()
  local manager = manager_with_clock()
  local connection = manager.start({ kind = "connection", title = "Connection", message = "Connecting" })
  local metadata = manager.create_operation({ kind = "metadata", title = "Metadata", message = "Waiting" })

  local active = manager.active()
  assert(#active == 2)
  assert(active[1].id == connection.id)
  assert(active[2].id == metadata.id)
  assert(manager.latest_active().id == metadata.id)

  assert(connection.succeed({ message = "Connected" }))
  assert(#manager.active() == 1)
  assert(manager.latest_active().id == metadata.id)
end

T["Operations can be resumed safely by identifier"] = function()
  local manager = manager_with_clock()
  local operation = manager.start({ kind = "query", title = "Query", message = "Executing" })
  local resumed = manager.operation(operation.id)

  assert(resumed == operation)
  assert(resumed.update({ phase = "loading_results", message = "Loading results" }))
  assert(operation.snapshot().phase == "loading_results")
  assert(resumed.succeed({ message = "Complete" }))
  assert(not manager.operation(operation.id).fail({ code = "late" }))
  assert(manager.operation(999) == nil)
end

T["Subscribers are isolated and receive immutable snapshots"] = function()
  local errors = {}
  local received = {}
  local manager = manager_with_clock(function(message)
    table.insert(errors, message)
  end)
  manager.subscribe(function(snapshot)
    table.insert(received, snapshot)
    snapshot.message = "Changed"
  end)
  manager.subscribe(function()
    error("broken subscriber")
  end)

  local operation = manager.create_operation({ kind = "query", title = "Query", message = "Pending" })
  operation.start({ message = "Executing" })

  assert(#received == 2)
  assert(received[1].status == "pending")
  assert(received[2].status == "running")
  assert(operation.snapshot().message == "Executing")
  assert(#errors == 2)
  assert(errors[1]:find("broken subscriber", 1, true))
end

T["Unsubscribed listeners stop receiving operations"] = function()
  local manager = manager_with_clock()
  local received = 0
  local unsubscribe = manager.subscribe(function()
    received = received + 1
  end)
  local operation = manager.create_operation({ kind = "query", title = "Query", message = "Pending" })
  unsubscribe()
  operation.start()
  assert(received == 1)
end

T["Disposal cancels active work and suppresses late callbacks"] = function()
  local manager = manager_with_clock()
  local first = manager.start({ kind = "query", title = "Query", message = "Executing", source_bufnr = 4 })
  local second =
    manager.create_operation({ kind = "metadata", title = "Metadata", message = "Waiting", source_bufnr = 4 })

  assert(manager.dispose({ phase = "disposed", message = "Source buffer deleted" }))
  assert(first.snapshot().status == "cancelled")
  assert(second.snapshot().status == "cancelled")
  assert(first.snapshot().message == "Source buffer deleted")
  assert(not first.succeed({ message = "Late query result" }))
  assert(not second.start())
  assert(not manager.dispose())
  assert(not pcall(manager.create_operation, { kind = "query", title = "Query", message = "Pending" }))
end

return T
