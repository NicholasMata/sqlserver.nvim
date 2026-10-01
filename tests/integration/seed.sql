USE master;
GO
IF DB_ID(N'TestDbA') IS NOT NULL
BEGIN
  ALTER DATABASE TestDbA SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE TestDbA;
END;
IF DB_ID(N'TestDbB') IS NOT NULL
BEGIN
  ALTER DATABASE TestDbB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE TestDbB;
END;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'sqlserver_nvim_restricted')
  DROP LOGIN [sqlserver_nvim_restricted];
GO

CREATE DATABASE TestDbA;
GO
USE TestDbA;
CREATE TABLE Person
(
  ID INT IDENTITY(1,1) PRIMARY KEY,
  [Name] NVARCHAR(50),
  Age INT
);
INSERT INTO Person
  ([Name], Age)
VALUES
  ('Bob', 40),
  ('Amy', 65);
GO
CREATE TABLE PersonNonAscii
(
  ID INT IDENTITY(1,1) PRIMARY KEY,
  [Name] NVARCHAR(50),
  Age INT
);
INSERT INTO PersonNonAscii
  ([Name], Age)
VALUES
  ('Very Long Name', 40),
  (N'Bøb', 40),
  ('Bob' + CHAR(10), 40),
  (N'Bob' + NCHAR(8203), 40);
GO

CREATE DATABASE TestDbB;
GO
USE TestDbB;
CREATE TABLE Car
(
  ID INT IDENTITY(1,1) PRIMARY KEY,
  Make NVARCHAR(50),
  PersonId INT
);
ALTER TABLE Car
  ADD CONSTRAINT CK_Car_PersonId CHECK (PersonId > 0);
CREATE INDEX IX_Car_Make ON Car (Make);
GO
CREATE TRIGGER CarInsertTrigger
ON Car
AFTER INSERT
AS
BEGIN
  SET NOCOUNT ON;
END;
GO
INSERT INTO Car
  (Make, PersonId)
VALUES
  ('Merc', 1),
  ('Ford', 1),
  ('Hyundai', 2);
DISABLE TRIGGER CarInsertTrigger ON Car;
GO
CREATE VIEW CarView AS
SELECT ID, Make, PersonId
FROM dbo.Car;
GO
CREATE PROCEDURE GetCar
  @ID INT
AS
BEGIN
  SELECT ID, Make, PersonId
  FROM dbo.Car
  WHERE ID = @ID;
END;
GO
CREATE FUNCTION GetCarMake(@ID INT)
RETURNS NVARCHAR(50)
AS
BEGIN
  RETURN (SELECT Make FROM dbo.Car WHERE ID = @ID);
END;
GO
CREATE FUNCTION CarsForPerson(@PersonID INT)
RETURNS TABLE
AS
RETURN
(
  SELECT ID, Make, PersonId
  FROM dbo.Car
  WHERE PersonId = @PersonID
);
GO
USE master;
CREATE LOGIN [sqlserver_nvim_restricted]
  WITH PASSWORD = 'Restricted_Password_123';
GO
USE TestDbB;
CREATE USER [sqlserver_nvim_restricted]
  FOR LOGIN [sqlserver_nvim_restricted];
GRANT SELECT ON OBJECT::dbo.Car TO [sqlserver_nvim_restricted];
GRANT VIEW DEFINITION ON OBJECT::dbo.Car TO [sqlserver_nvim_restricted];
GO

USE master;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'sqlserver_nvim_agent_limited')
  CREATE LOGIN [sqlserver_nvim_agent_limited]
    WITH PASSWORD = N'Test_Agent_Limited_123', CHECK_POLICY = OFF;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'sqlserver_nvim_agent_empty')
  CREATE LOGIN [sqlserver_nvim_agent_empty]
    WITH PASSWORD = N'Test_Agent_Empty_123', CHECK_POLICY = OFF;
GO
USE msdb;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'sqlserver_nvim_agent_limited')
  CREATE USER [sqlserver_nvim_agent_limited] FOR LOGIN [sqlserver_nvim_agent_limited];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'sqlserver_nvim_agent_empty')
  CREATE USER [sqlserver_nvim_agent_empty] FOR LOGIN [sqlserver_nvim_agent_empty];
IF NOT EXISTS (
  SELECT 1 FROM sys.database_role_members
  WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'SQLAgentUserRole')
    AND member_principal_id = DATABASE_PRINCIPAL_ID(N'sqlserver_nvim_agent_empty')
)
  ALTER ROLE [SQLAgentUserRole] ADD MEMBER [sqlserver_nvim_agent_empty];
GO

USE msdb;
DECLARE @agent_starting int = 1;
DECLARE @agent_waits int = 0;
WHILE @agent_starting = 1 AND @agent_waits < 60
BEGIN
  BEGIN TRY
    EXEC @agent_starting = dbo.sp_is_sqlagent_starting;
  END TRY
  BEGIN CATCH
    IF ERROR_NUMBER() <> 14258 THROW;
  END CATCH;
  IF @agent_starting = 1
  BEGIN
    WAITFOR DELAY '00:00:01';
    SET @agent_waits = @agent_waits + 1;
  END;
END;
IF @agent_starting = 1
  THROW 50000, 'SQL Agent did not finish starting', 1;
GO

USE msdb;
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'sqlserver.nvim fixture linked alert')
  EXEC dbo.sp_delete_alert @name = N'sqlserver.nvim fixture linked alert';
IF EXISTS (SELECT 1 FROM dbo.sysalerts WHERE name = N'sqlserver.nvim fixture independent alert')
  EXEC dbo.sp_delete_alert @name = N'sqlserver.nvim fixture independent alert';
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sqlserver.nvim fixture history')
  EXEC dbo.sp_delete_job @job_name = N'sqlserver.nvim fixture history', @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'sqlserver.nvim fixture no history')
  EXEC dbo.sp_delete_job @job_name = N'sqlserver.nvim fixture no history', @delete_unused_schedule = 1;
GO

EXEC dbo.sp_add_job
  @job_name = N'sqlserver.nvim fixture history',
  @enabled = 1,
  @description = N'Isolated sqlserver.nvim integration fixture',
  @owner_login_name = N'sa';
EXEC dbo.sp_add_jobstep
  @job_name = N'sqlserver.nvim fixture history',
  @step_name = N'Record success',
  @subsystem = N'TSQL',
  @command = N'SELECT 1;',
  @database_name = N'master';
EXEC dbo.sp_add_jobschedule
  @job_name = N'sqlserver.nvim fixture history',
  @name = N'sqlserver.nvim fixture history schedule',
  @enabled = 0,
  @freq_type = 4,
  @freq_interval = 1,
  @active_start_time = 10000;
EXEC dbo.sp_add_jobserver @job_name = N'sqlserver.nvim fixture history';
GO

EXEC dbo.sp_add_job
  @job_name = N'sqlserver.nvim fixture no history',
  @enabled = 0,
  @description = N'Isolated sqlserver.nvim integration fixture',
  @owner_login_name = N'sa';
EXEC dbo.sp_add_jobstep
  @job_name = N'sqlserver.nvim fixture no history',
  @step_name = N'Never run',
  @subsystem = N'TSQL',
  @command = N'SELECT 1;',
  @database_name = N'master';
EXEC dbo.sp_add_jobschedule
  @job_name = N'sqlserver.nvim fixture no history',
  @name = N'sqlserver.nvim fixture no-history schedule',
  @enabled = 0,
  @freq_type = 4,
  @freq_interval = 1,
  @active_start_time = 10000;
EXEC dbo.sp_add_jobserver @job_name = N'sqlserver.nvim fixture no history';
GO

EXEC dbo.sp_add_alert
  @name = N'sqlserver.nvim fixture linked alert',
  @severity = 16,
  @job_name = N'sqlserver.nvim fixture history';
EXEC dbo.sp_add_alert
  @name = N'sqlserver.nvim fixture independent alert',
  @severity = 17;
GO

DECLARE @fixture_job_id uniqueidentifier = (
  SELECT job_id FROM dbo.sysjobs WHERE name = N'sqlserver.nvim fixture history'
);
EXEC dbo.sp_start_job @job_name = N'sqlserver.nvim fixture history';
DECLARE @fixture_attempts int = 0;
WHILE @fixture_attempts < 60
  AND NOT EXISTS (
    SELECT 1 FROM dbo.sysjobhistory
    WHERE job_id = @fixture_job_id AND step_id = 0
  )
BEGIN
  WAITFOR DELAY '00:00:01';
  SET @fixture_attempts = @fixture_attempts + 1;
END;
IF NOT EXISTS (
  SELECT 1 FROM dbo.sysjobhistory
  WHERE job_id = @fixture_job_id AND step_id = 0
)
  THROW 50000, 'SQL Agent fixture job did not write history', 1;
GO
