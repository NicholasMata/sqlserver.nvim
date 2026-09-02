# Connection profiles

Each connection JSON object can contain the following properties (taken from the
[SQL Tools Service source code](https://github.com/microsoft/sqltoolsservice/blob/main/src/Microsoft.SqlTools.ServiceLayer/Connection/Contracts/ConnectionDetails.cs)).

Use `${ENVIRONMENT_VARIABLE}` anywhere inside a string value to keep secrets or
machine-specific values out of the file. Variables are resolved immediately
before connecting, and a missing variable stops the connection with a profile-
specific error. For example:

```json
{
  "development": {
    "server": "${SQLSERVER_HOST}",
    "database": "ApplicationDb",
    "authenticationType": "SqlLogin",
    "user": "${SQLSERVER_USER}",
    "password": "${SQLSERVER_PASSWORD}",
    "trustServerCertificate": true
  }
}
```

Every profile requires a non-empty `server`. `SqlLogin` profiles also require
`user` and either `password` or `promptForPassword`. Resolved passwords are
redacted from plugin-generated connection errors.

| Name                       | Allowed Values                                                                                                        | Description                                                                                                                                      |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `server`                   | `string`                                                                                                              | The name of the SQL Server instance to connect to.                                                                                               |
| `database`                 | `string`                                                                                                              | The name of the target database.                                                                                                                 |
| `authenticationType`       | `"Integrated"`, `"SqlLogin"`, `"AzureMFA"`, `"dstsAuth"`, `"ActiveDirectoryInteractive"`, `"ActiveDirectoryPassword"` | The type of authentication to use.                                                                                                               |
| `user`                     | `string`                                                                                                              | The user name used for authentication.                                                                                                           |
| `password`                 | `string`                                                                                                              | The password used for the connection.                                                                                                            |
| `trustServerCertificate`   | `bool`                                                                                                                | Specifies whether to bypass certificate chain validation while encrypting the channel.                                                           |
| `encrypt`                  | `"Optional"`, `"Mandatory"`, `"Strict"`, `"True"`, `"False"`, `"Yes"`, `"No"`                                         | Determines the encryption mode for SSL used between client and server. Boolean `true` and `false` are also supported for backward compatibility. |
| `connectTimeout`           | `int`                                                                                                                 | The time, in seconds, to wait for a connection to open before timing out.                                                                        |
| `commandTimeout`           | `int`                                                                                                                 | The time, in seconds, to wait for a command to complete before timing out.                                                                       |
| `pooling`                  | `bool`                                                                                                                | Determines whether connections are pooled or explicitly opened on each request.                                                                  |
| `maxPoolSize`              | `int`                                                                                                                 | The maximum number of connections allowed in the connection pool.                                                                                |
| `minPoolSize`              | `int`                                                                                                                 | The minimum number of connections maintained in the connection pool.                                                                             |
| `applicationName`          | `string`                                                                                                              | The name of the application associated with the connection.                                                                                      |
| `workstationId`            | `string`                                                                                                              | The name of the workstation initiating the connection.                                                                                           |
| `multipleActiveResultSets` | `bool`                                                                                                                | Enables support for multiple active result sets (MARS).                                                                                          |
| `persistSecurityInfo`      | `bool`                                                                                                                | Indicates whether security-sensitive information (e.g., the password) is retained once the connection is open.                                   |
| `applicationIntent`        | `string`                                                                                                              | Specifies the intended workload type when connecting to an availability group.                                                                   |
| `currentLanguage`          | `string`                                                                                                              | The language setting for the SQL Server session.                                                                                                 |
| `connectRetryCount`        | `int`                                                                                                                 | The number of retry attempts after detecting an idle connection failure.                                                                         |
| `connectRetryInterval`     | `int`                                                                                                                 | The time, in seconds, between retry attempts after an idle connection failure.                                                                   |
| `failoverPartner`          | `string`                                                                                                              | The name or address of a partner server for failover scenarios.                                                                                  |
| `multiSubnetFailover`      | `bool`                                                                                                                | Enables faster failover when connecting to availability groups across subnets.                                                                   |
| `loadBalanceTimeout`       | `int`                                                                                                                 | The minimum time, in seconds, a connection remains in the pool before being destroyed.                                                           |
| `packetSize`               | `int`                                                                                                                 | The size, in bytes, of the network packets used to communicate with SQL Server.                                                                  |
| `attachDbFilename`         | `string`                                                                                                              | The full path to a primary data file for attaching a database.                                                                                   |
| `port`                     | `int`                                                                                                                 | The port number used for the TCP/IP connection.                                                                                                  |
| `columnEncryptionSetting`  | `string`                                                                                                              | Specifies whether Always Encrypted is enabled for the connection.                                                                                |
| `secureEnclaves`           | `string`                                                                                                              | Specifies whether Always Encrypted with Secure Enclaves is enabled for the connection.                                                           |
| `attestationProtocol`      | `string`                                                                                                              | The protocol used for enclave attestation.                                                                                                       |
| `enclaveAttestationUrl`    | `string`                                                                                                              | The URL used for enclave attestation with Always Encrypted.                                                                                      |
| `hostNameInCertificate`    | `string`                                                                                                              | The expected host name in the certificate for validation when encryption is enabled.                                                             |
| `replication`              | `bool`                                                                                                                | Specifies whether replication is supported using this connection.                                                                                |
| `typeSystemVersion`        | `string`                                                                                                              | Specifies the expected type system version.                                                                                                      |
| `groupId`                  | `string`                                                                                                              | The group identifier for the connection.                                                                                                         |
| `connectionName`           | `string`                                                                                                              | A user-defined name for the connection.                                                                                                          |
| `databaseDisplayName`      | `string`                                                                                                              | A display name for the database, used for UI or documentation.                                                                                   |
| `azureAccountToken`        | `string`                                                                                                              | The Azure AD access token used for authentication.                                                                                               |
| `expiresOn`                | `int`                                                                                                                 | The expiration time (as a Unix timestamp) for the Azure access token.                                                                            |
