local sqlserver = require("sqlserver")
local query_selection = require("sqlserver.core.query_selection")
local workspace_registry = require("sqlserver.core.workspace_registry")
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

local function execute(request)
  await(function(callback)
    sqlserver.execute({ bufnr = 0, request = request }, callback)
  end)
  utils.wait_for_schedule_async()
end

local function replace_document(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  utils.wait_for_schedule_async()
end

local function error_event(workspace, label)
  for _, event in ipairs(workspace.get_activity()) do
    if event.kind == "message" and event.message:find(label, 1, true) then
      return event
    end
  end
  return nil, nil
end

return {
  test_name = "Query errors should report source document line numbers",
  run_test_async = function()
    local workspace = assert(workspace_registry.get(0))

    replace_document({
      "-- cursor padding 1",
      "-- cursor padding 2",
      "-- cursor padding 3",
      "THROW 50000, 'cursor line error', 1;",
      "THROW 50000, 'cursor unexecuted error', 1;",
    })
    vim.api.nvim_win_set_cursor(0, { 4, 10 })
    execute(query_selection.statement(0))

    replace_document({
      "-- line visual padding 1",
      "-- line visual padding 2",
      "-- line visual padding 3",
      "-- line visual padding 4",
      "THROW 50000, 'line visual error', 1;",
      "THROW 50000, 'line visual unexecuted error', 1;",
    })
    vim.fn.setpos("'<", { 0, 5, 1, 0 })
    vim.fn.setpos("'>", { 0, 5, 1, 0 })
    execute(query_selection.visual(0, "V"))

    local character_target = "THROW 50000, 'character visual error', 1;"
    local character_document = "/* 😀 */ " .. character_target .. " THROW 50000, 'character unexecuted error', 1;"
    replace_document({
      "-- character visual padding 1",
      "-- character visual padding 2",
      character_document,
    })
    local character_start = assert(character_document:find(character_target, 1, true))
    vim.fn.setpos("'<", { 0, 3, character_start, 0 })
    vim.fn.setpos("'>", { 0, 3, character_start + #character_target - 1, 0 })
    execute(query_selection.visual(0, "v"))

    replace_document({
      "SELECT 1;",
      "-- buffer padding 2",
      "-- buffer padding 3",
      "-- buffer padding 4",
      "-- buffer padding 5",
      "THROW 50000, 'buffer line error', 1;",
    })
    execute(query_selection.buffer(0))

    local expectations = {
      { label = "cursor line error", line = 3 },
      { label = "line visual error", line = 4 },
      { label = "character visual error", line = 2 },
      { label = "buffer line error", line = 5 },
    }
    local failures = {}
    for _, expectation in ipairs(expectations) do
      local event = error_event(workspace, expectation.label)
      local selection = event and event.error_selection
      if not event then
        table.insert(failures, "No error activity contained " .. expectation.label)
      elseif not selection then
        table.insert(failures, "No errorSelection was provided for " .. expectation.label)
      elseif selection.startLine ~= expectation.line then
        table.insert(
          failures,
          string.format(
            "%s should identify zero-based source line %d, but was %s",
            expectation.label,
            expectation.line,
            vim.inspect(selection)
          )
        )
      end
    end
    assert(#failures == 0, table.concat(failures, "\n"))
  end,
}
