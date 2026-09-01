local get_plugin_root = function()
  local current_file = debug.getinfo(1, "S").source:sub(2)
  local abs_path = vim.fn.fnamemodify(current_file, ":p")
  local current_dir = vim.fs.dirname(abs_path)

  return vim.fs.find("sqlserver.nvim", {
    upward = true,
    path = current_dir,
    type = "directory",
  })[1]
end

local function print_without_prompt(message)
  io.stdout:write(message .. "\n")
end

-- Prepend plugin root to runtimepath
vim.opt.rtp:prepend(get_plugin_root())
-- Disable swap files to avoid test errors
vim.opt.swapfile = false
-- Don't have autocomplete auto insert selections
vim.o.completeopt = "menu,menuone,noselect,noinsert"

local src = vim.fn.stdpath("state")
print_without_prompt("nvim state path: " .. src)
vim.lsp.log.set_level("debug")

local function copy_state_folder()
  if vim.env.GITHUB_ACTIONS == "true" then
    local src = vim.fn.stdpath("state")
    print_without_prompt("nvim state path: " .. src)
    local dst = "nvim-state-dump"

    if vim.fn.has("win32") == 1 then
      vim.fn.system({ "xcopy", "/E", "/I", "/Y", src, dst })
    else
      vim.fn.system({ "cp", "-r", src, dst })
    end
  end
end

local function run_test(test)
  print_without_prompt("=== Running: " .. test.test_name .. " ===")
  local success, err = pcall(test.run_test_async)

  if not success then
    print_without_prompt("\n" .. test.test_name .. " FAILED: " .. err)
    copy_state_folder()
    os.exit(1)
  else
    print_without_prompt("\nTest passed\n")
  end
end

local suite_name = vim.env.SQLSERVER_TEST_SUITE or "unit"
local suites = require("tests.suites")
local suite = suites[suite_name]
assert(suite, "Unknown SQLSERVER_TEST_SUITE: " .. suite_name)

if suite_name == "integration" then
  for _, name in ipairs({ "DbServer", "DbDatabase", "DbUser", "DbPassword" }) do
    assert(vim.env[name] and vim.env[name] ~= "", name .. " is required for integration tests")
  end
end

local tests = vim
  .iter(suite)
  :map(function(module)
    return require(module)
  end)
  :totable()

print_without_prompt("Running " .. suite_name .. " test suite")

coroutine.resume(coroutine.create(function()
  for _, test in ipairs(tests) do
    run_test(test)
  end
  os.exit(0)
end))
