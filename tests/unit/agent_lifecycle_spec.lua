local workspace_module = require("sqlserver.workspace")

local T = MiniTest.new_set()

local function fixture()
  local requests = {}
  local workspace = workspace_module.create({
    bufnr = 17,
    backend = {
      owner_uri = "file:///agent.sql",
      connect_async = function()
        return {}
      end,
      disconnect_async = function() end,
    },
    objects = {},
    agent_timeout = 25,
  })
  local function request(kind, job, control, timeout)
    requests[#requests + 1] = { kind = kind, job = job, control = control, timeout = timeout }
    local result, err = coroutine.yield()
    if err then
      error(err, 0)
    end
    return result
  end
  workspace.set_agent_backend({
    list_jobs_async = function(control, timeout)
      return request("jobs", nil, control, timeout)
    end,
    get_job_details_async = function(job, control, timeout)
      return request("details", job, control, timeout)
    end,
    list_alerts_async = function(control, timeout)
      return request("alerts", nil, control, timeout)
    end,
  })
  workspace.connect_async({ connection = { options = { server = "localhost" } } })
  return workspace, requests
end

local function start(fn)
  local thread = coroutine.create(fn)
  local ok, err = coroutine.resume(thread)
  assert(ok, err)
  return thread
end

T["A newer jobs refresh supersedes an older response"] = function()
  local workspace, requests = fixture()
  local old = start(function()
    assert(workspace.list_agent_jobs_async() == nil)
  end)
  local first = workspace.get_active_operation()
  assert(first.kind == "agent" and first.status == "running")
  local new = start(function()
    local jobs = workspace.list_agent_jobs_async()
    assert(#jobs == 1 and jobs[1].name == "New")
  end)
  assert(workspace.get_agent_state("jobs").loading)
  assert(requests[1].timeout == 25 and requests[2].timeout == 25)
  assert(workspace.get_activity()[#workspace.get_activity() - 1].status == "cancelled")
  assert(coroutine.resume(new, { { name = "New" } }))
  assert(coroutine.resume(old, { { name = "Old" } }))
  assert(workspace.get_agent_state("jobs").data[1].name == "New")
  assert(workspace.get_active_operation() == nil)
end

T["Failed refresh retains successful data and a safe error"] = function()
  local workspace = fixture()
  local first = start(function()
    workspace.list_agent_alerts_async()
  end)
  assert(coroutine.resume(first, { { name = "Existing" } }))
  local second = start(function()
    local data, err = workspace.list_agent_alerts_async()
    assert(data == nil and err.code == "agent_timeout")
  end)
  assert(workspace.get_agent_state("alerts").data[1].name == "Existing")
  assert(coroutine.resume(second, nil, { code = "agent_timeout", message = "SQL Agent request timed out" }))
  local state = workspace.get_agent_state("alerts")
  assert(state.status == "ready" and state.data[1].name == "Existing")
  assert(state.error.code == "agent_timeout" and workspace.get_active_operation() == nil)
end

T["Selection, view closure, and disconnect discard late details"] = function()
  local workspace = fixture()
  local a = { id = "a", name = "A" }
  local b = { id = "b", name = "B" }
  local old = start(function()
    assert(workspace.get_agent_job_details_async(a) == nil)
  end)
  local current = start(function()
    assert(workspace.get_agent_job_details_async(b).job_name == "B")
  end)
  assert(workspace.get_agent_state("details").job.id == "b")
  assert(coroutine.resume(old, { job_name = "A" }))
  assert(coroutine.resume(current, { job_name = "B" }))
  local closed = start(function()
    assert(workspace.get_agent_job_details_async(b) == nil)
  end)
  workspace.close_agent_view("details")
  assert(coroutine.resume(closed, { job_name = "Late" }))
  assert(workspace.get_agent_state("details").data == nil)
  local pending = start(function()
    assert(workspace.list_agent_jobs_async() == nil)
  end)
  workspace.disconnect_async()
  assert(coroutine.resume(pending, { { name = "Late" } }))
  assert(workspace.get_agent_state("jobs").data == nil)
  assert(workspace.get_active_operation() == nil)
end

return T
