local profiles = require("sqlserver.core.connection_profiles")

return {
  test_name = "Connection profiles should resolve and protect credentials",
  run_test_async = function()
    local resolved = profiles.resolve(
      {
        server = "${DB_HOST},1433",
        database = "app",
        authenticationType = "SqlLogin",
        user = "${DB_USER}",
        password = "${DB_PASSWORD}",
        azureAccountToken = "Token456",
      },
      "development",
      function(name)
        return ({ DB_HOST = "localhost", DB_USER = "sa", DB_PASSWORD = "Secret123" })[name]
      end
    )
    profiles.validate(resolved, "development")
    assert(resolved.server == "localhost,1433")
    assert(resolved.user == "sa" and resolved.password == "Secret123")
    assert(profiles.redact("Login using Secret123 failed", resolved) == "Login using [REDACTED] failed")
    assert(profiles.redact("Token456 was rejected", resolved) == "[REDACTED] was rejected")

    local failure = profiles.failure("Login failed for user with Secret123", resolved)
    assert(failure.message == "SQL Server authentication failed")
    assert(failure.operation_message == "Authentication failed")
    assert(not failure.diagnostic:find("Secret123", 1, true))
    assert(profiles.failure("certificate chain is not trusted").message == "SQL Server TLS validation failed")
    assert(profiles.failure("server was not found").message == "Could not reach SQL Server")
    assert(profiles.failure("RPC transport shut down").message == "SQL Tools Service became unavailable")

    local valid, err = pcall(profiles.resolve, { server = "${MISSING}" }, "broken", function()
      return nil
    end)
    assert(not valid and err:find("MISSING", 1, true))
    assert(not err:find("password", 1, true))

    valid, err = pcall(profiles.validate, { authenticationType = "SqlLogin" }, "broken")
    assert(not valid and err:find("server", 1, true))
    valid, err = pcall(profiles.validate, {
      server = "localhost",
      authenticationType = "SqlLogin",
      user = "sa",
    }, "broken")
    assert(not valid and err:find("password", 1, true))
  end,
}
