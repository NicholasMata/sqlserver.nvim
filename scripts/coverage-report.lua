local root = vim.fn.getcwd()
local luacov_src = vim.fs.joinpath(root, ".tests", "deps", "luacov", "src")
package.path = table.concat({
  vim.fs.joinpath(luacov_src, "?.lua"),
  vim.fs.joinpath(luacov_src, "?", "init.lua"),
  package.path,
}, ";")

local runner = require("luacov.runner")
local configuration = runner.load_config()
local stats = require("luacov.stats")
local normalized = {}

local function relative_plugin_path(filename)
  filename = filename:gsub("\\", "/")
  local start = filename:find("lua/sqlserver/", 1, true)
  return start and filename:sub(start) or nil
end

local function merge_file(target, source)
  target.max = math.max(target.max, source.max)
  for line = 1, source.max do
    local hits = source[line]
    if hits then
      target[line] = (target[line] or 0) + hits
      target.max_hits = math.max(target.max_hits, target[line])
    end
  end
end

local function merge_stats_file(statsfile)
  local collected = stats.load(statsfile) or {}
  for filename, file_stats in pairs(collected) do
    local relative = relative_plugin_path(filename)
    if relative then
      normalized[relative] = normalized[relative] or { max = 0, max_hits = 0 }
      merge_file(normalized[relative], file_stats)
    end
  end
end

merge_stats_file(configuration.statsfile)

local shards = vim.fs.joinpath(root, "coverage", "shards")
if vim.uv.fs_stat(shards) then
  for filename, file_type in vim.fs.dir(shards, { depth = math.huge }) do
    if file_type == "file" and filename:match("luacov%.stats%.out$") then
      merge_stats_file(vim.fs.joinpath(shards, filename))
    end
  end
end

for filename, file_type in vim.fs.dir(vim.fs.joinpath(root, "lua", "sqlserver"), { depth = math.huge }) do
  if file_type == "file" and filename:sub(-4) == ".lua" then
    local relative = "lua/sqlserver/" .. filename:gsub("\\", "/")
    normalized[relative] = normalized[relative] or { max = 0, max_hits = 0 }
  end
end

stats.save(configuration.statsfile, normalized)
runner.run_report(configuration)

local report = assert(io.open(configuration.reportfile, "r"))
local contents = report:read("*a")
report:close()
local summary = contents:match("Summary\n=+\n\n(.+)$")
assert(summary, "LuaCov did not generate a coverage summary")

local summary_path = vim.fs.joinpath(root, "coverage", "summary.txt")
local summary_file = assert(io.open(summary_path, "w"))
summary_file:write(summary)
summary_file:close()
io.write(summary)
