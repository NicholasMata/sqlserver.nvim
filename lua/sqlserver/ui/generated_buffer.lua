local M = {}

---@param opts? { listed?: boolean, scratch?: boolean, name?: string, filetype?: string }
function M.create(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(opts.listed ~= false, opts.scratch == true)
  local finished = false

  if opts.name then
    vim.api.nvim_buf_set_name(bufnr, opts.name)
  end
  if opts.filetype then
    vim.api.nvim_set_option_value("filetype", opts.filetype, { buf = bufnr })
  end

  local transaction = { bufnr = bufnr }

  function transaction.set_lines(lines)
    assert(not finished, "Generated buffer transaction is already finished")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  function transaction.commit(present)
    if finished or not vim.api.nvim_buf_is_valid(bufnr) then
      return false
    end
    finished = true
    if present then
      present(bufnr)
    else
      vim.api.nvim_set_current_buf(bufnr)
    end
    return true
  end

  function transaction.rollback()
    if finished then
      return false
    end
    finished = true
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    return true
  end

  return transaction
end

return M
