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

local actionable_types = {
  ScalarValuedFunction = true,
  StoredProcedure = true,
  Table = true,
  TableValuedFunction = true,
  View = true,
}

local function icon_for(node_type)
  return object_icons[node_type] or detail_icons[node_type] or "󰘦"
end

local function public_object(service_node)
  if not actionable_types[service_node.objectType] then
    return nil
  end
  local metadata = service_node.metadata
  if type(metadata) ~= "table" or not (metadata.name and metadata.schema and metadata.metadataTypeName) then
    return nil
  end
  return {
    id = service_node.nodePath,
    name = metadata.name,
    schema = metadata.schema,
    type = service_node.objectType or metadata.metadataTypeName,
  }
end

---@param service_node table
---@return table
function M.from_service(service_node)
  local result = vim.deepcopy(service_node)
  assert(type(service_node.nodePath) == "string", "SQL Tools Service node has no nodePath")
  result.id = service_node.nodePath
  result.label = type(service_node.label) == "string" and service_node.label or result.id
  result.path_labels = { result.label }
  local node_type = type(service_node.objectType) == "string" and service_node.objectType
    or type(service_node.nodeType) == "string" and service_node.nodeType
    or nil
  result.icon = icon_for(node_type)
  result.children = nil
  result.loaded = service_node.isLeaf == true
  result.loading = false
  result.expanded = false
  result.object = public_object(service_node)
  return result
end

---@param parent table
---@param service_nodes table[]
function M.set_service_children(parent, service_nodes)
  local seen = {}
  parent.children = vim
    .iter(service_nodes or {})
    :filter(function(service_node)
      if type(service_node) ~= "table" or type(service_node.nodePath) ~= "string" or seen[service_node.nodePath] then
        return false
      end
      seen[service_node.nodePath] = true
      return true
    end)
    :map(M.from_service)
    :totable()
  for _, child in ipairs(parent.children) do
    child.path_labels = vim.deepcopy(parent.path_labels or { parent.label })
    child.path_labels[#child.path_labels + 1] = child.label
  end
  parent.loaded = true
  parent.loading = false
end

return M
