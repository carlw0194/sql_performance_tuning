/*===================================================================
  fixes/16_rebuild_fragmented.sql
  Purpose : Defragment highly fragmented indexes after chaos.
===================================================================*/
-- Database context set by PowerShell
-- USE AdventureWorks2022;
-- For SSMS, uncomment the following:
/*
USE AdventureWorks2022;
GO
*/
BEGIN TRY
  BEGIN TRAN;

  PRINT 'Rebuilding fragmented indexes (>30% fragmentation)...';
  DECLARE @sql nvarchar(max)='';

  ;WITH frag AS (
    SELECT
        s.[object_id], s.index_id,
        avg_fragmentation_in_percent
    FROM sys.dm_db_index_physical_stats
         (DB_ID(), NULL, NULL, NULL, 'LIMITED') AS s
    WHERE avg_fragmentation_in_percent > 30
      AND page_count > 1000
      AND index_id <> 0          -- ignore heaps here
  )
  SELECT @sql = STRING_AGG(
      'ALTER INDEX '
      + QUOTENAME(i.name)
      + ' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(f.object_id))
      + '.' + QUOTENAME(OBJECT_NAME(f.object_id))
      + ' REBUILD WITH (ONLINE = ON);', CHAR(13)+CHAR(10))
  FROM frag f
  JOIN sys.indexes i
    ON i.object_id = f.object_id
   AND i.index_id  = f.index_id;

  EXEC (@sql);
  COMMIT;
  PRINT 'Fragmentation repaired.';
END TRY
BEGIN CATCH
  ROLLBACK;
  THROW;
END CATCH;

-- For SSMS, uncomment the following:
/*
GO
*/
