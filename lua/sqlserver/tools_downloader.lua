local utils = require("sqlserver.utils")

local M = {}

M.default_version = "5.0.20250530.2"

local platforms = {
  Windows = { arm64 = "win-arm64-net8.0.zip", x64 = "win-x64-net8.0.zip", x86 = "win-x86-net8.0.zip" },
  Linux = { arm64 = "linux-arm64-net8.0.tar.gz", x64 = "linux-x64-net8.0.tar.gz" },
  OSX = { arm64 = "osx-arm64-net8.0.tar.gz", x64 = "osx-x64-net8.0.tar.gz" },
}

function M.get_release(version, os, arch)
  version = version or M.default_version
  os = os or jit.os
  arch = arch or jit.arch
  if type(version) ~= "string" or not version:match("^[%w%.%-]+$") then
    error("tools_version must contain only letters, numbers, periods, and hyphens", 0)
  end
  if not platforms[os] then
    error("SQL Tools Service does not support operating system " .. tostring(os), 0)
  end
  local artifact = platforms[os][arch]
  if not artifact then
    error(string.format("SQL Tools Service does not support architecture %s on %s", tostring(arch), os), 0)
  end
  local filename = "Microsoft.SqlTools.ServiceLayer-" .. artifact
  return {
    version = version,
    filename = filename,
    url = string.format("https://github.com/microsoft/sqltoolsservice/releases/download/%s/%s", version, filename),
  }
end

function M.get_tools_download_url()
  return M.get_release().url
end

local function run_async(command)
  local co = coroutine.running()
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      utils.try_resume(co, result)
    end)
  end)
  return coroutine.yield()
end

local function remove(path)
  if vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path, "rf")
  end
end

local function command_error(command, result)
  local detail = vim.trim(result.stderr or "")
  if detail == "" then
    detail = "process exited with code " .. tostring(result.code)
  end
  return string.format("%s failed: %s", command, detail)
end

function M.download_tools_async(release, data_folder)
  if type(release) == "string" then
    release = { url = release, filename = release:match("[^/]+$") }
  end

  local suffix = string.format("%d-%d", vim.fn.getpid(), vim.uv.hrtime())
  local target = vim.fs.joinpath(data_folder, "sqltools")
  local staging = vim.fs.joinpath(data_folder, "sqltools.installing-" .. suffix)
  local backup = vim.fs.joinpath(data_folder, "sqltools.previous-" .. suffix)
  local archive = vim.fs.joinpath(data_folder, "sqltools.download-" .. suffix)
  local executable = vim.fs.joinpath(
    staging,
    jit.os == "Windows" and "MicrosoftSqlToolsServiceLayer.exe" or "MicrosoftSqlToolsServiceLayer"
  )

  remove(staging)
  remove(backup)
  vim.fn.mkdir(staging, "p")
  utils.log_info("Downloading SQL Tools Service...")

  local download
  if jit.os == "Windows" then
    download = run_async({
      "powershell",
      "-NoProfile",
      "-Command",
      "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri $args[0] -OutFile $args[1]",
      release.url,
      archive,
    })
  else
    download = run_async({ "curl", "-fsSL", release.url, "-o", archive })
  end
  if download.code ~= 0 then
    remove(staging)
    remove(archive)
    return false, command_error("SQL Tools Service download", download)
  end

  local extract
  if jit.os == "Windows" then
    extract = run_async({
      "powershell",
      "-NoProfile",
      "-Command",
      "Expand-Archive -LiteralPath $args[0] -DestinationPath $args[1]",
      archive,
      staging,
    })
  else
    extract = run_async({ "tar", "-xzf", archive, "-C", staging })
  end
  remove(archive)
  if extract.code ~= 0 then
    remove(staging)
    return false, command_error("SQL Tools Service extraction", extract)
  end
  if vim.fn.filereadable(executable) == 0 then
    remove(staging)
    return false, "SQL Tools Service archive did not contain the expected executable"
  end
  if jit.os ~= "Windows" then
    local chmod = run_async({ "chmod", "u+x", executable })
    if chmod.code ~= 0 then
      remove(staging)
      return false, command_error("Making SQL Tools Service executable", chmod)
    end
  end

  if vim.fn.isdirectory(target) == 1 then
    local moved, move_error = vim.uv.fs_rename(target, backup)
    if not moved then
      remove(staging)
      return false, "Could not preserve the existing SQL Tools Service install: " .. tostring(move_error)
    end
  end
  local installed, install_error = vim.uv.fs_rename(staging, target)
  if not installed then
    if vim.fn.isdirectory(backup) == 1 then
      vim.uv.fs_rename(backup, target)
    end
    remove(staging)
    return false, "Could not activate SQL Tools Service: " .. tostring(install_error)
  end
  remove(backup)
  utils.log_info("SQL Tools Service installed successfully")
  return true
end

return M
