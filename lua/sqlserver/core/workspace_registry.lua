local M = {}

local workspaces = {}

---@param bufnr integer
---@param workspace SqlServerWorkspace
function M.attach(bufnr, workspace)
	assert(type(bufnr) == "number", "A buffer number is required")
	assert(workspace, "A workspace is required")
	workspaces[bufnr] = workspace
end

---@param bufnr? integer
---@return SqlServerWorkspace?
function M.get(bufnr)
	if bufnr == nil or bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	return workspaces[bufnr]
end

---@param bufnr integer
---@return SqlServerWorkspace?
function M.detach(bufnr)
	local workspace = workspaces[bufnr]
	workspaces[bufnr] = nil
	return workspace
end

---@param owner_uri string
---@return SqlServerWorkspace?
function M.find_by_owner_uri(owner_uri)
	for _, workspace in pairs(workspaces) do
		if workspace.owner_uri == owner_uri then
			return workspace
		end
	end
end

---@return fun(): integer, SqlServerWorkspace
function M.iter()
	return pairs(workspaces)
end

return M
