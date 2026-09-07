local sqlserver = require("sqlserver")
local query_selection = require("sqlserver.core.query_selection")
local utils = require("sqlserver.utils")

local function await(invoke)
  local co = coroutine.running()
  local completed = false
  local value
  local failure
  invoke(function(result, err)
    completed = true
    value = result
    failure = err
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co)
    end
  end)
  if not completed then
    coroutine.yield()
  end
  assert(not failure, failure and (failure.diagnostic or failure.message))
  return value
end

local function execute(opts)
  return await(function(callback)
    sqlserver.execute(opts, callback)
  end)
end

local function replace_document(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  utils.wait_for_schedule_async()
end

local function reset_audit()
  execute({ bufnr = 0, text = "TRUNCATE TABLE #ExecutionScopeAudit;" })
end

local function assert_audit(expected)
  local execution = execute({
    bufnr = 0,
    text = "SELECT Label FROM #ExecutionScopeAudit ORDER BY ID;",
  })
  assert(#execution.result_sets == 1, "Audit query should return exactly one result set")
  local actual = vim
    .iter(execution.result_sets[1].rows)
    :map(function(row)
      return row[1].display_value
    end)
    :totable()
  assert(
    vim.deep_equal(actual, expected),
    "Expected only " .. vim.inspect(expected) .. " to execute, got " .. vim.inspect(actual)
  )
end

local T = MiniTest.new_set()

T["Execution scopes should run only their intended SQL"] = require("tests.helpers").async(function()
  execute({
    bufnr = 0,
    text = [[
IF OBJECT_ID('tempdb..#ExecutionScopeAudit') IS NOT NULL
  DROP TABLE #ExecutionScopeAudit;
CREATE TABLE #ExecutionScopeAudit (
  ID int IDENTITY PRIMARY KEY,
  Label nvarchar(50) NOT NULL
);]],
  })

  replace_document({
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'cursor-before');",
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'cursor-target');",
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'cursor-after');",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 12 })
  execute({ bufnr = 0, request = query_selection.statement(0) })
  assert_audit({ "cursor-target" })

  reset_audit()
  replace_document({
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'visual-before');",
    "INSERT INTO #ExecutionScopeAudit (Label)",
    "VALUES (N'visual-target');",
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'visual-after');",
  })
  vim.fn.setpos("'<", { 0, 2, 1, 0 })
  vim.fn.setpos("'>", { 0, 3, 27, 0 })
  execute({ bufnr = 0, request = query_selection.visual(0, "V") })
  assert_audit({ "visual-target" })

  reset_audit()
  local character_target = "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'character-target');"
  local character_document = "/* 😀 */ "
    .. character_target
    .. " INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'character-after');"
  replace_document({ character_document })
  local character_start = assert(character_document:find(character_target, 1, true))
  vim.fn.setpos("'<", { 0, 1, character_start, 0 })
  vim.fn.setpos("'>", { 0, 1, character_start + #character_target - 1, 0 })
  execute({ bufnr = 0, request = query_selection.visual(0, "v") })
  assert_audit({ "character-target" })

  reset_audit()
  replace_document({
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'buffer-first');",
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'buffer-second');",
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'buffer-third');",
  })
  execute({ bufnr = 0, request = query_selection.buffer(0) })
  assert_audit({ "buffer-first", "buffer-second", "buffer-third" })

  reset_audit()
  replace_document({
    "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'document-not-requested');",
  })
  execute({
    bufnr = 0,
    text = "INSERT INTO #ExecutionScopeAudit (Label) VALUES (N'api-text');",
  })
  assert_audit({ "api-text" })

  execute({ bufnr = 0, text = "DROP TABLE #ExecutionScopeAudit;" })
end)

return T
