local sqlserver = require("sqlserver")
local test_utils = require("tests.utils")

local function select_object(object_type, name, collision_choice)
  test_utils.ui_select_fake(function(item)
    local matches = item.objectType == object_type and item.metadata and item.metadata.name == name
    if matches and collision_choice then
      test_utils.ui_select_fake(collision_choice)
    end
    return matches
  end)
end

local function run_action_async(action)
  local co = coroutine.running()
  local completed = false
  action(function()
    completed = true
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co)
    end
  end)
  vim.defer_fn(function()
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co)
    end
  end, 60000)
  coroutine.yield()
  assert(completed, "Object scripting did not complete within one minute")
  test_utils.defer_async(500)
  local bufnr = vim.api.nvim_get_current_buf()
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"), bufnr
end

return {
  test_name = "Object actions should build queries and definitions",
  run_test_async = function()
    select_object("StoredProcedure", "GetCar")
    local procedure_query, procedure_bufnr = run_action_async(sqlserver.find_object)
    assert(procedure_query:find("GetCar", 1, true))
    assert(procedure_query:upper():find("EXEC", 1, true))
    assert(not procedure_query:upper():find("CREATE", 1, true))
    vim.api.nvim_buf_delete(procedure_bufnr, { force = true })

    for _, expected in ipairs({
      { object_type = "ScalarValuedFunction", name = "GetCarMake" },
      { object_type = "TableValuedFunction", name = "CarsForPerson" },
    }) do
      select_object(expected.object_type, expected.name)
      local query, query_bufnr = run_action_async(sqlserver.find_object)
      assert(query:find(expected.name, 1, true))
      assert(query:upper():find("SELECT", 1, true))
      vim.api.nvim_buf_delete(query_bufnr, { force = true })
    end

    local definitions = {
      { object_type = "Table", name = "Car", keyword = "CREATE TABLE" },
      { object_type = "View", name = "CarView", keyword = "CREATE VIEW" },
      { object_type = "StoredProcedure", name = "GetCar", keyword = "CREATE PROCEDURE" },
      { object_type = "ScalarValuedFunction", name = "GetCarMake", keyword = "CREATE FUNCTION" },
      { object_type = "TableValuedFunction", name = "CarsForPerson", keyword = "CREATE FUNCTION" },
    }
    for _, expected in ipairs(definitions) do
      select_object(expected.object_type, expected.name)
      local definition, definition_bufnr = run_action_async(sqlserver.show_object_definition)
      assert(definition:find(expected.name, 1, true))
      assert(definition:upper():find(expected.keyword, 1, true))
      assert(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(definition_bufnr), ":t") == "dbo." .. expected.name .. ".sql")
      assert(vim.b[definition_bufnr].sqlserver_object.name == expected.name)
      assert(vim.b[definition_bufnr].sqlserver_object.schema == "dbo")
      vim.api.nvim_buf_delete(definition_bufnr, { force = true })
    end

    select_object("View", "CarView")
    local _, original_definition = run_action_async(sqlserver.show_object_definition)
    select_object("View", "CarView", "Focus open buffer")
    local _, focused_definition = run_action_async(sqlserver.show_object_definition)
    assert(focused_definition == original_definition)

    select_object("View", "CarView", "Open another buffer")
    local _, duplicate_definition = run_action_async(sqlserver.show_object_definition)
    assert(duplicate_definition ~= original_definition)
    assert(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(duplicate_definition), ":t") == "dbo.CarView (2).sql")
    vim.api.nvim_buf_delete(original_definition, { force = true })
    vim.api.nvim_buf_delete(duplicate_definition, { force = true })
  end,
}
