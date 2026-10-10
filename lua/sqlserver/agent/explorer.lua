local M = {}

local execution_icons = {
  executing = { "󰐊", "SqlServerJobRunning" },
  completing = { "󰐊", "SqlServerJobRunning" },
  queued = { "󰔟", "SqlServerJobWaiting" },
  waiting_for_worker = { "󰔟", "SqlServerJobWaiting" },
  waiting_for_step = { "󰔟", "SqlServerJobWaiting" },
  between_retries = { "󰔟", "SqlServerJobWaiting" },
  suspended = { "󰏤", "SqlServerJobSuspended" },
  idle = { "󰅐", "SqlServerJobIdle" },
}

local function value(item)
  if item == nil or item == "" then
    return nil
  end
  if type(item) == "boolean" then
    return item and "Yes" or "No"
  end
  return tostring(item):gsub("[%c]", " ")
end

local function node(id, label, kind, icon, children)
  return {
    id = "sqlserver-agent://" .. id,
    label = label,
    agent_kind = kind,
    icon = icon,
    isLeaf = children == nil,
    loaded = children ~= nil,
    loading = false,
    children = children,
  }
end

local function with_paths(parent)
  for _, child in ipairs(parent.children or {}) do
    child.path_labels = vim.deepcopy(parent.path_labels or { parent.label })
    child.path_labels[#child.path_labels + 1] = child.label
    with_paths(child)
  end
end

function M.attach(service_root, server_name)
  local jobs = node("jobs", "Jobs", "jobs", "󰒋")
  jobs.isLeaf = false
  local agent = node("service", "SQL Server Agent", "service", "󰒋", { jobs })
  if service_root.objectType == "Server" then
    service_root.children = service_root.children or {}
    service_root.children[#service_root.children + 1] = agent
    service_root.expanded = true
    with_paths(service_root)
    return service_root
  end

  local databases = node("databases", "Databases", "databases", "󰆼", { service_root })
  databases.expanded = true
  local root = node("server", value(server_name) or "SQL Server", "server", "󰒋", { databases, agent })
  root.expanded = true
  root.path_labels = { root.label }
  with_paths(root)
  return root
end

function M.set_jobs(parent, jobs)
  local previous = {}
  for _, child in ipairs(parent.children or {}) do
    previous[child.job.id] = child
  end
  local children = {}
  for _, job in ipairs(jobs) do
    local child = previous[job.id] or node("jobs/" .. job.id, job.name, "job", "󰒋")
    child.job = job
    child.label = value(job.name) or job.id
    child.icon = job.enabled == true and "󰄬" or job.enabled == false and "󰅙" or "?"
    local execution_icon = execution_icons[job.execution_status]
    child.status_icon = execution_icon and execution_icon[1] or nil
    child.status_highlight = execution_icon and execution_icon[2] or nil
    child.annotations = nil
    child.isLeaf = true
    children[#children + 1] = child
  end
  parent.children = children
  parent.loaded = true
  parent.loading = false
  parent.errorMessage = nil
  parent.annotations = #jobs == 0 and { "No jobs" } or nil
  with_paths(parent)
end

return M
