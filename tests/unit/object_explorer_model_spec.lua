local explorer = require("sqlserver.objects.explorer")

local T = MiniTest.new_set()

T["Object Explorer preserves SQL Tools Service nodes"] = function()
  local source = {
    nodePath = "server/TestDb/Tables",
    parentNodePath = "server/TestDb",
    label = "Tables",
    objectType = "Tables",
    nodeType = "Folder",
    isLeaf = false,
    nodeSubType = "UserTables",
    nodeStatus = "Available",
    errorMessage = "Metadata is incomplete",
    filterableProperties = { { name = "Name" } },
  }
  local node = explorer.from_service(source)
  assert(node.id == source.nodePath and node.nodePath == source.nodePath)
  assert(node.parentNodePath == source.parentNodePath and node.objectType == "Tables")
  assert(vim.deep_equal(node.filterableProperties, source.filterableProperties))
  assert(node.nodeSubType == "UserTables")
  assert(node.nodeStatus == "Available")
  assert(node.errorMessage == "Metadata is incomplete")
  assert(vim.deep_equal(explorer.details(node), { "UserTables", "Available", "Metadata is incomplete" }))
  assert(node.children == nil and not node.loaded and not node.loading and not node.expanded)
  assert(node.object == nil)
end

T["Object Explorer exposes supported service objects"] = function()
  local node = explorer.from_service({
    nodePath = "server/TestDb/Tables/dbo.Person",
    label = "dbo.Person",
    objectType = "Table",
    isLeaf = false,
    metadata = { name = "Person", schema = "dbo", metadataTypeName = "Table" },
  })
  assert(vim.deep_equal(node.object, {
    id = node.nodePath,
    name = "Person",
    schema = "dbo",
    type = "Table",
  }))
end

T["Object Explorer attaches service children in service order"] = function()
  local parent = explorer.from_service({
    nodePath = "server/TestDb/Tables/dbo.Person",
    label = "dbo.Person",
    objectType = "Table",
    isLeaf = false,
  })
  explorer.set_service_children(parent, {
    { nodePath = parent.nodePath .. "/Columns", label = "Columns", objectType = "Columns", isLeaf = false },
    { nodePath = parent.nodePath .. "/Keys", label = "Keys", objectType = "Keys", isLeaf = false },
  })
  assert(parent.loaded and not parent.loading)
  assert(parent.children[1].label == "Columns" and parent.children[2].label == "Keys")
  assert(parent.children[1].nodePath == parent.nodePath .. "/Columns")
  assert(vim.deep_equal(parent.children[1].path_labels, { parent.label, "Columns" }))
end

T["Object Explorer deduplicates service children by node path"] = function()
  local parent = explorer.from_service({
    nodePath = "server/TestDb/Tables",
    label = "Tables",
    objectType = "Folder",
    isLeaf = false,
  })
  explorer.set_service_children(parent, {
    { nodePath = parent.nodePath .. "/dbo.Person", label = "dbo.Person", objectType = "Table", isLeaf = false },
    { nodePath = parent.nodePath .. "/dbo.Car", label = "dbo.Car", objectType = "Table", isLeaf = false },
    { nodePath = parent.nodePath .. "/dbo.Person", label = "dbo.Person", objectType = "Table", isLeaf = false },
  })

  assert(#parent.children == 2)
  assert(parent.children[1].label == "dbo.Person" and parent.children[2].label == "dbo.Car")
end

T["Object Explorer accepts empty service children"] = function()
  local node =
    explorer.from_service({ nodePath = "server/TestDb/Views/dbo.Empty", label = "dbo.Empty", isLeaf = false })
  explorer.set_service_children(node, {})
  assert(node.loaded and #node.children == 0)
end

T["Object Explorer normalizes null service labels for searching"] = function()
  local node = explorer.from_service({
    nodePath = "server/TestDb/Unknown",
    label = vim.NIL,
    objectType = vim.NIL,
    nodeType = vim.NIL,
    isLeaf = true,
  })
  assert(node.label == node.nodePath)
  assert(type(node.label) == "string" and type(node.icon) == "string")
end

return T
