local shards = require("tests.integration.shards")

local T = MiniTest.new_set()

local function assigned_modules()
  local assigned = {}
  for _, group in ipairs({ "environment", "connected" }) do
    for _, module in ipairs(shards.modules(group)) do
      assert(not assigned[module], "Integration spec assigned more than once: " .. module)
      assigned[module] = true
    end
  end
  return assigned
end

T["Integration shards assign every spec exactly once"] = function()
  local assigned = assigned_modules()
  local specs = vim.fs.joinpath(vim.fn.getcwd(), "tests", "integration", "specs")

  for filename, file_type in vim.fs.dir(specs) do
    if file_type == "file" and filename:match("_spec%.lua$") then
      local module = filename:gsub("%.lua$", "")
      assert(assigned[module], "Integration spec is not assigned to a shard: " .. module)
      assigned[module] = nil
    end
  end

  assert(next(assigned) == nil, "Integration shard references a missing spec: " .. tostring(next(assigned)))
end

T["Integration shards reject unknown names"] = function()
  local ok, err = pcall(shards.modules, "connected", "missing")
  assert(not ok)
  assert(tostring(err):find("Unknown integration test shard: missing", 1, true))
end

return T
