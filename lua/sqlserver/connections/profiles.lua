local M = {}

local function profile_error(name, message)
  error(string.format("Connection profile '%s' %s", name, message), 0)
end

---@param value any
---@param profile_name string
---@param path string
---@param getenv fun(name: string): string?
---@return any
local function resolve_value(value, profile_name, path, getenv)
  if type(value) == "table" then
    local resolved = {}
    for key, child in pairs(value) do
      resolved[key] = resolve_value(child, profile_name, path .. "." .. tostring(key), getenv)
    end
    return resolved
  end
  if type(value) ~= "string" then
    return value
  end

  return (
    value:gsub("%${([%a_][%w_]*)}", function(variable)
      local replacement = getenv(variable)
      if replacement == nil then
        profile_error(
          profile_name,
          string.format("option '%s' references missing environment variable %s", path, variable)
        )
      end
      return replacement
    end)
  )
end

---@param path string
---@return table?
function M.load(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  local ok, profiles = pcall(vim.json.decode, content)
  if not (ok and type(profiles) == "table" and not vim.islist(profiles)) then
    error("The connections file must contain a valid JSON object", 0)
  end
  for name, profile in pairs(profiles) do
    if type(name) ~= "string" or type(profile) ~= "table" or vim.islist(profile) then
      error("Each connection profile must be a named JSON object", 0)
    end
  end
  return profiles
end

---@param profile table
---@param name string
---@param getenv? fun(name: string): string?
---@return table
function M.resolve(profile, name, getenv)
  if type(profile) ~= "table" or vim.islist(profile) then
    profile_error(name, "must be an object")
  end
  return resolve_value(profile, name, "connection", getenv or os.getenv)
end

---@param profile table
---@param name string
function M.validate(profile, name)
  if type(profile.server) ~= "string" or vim.trim(profile.server) == "" then
    profile_error(name, "requires a non-empty 'server'")
  end

  if profile.authenticationType == "SqlLogin" then
    if type(profile.user) ~= "string" or vim.trim(profile.user) == "" then
      profile_error(name, "requires a non-empty 'user' for SqlLogin authentication")
    end
    if not profile.promptForPassword and (type(profile.password) ~= "string" or profile.password == "") then
      profile_error(name, "requires 'password' or promptForPassword for SqlLogin authentication")
    end
  end
end

---@param message any
---@param profile? table
---@return string
function M.redact(message, profile)
  message = tostring(message)
  for _, key in ipairs({ "password", "azureAccountToken" }) do
    local secret = profile and profile[key]
    if type(secret) == "string" and secret ~= "" then
      message = message:gsub(vim.pesc(secret), "[REDACTED]")
    end
  end
  return message
end

---@param message any
---@param profile? table
---@return table
function M.failure(message, profile)
  local diagnostic = M.redact(message, profile)
  local normalized = diagnostic:lower()
  local user_message = "Could not connect to SQL Server"
  local operation_message = "Connection failed"

  if normalized:find("login failed", 1, true) or normalized:find("authentication", 1, true) then
    user_message = "SQL Server authentication failed"
    operation_message = "Authentication failed"
  elseif
    normalized:find("certificate", 1, true)
    or normalized:find("ssl", 1, true)
    or normalized:find("tls", 1, true)
  then
    user_message = "SQL Server TLS validation failed"
    operation_message = "TLS validation failed"
  elseif
    normalized:find("server was not found", 1, true)
    or normalized:find("network-related", 1, true)
    or normalized:find("actively refused", 1, true)
    or normalized:find("no such host", 1, true)
  then
    user_message = "Could not reach SQL Server"
    operation_message = "Server unreachable"
  elseif
    normalized:find("shut down", 1, true)
    or normalized:find("transport", 1, true)
    or normalized:find("rpc", 1, true)
  then
    user_message = "SQL Tools Service became unavailable"
    operation_message = "SQL Tools Service unavailable"
  end

  return {
    message = user_message,
    diagnostic = diagnostic,
    operation_message = operation_message,
  }
end

---@param profile table
---@return table
function M.public_view(profile)
  local view = vim.deepcopy(profile)
  view.password = nil
  view.azureAccountToken = nil
  return view
end

return M
