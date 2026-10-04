local snapshot = require("sqlserver.plans.snapshot")
local M = {}

function M.save(plan, path, overwrite)
  snapshot.validate(plan)
  assert(type(path) == "string" and path ~= "", "An export path is required")
  local existing = vim.uv.fs_lstat(path)
  if existing and (existing.type ~= "file" or not overwrite) then
    error({ code = "plan_export_failed", message = "Export path exists; choose a new file or allow overwrite" }, 0)
  end
  local target = overwrite and (path .. ".sqlserver-" .. vim.uv.os_getpid() .. "-" .. vim.uv.hrtime()) or path
  local fd, open_error = vim.uv.fs_open(target, "wx", 420)
  if not fd then
    error({ code = "plan_export_failed", message = "Could not open plan export: " .. tostring(open_error) }, 0)
  end
  local ok, failure = pcall(function()
    local offset = 0
    while offset < #plan.xml do
      local written, err = vim.uv.fs_write(fd, plan.xml:sub(offset + 1), offset)
      assert(written and written > 0, err or "Could not write plan export")
      offset = offset + written
    end
    assert(vim.uv.fs_fsync(fd))
  end)
  local closed, close_error = vim.uv.fs_close(fd)
  if not ok or not closed then
    vim.uv.fs_unlink(target)
    error(
      { code = "plan_export_failed", message = "Could not write plan export: " .. tostring(failure or close_error) },
      0
    )
  end
  if overwrite then
    local renamed, rename_error = vim.uv.fs_rename(target, path)
    if not renamed then
      vim.uv.fs_unlink(target)
      error({ code = "plan_export_failed", message = "Could not replace plan export: " .. tostring(rename_error) }, 0)
    end
  end
  return { path = path, format = "sqlplan" }
end

return M
