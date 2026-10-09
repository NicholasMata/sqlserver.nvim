local generated_buffer = require("sqlserver.ui.generated_buffer")
local snapshot = require("sqlserver.plans.snapshot")
local M = {}
local next_id = 0

function M.prepare(plan)
  snapshot.validate(plan)
  next_id = next_id + 1
  local transaction = generated_buffer.create({ name = "sqlserver-plan://" .. next_id .. ".sqlplan", scratch = true })
  local ok, err = pcall(function()
    local original_lines = vim.split(plan.xml, "\n", { plain = true })
    transaction.set_lines(original_lines)
    local bufnr = transaction.bufnr
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].filetype = "xml"
    -- FileType handlers can configure XML formatting. Use Neovim's native
    -- formatting operator only when a formatter is configured, avoiding its
    -- default text-wrapping fallback on raw XML.
    vim.api.nvim_buf_call(bufnr, function()
      if vim.bo.formatexpr ~= "" or vim.bo.formatprg ~= "" then
        local formatted = pcall(vim.cmd, "silent keepjumps normal! gggqG")
        if not formatted then
          transaction.set_lines(original_lines)
        end
      end
    end)
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].readonly = true
    vim.bo[bufnr].modifiable = false
    vim.api.nvim_create_autocmd("BufWinEnter", {
      buffer = bufnr,
      callback = function(args)
        for _, winid in ipairs(vim.fn.win_findbuf(args.buf)) do
          vim.api.nvim_set_option_value("spell", false, { win = winid, scope = "local" })
        end
      end,
    })
    vim.b[bufnr].sqlserver_plan_info = {
      source_bufnr = plan.source_bufnr,
      execution_id = plan.execution_id,
      ordinal = plan.ordinal,
    }
    vim.b[bufnr].sqlserver_plan = vim.deepcopy(plan)
    local view = require("sqlserver.results.ui.view")
    vim.keymap.set("n", "]r", view.next_result, { buffer = bufnr, desc = "Next SQL result or plan" })
    vim.keymap.set("n", "[r", view.previous_result, { buffer = bufnr, desc = "Previous SQL result or plan" })
  end)
  if not ok then
    transaction.rollback()
    error(err, 0)
  end
  return transaction
end

function M.open(plan)
  local transaction = M.prepare(plan)
  vim.bo[transaction.bufnr].bufhidden = "wipe"
  local ok, err = pcall(function()
    -- Keep the transaction rollback-capable until presentation succeeds.
    vim.cmd("split")
    vim.api.nvim_set_current_buf(transaction.bufnr)
    vim.wo.winbar = snapshot.title(plan):gsub("%%", "%%%%")
  end)
  if not ok then
    transaction.rollback()
    error(err, 0)
  end
  transaction.commit(function() end)
  if plan.source_bufnr and vim.api.nvim_buf_is_valid(plan.source_bufnr) then
    local autocmd = vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = plan.source_bufnr,
      once = true,
      callback = function()
        if vim.api.nvim_buf_is_valid(transaction.bufnr) then
          vim.api.nvim_buf_delete(transaction.bufnr, { force = true })
        end
      end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = transaction.bufnr,
      once = true,
      callback = function()
        pcall(vim.api.nvim_del_autocmd, autocmd)
      end,
    })
  end
  return { bufnr = transaction.bufnr }
end

return M
