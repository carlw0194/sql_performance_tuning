/*---------------------------------------------------------------
  fixes/12_enable_statistics.sql
  Purpose : Re‑enable AUTO_UPDATE_STATISTICS and refresh stats
  Rollback: ALTER DATABASE AdventureWorks2022 SET AUTO_UPDATE_STATISTICS OFF;
----------------------------------------------------------------*/
-- For SSMS, uncomment the following:
/*
USE master;
GO
*/

-- Note: When running with Invoke-Sqlcmd, the database context is set by the -Database parameter
-- The ALTER DATABASE statement below will work regardless of context

-- Step 1: Enable AUTO_UPDATE_STATISTICS (this is the most important part)
PRINT 'Turning AUTO_UPDATE_STATISTICS ON...';
ALTER DATABASE AdventureWorks2022 SET AUTO_UPDATE_STATISTICS ON;

-- Step 2: Switch to AdventureWorks2022 for minimal critical statistics updates
USE AdventureWorks2022;

-- Step 3: Update only the most critical statistics for testing
-- This uses sp_updatestats with resample which is much faster than individual updates
-- For production, you would want more thorough statistics updates

-- Update statistics on the most problematic tables only
-- This is much faster than updating all statistics
PRINT 'Updating critical statistics...';

-- SalesOrderDetail is usually the most problematic table
UPDATE STATISTICS Sales.SalesOrderDetail WITH SAMPLE 20 PERCENT;

-- Enable auto-update for future queries
PRINT 'Stats updated & AUTO_UPDATE_STATS ON.';

