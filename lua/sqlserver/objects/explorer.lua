local M = {}

local object_icons = {
  ScalarValuedFunction = "󰡱",
  StoredProcedure = "󰯁",
  TableValuedFunction = "󰡱",
  Table = "",
  View = "󱂬",
}

local detail_icons = {
  Column = "󰠵",
  Columns = "󰠵",
  Constraint = "󰅩",
  Constraints = "󰅩",
  Folder = "󰉋",
  Index = "󰌷",
  Indexes = "󰌷",
  Key = "󰌆",
  Keys = "󰌆",
  Parameter = "󰘦",
  Parameters = "󰘦",
  Statistic = "󰄧",
  Statistics = "󰄧",
  Trigger = "󰯂",
  Triggers = "󰯂",
}

local function node(id, kind, label, icon, children, object, loadable, node_type)
  return {
    id = id,
    kind = kind,
    label = label,
    icon = icon,
    children = children or {},
    object = object,
    loadable = loadable == true,
    loaded = not loadable,
    node_type = node_type,
  }
end

local function path_segments(path)
  local segments = {}
  for segment in (path or ""):gmatch("[^/]+") do
    segments[#segments + 1] = segment
  end
  return segments
end

---@param connection table
---@param objects table[]
---@return table
function M.build(connection, objects)
  connection = connection or {}
  local server_name = connection.server or "SQL Server"
  local database_name = connection.database or "Database"
  local server = node("server:" .. server_name, "server", server_name, "")
  local database = node(server.id .. "/database:" .. database_name, "database", database_name, "")
  server.children = { database }

  local folders = { [""] = database }
  for _, object in ipairs(objects or {}) do
    local parent = database
    local path = ""
    for _, segment in ipairs(path_segments(object.path)) do
      path = path == "" and segment or path .. "/" .. segment
      if not folders[path] then
        folders[path] = node(database.id .. "/path:" .. path, "group", segment, "󰉋")
        parent.children[#parent.children + 1] = folders[path]
      end
      parent = folders[path]
    end
    parent.children[#parent.children + 1] = node(
      parent.id .. "/object:" .. object.id,
      "object",
      object.name,
      object_icons[object.type] or "󰘦",
      nil,
      object,
      object.expandable == true or object.type == "Table"
    )
  end

  return server
end

---@param parent table
---@param children table[]
function M.set_children(parent, children)
  local mapped = vim
    .iter(children or {})
    :map(function(child)
      return node(
        child.id,
        "detail",
        child.label,
        detail_icons[child.type] or "󰘦",
        nil,
        nil,
        child.expandable,
        child.type
      )
    end)
    :totable()
  parent.children = mapped
  parent.loaded = true
end

return M
