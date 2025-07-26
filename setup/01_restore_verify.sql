/*======================================================================
  01_restore_verify.sql
  Purpose  : Restore AdventureWorks2022 and confirm database health
  Author   : Carlton Njong
  Notes    : • Adjust @BackupFile, @DataFile, @LogFile paths as needed
             • Requires sysadmin on the SQL instance
======================================================================*/

USE master; 
GO

-----------------------------------------------------------------------
-- Declare paths & DB name
-----------------------------------------------------------------------
DECLARE @DB          sysname      = N'AdventureWorks2022';
DECLARE @BackupFile  nvarchar(4000)= N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER01\MSSQL\Backup\AdventureWorks2022.bak';  -- ⬅️ change
DECLARE @DataFile    nvarchar(4000)= N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER01\MSSQL\DATA\AdventureWorks2022.mdf';-- ⬅️ change
DECLARE @LogFile     nvarchar(4000)= N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER01\MSSQL\Log\AdventureWorks2022.ldf'; -- ⬅️ change

-----------------------------------------------------------------------
-- If DB exists, drop or set to SINGLE_USER and drop
-----------------------------------------------------------------------
IF DB_ID(@DB) IS NOT NULL
BEGIN
    ALTER DATABASE [AdventureWorks2022] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [AdventureWorks2022];
END
print '✅ Existing copy removed (if any).';

-----------------------------------------------------------------------
-- Begin transaction wrapper
-----------------------------------------------------------------------
BEGIN TRY

-----------------------------------------------------------------------
-- Capture logical file names from the backup
-----------------------------------------------------------------------
IF OBJECT_ID('tempdb..#FileList') IS NOT NULL
    DROP TABLE #FileList;

-- Create staging table matching RESTORE FILELISTONLY output
-- (we only need the first 3 columns later, but all columns must be
--  present so the INSERT … EXEC column counts align)
CREATE TABLE #FileList
(
    LogicalName           sysname            ,
    PhysicalName          nvarchar(4000)     ,
    Type                  char(1)            ,
    FileGroupName         sysname NULL       ,
    Size                  bigint  NULL       ,
    MaxSize               bigint  NULL       ,
    FileID                bigint  NULL       ,
    CreateLSN             numeric(25,0) NULL ,
    DropLSN               numeric(25,0) NULL ,
    UniqueID              uniqueidentifier NULL,
    ReadOnlyLSN           numeric(25,0) NULL ,
    ReadWriteLSN          numeric(25,0) NULL ,
    BackupSizeInBytes     bigint NULL        ,
    SourceBlockSize       int    NULL        ,
    FileGroupID           int    NULL        ,
    LogGroupGUID          uniqueidentifier NULL,
    DifferentialBaseLSN   numeric(25,0) NULL ,
    DifferentialBaseGUID  uniqueidentifier NULL,
    IsReadOnly            bit    NULL        ,
    IsPresent             bit    NULL        ,
    TDEThumbprint         varbinary(32) NULL ,
    SnapshotURL           nvarchar(360) NULL
);


/*
   Use INSERT … EXEC to capture the result-set that RESTORE FILELISTONLY
   returns. We keep the BACKUP path parameterised to avoid dynamic-SQL
   injection and to preserve readability.
*/
DECLARE @sql nvarchar(max) = N'RESTORE FILELISTONLY FROM DISK = @b';

INSERT INTO #FileList
EXEC sp_executesql
     @sql,
     N'@b nvarchar(4000)',
     @b = @BackupFile;

-- Extract logical names for the MOVE clause later
DECLARE @LogicalDataName sysname,
        @LogicalLogName  sysname;

SELECT @LogicalDataName = LogicalName
FROM   #FileList
WHERE  Type = 'D';   -- Data file

SELECT @LogicalLogName  = LogicalName
FROM   #FileList
WHERE  Type = 'L';   -- Log file

PRINT 'Logical Data File: ' + @LogicalDataName;
PRINT 'Logical Log  File: ' + @LogicalLogName;
-----------------------------------------------------------------------
-- Restore database with MOVE
-----------------------------------------------------------------------
RESTORE DATABASE [AdventureWorks2022]
FROM DISK = @BackupFile
WITH
    MOVE @LogicalDataName TO @DataFile,  -- logical data name ⬅️
    MOVE @LogicalLogName  TO @LogFile,   -- logical log name  ⬅️
    RECOVERY,
    REPLACE,             
    STATS = 10;          -- progress messages

PRINT 'Restore completed.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
    DECLARE @ErrLine int = ERROR_LINE();
    RAISERROR('RestoreVerify failed at line %d: %s', 16, 1, @ErrLine, @ErrMsg);
END CATCH
GO

-----------------------------------------------------------------------
-- Post-restore validation (separate batch)
-----------------------------------------------------------------------
/* Confirm state = ONLINE */
SELECT name, state_desc, recovery_model_desc
FROM sys.databases
WHERE name = 'AdventureWorks2022';

/* Quick integrity check (no detail messages) */
DBCC CHECKDB('AdventureWorks2022') WITH NO_INFOMSGS;
PRINT 'CHECKDB passed.';

/* Smoke-test: query a large table */
USE AdventureWorks2022;

SELECT TOP (5) SalesOrderID, OrderDate, SubTotal
FROM Sales.SalesOrderHeader
ORDER BY OrderDate DESC;

PRINT 'Restore & validation script finished.';
GO
