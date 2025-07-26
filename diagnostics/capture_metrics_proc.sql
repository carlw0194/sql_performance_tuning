/*======================================================================
  diagnostics/capture_metrics_proc.sql
  Purpose : ONE-STOP script – creates logging tables (Perf_*) and a
            stored procedure dbo.Capture_PerfMetrics that captures a
            comprehensive performance snapshot.
  Author  : Carlton Njong
  Usage   : 1. Run this script once to deploy tables + proc.
            2. EXEC dbo.Capture_PerfMetrics @SnapshotLabel = 'Baseline';
               EXEC dbo.Capture_PerfMetrics @SnapshotLabel = 'After';
======================================================================*/

USE AdventureWorks2022;  -- change if you prefer another DB for logging
GO

/*--------------------------------------------------------------------
  1. Create/refresh logging tables (runs safely even if they exist)
--------------------------------------------------------------------*/

--check if tables exist already
IF OBJECT_ID('dbo.Perf_TopCPU') IS NULL
    CREATE TABLE dbo.Perf_TopCPU
    (
        SnapshotLabel    sysname,
        total_cpu_ms     bigint,
        execution_count  bigint,
        avg_cpu_ms       bigint,
        max_cpu_ms       bigint,
        dbname           sysname NULL,
        object_name      sysname NULL,
        query_snippet    nvarchar(200),
        CapturedAt       datetime
    );
GO

IF OBJECT_ID('dbo.Perf_TopIO') IS NULL
    CREATE TABLE dbo.Perf_TopIO
    (
        SnapshotLabel       sysname,
        total_logical_reads bigint,
        execution_count     bigint,
        avg_logical_reads   bigint,
        dbname              sysname NULL,
        object_name         sysname NULL,
        query_snippet       nvarchar(200),
        CapturedAt          datetime
    );
GO

IF OBJECT_ID('dbo.Perf_Waits') IS NULL
    CREATE TABLE dbo.Perf_Waits
    (
        wait_type             nvarchar(120),
        waiting_tasks_count    bigint,
        wait_time_ms           bigint,
        SnapshotLabel          sysname,
        CapturedAt             datetime
    );
GO

IF OBJECT_ID('dbo.Perf_MissingIdx') IS NULL
    CREATE TABLE dbo.Perf_MissingIdx
    (
        database_id         int,
        object_id           int,
        equality_columns    nvarchar(max),
        inequality_columns  nvarchar(max),
        included_columns    nvarchar(max),
        avg_total_user_cost float,
        avg_user_impact     float,
        SnapshotLabel       sysname,
        CapturedAt          datetime
    );
GO


IF OBJECT_ID('dbo.Perf_Tempdb') IS NULL
    CREATE TABLE dbo.Perf_Tempdb
    (
        SnapshotLabel   sysname,
        unallocated_mb  bigint,
        user_objs_mb    bigint,
        internal_mb     bigint,
        version_store_mb bigint,
        CapturedAt      datetime
    );
GO

IF OBJECT_ID('dbo.Perf_FileIO') IS NULL
    CREATE TABLE dbo.Perf_FileIO
    (
        SnapshotLabel     sysname,
        database_name     sysname,
        filelogicalname   sysname,
        num_of_reads      bigint,
        num_of_writes     bigint,
        io_stall_ms       bigint,
        size_mb           bigint,
        CapturedAt        datetime
    );
GO

IF OBJECT_ID('dbo.Perf_MemGrant') IS NULL
    CREATE TABLE dbo.Perf_MemGrant
    (
        SnapshotLabel      sysname,
        waiting_grants_kb  bigint,
        granted_grants_kb  bigint,
        active_grants_kb   bigint,
        CapturedAt         datetime
    );
GO

IF OBJECT_ID('dbo.Perf_PlanCache') IS NULL
    CREATE TABLE dbo.Perf_PlanCache
    (
        SnapshotLabel     sysname,
        cachestore        nvarchar(60),
        total_mb          bigint,
        CapturedAt        datetime
    );
GO

/*--------------------------------------------------------------------
  2. Create / replace the stored procedure that captures the snapshot
--------------------------------------------------------------------*/
IF OBJECT_ID('dbo.Capture_PerfMetrics') IS NOT NULL
    DROP PROCEDURE dbo.Capture_PerfMetrics;
GO

CREATE PROCEDURE dbo.Capture_PerfMetrics
    @SnapshotLabel sysname = N'Baseline'  -- e.g. 'Baseline' or 'After'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- auto-rollback on errors inside TRY

    -- Defensive: treat NULL param as 'Baseline'
    SET @SnapshotLabel = ISNULL(@SnapshotLabel, N'Baseline');

    BEGIN TRY
        BEGIN TRAN;

        /*----------------------------------------------------------
          2.1  CPU – top 10 statements by total worker time
        ----------------------------------------------------------*/
        DELETE dbo.Perf_TopCPU WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_TopCPU
            (SnapshotLabel,total_cpu_ms,execution_count,avg_cpu_ms,max_cpu_ms,
             dbname,object_name,query_snippet,CapturedAt)
        SELECT  TOP (10)
                @SnapshotLabel,
                qs.total_worker_time/1000,
                qs.execution_count,
                qs.total_worker_time/qs.execution_count/1000,
                qs.max_worker_time/1000,
                DB_NAME(qt.dbid),
                OBJECT_NAME(qt.objectid,qt.dbid),
                SUBSTRING(qt.text,1,200),
                GETDATE()
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
        ORDER BY qs.total_worker_time DESC;

        /*----------------------------------------------------------
          2.2  Logical IO – top 10 statements
        ----------------------------------------------------------*/
        DELETE dbo.Perf_TopIO WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_TopIO
            (SnapshotLabel,total_logical_reads,execution_count,avg_logical_reads,
             dbname,object_name,query_snippet,CapturedAt)
        SELECT  TOP (10)
                @SnapshotLabel,
                qs.total_logical_reads,
                qs.execution_count,
                qs.total_logical_reads/qs.execution_count,
                DB_NAME(qt.dbid),
                OBJECT_NAME(qt.objectid,qt.dbid),
                SUBSTRING(qt.text,1,200),
                GETDATE()
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
        ORDER BY qs.total_logical_reads DESC;

        /*----------------------------------------------------------
          2.3  Wait statistics snapshot (system-wide)
        ----------------------------------------------------------*/
        DELETE dbo.Perf_Waits WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_Waits
            (wait_type,waiting_tasks_count,wait_time_ms,SnapshotLabel,CapturedAt)
        SELECT  wait_type, waiting_tasks_count, wait_time_ms,
                @SnapshotLabel, GETDATE()
        FROM    sys.dm_os_wait_stats
        WHERE   wait_type NOT IN ('CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK',
                                  'SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE',
                                  'CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
                                  'BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_MANUAL_EVENT',
                                  'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT');

        /*----------------------------------------------------------
          2.4  Missing index suggestions for current DB
        ----------------------------------------------------------*/
        DELETE dbo.Perf_MissingIdx WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_MissingIdx
            (database_id,object_id,equality_columns,inequality_columns,included_columns,
             avg_total_user_cost,avg_user_impact,SnapshotLabel,CapturedAt)
        SELECT  d.database_id,d.object_id,d.equality_columns,d.inequality_columns,
                d.included_columns,s.avg_total_user_cost,s.avg_user_impact,
                @SnapshotLabel,GETDATE()
        FROM    sys.dm_db_missing_index_details d
        JOIN    sys.dm_db_missing_index_groups g   ON d.index_handle = g.index_handle
        JOIN    sys.dm_db_missing_index_group_stats s ON g.index_group_handle = s.group_handle
        WHERE   d.database_id = DB_ID();

        /*----------------------------------------------------------
          2.5  TempDB usage (file-space)
        ----------------------------------------------------------*/
        DELETE dbo.Perf_Tempdb WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_Tempdb
            (SnapshotLabel,unallocated_mb,user_objs_mb,internal_mb,version_store_mb,CapturedAt)
        SELECT  @SnapshotLabel,
                SUM(unallocated_extent_page_count)*8/1024,
                SUM(user_object_reserved_page_count)*8/1024,
                SUM(internal_object_reserved_page_count)*8/1024,
                SUM(version_store_reserved_page_count)*8/1024,
                GETDATE()
        FROM    sys.dm_db_file_space_usage;  -- one row per tempdb file

        /*----------------------------------------------------------
          2.6  File-level IO stats (all databases)
        ----------------------------------------------------------*/
        DELETE dbo.Perf_FileIO WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_FileIO
            (SnapshotLabel,database_name,filelogicalname,num_of_reads,num_of_writes,io_stall_ms,size_mb,CapturedAt)
        SELECT  @SnapshotLabel,
                DB_NAME(mf.database_id),
                mf.name,
                vfs.num_of_reads,
                vfs.num_of_writes,
                vfs.io_stall,
                mf.size*8/1024,
                GETDATE()
        FROM    sys.dm_io_virtual_file_stats(NULL,NULL) vfs
        JOIN    sys.master_files mf ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id;

        /*----------------------------------------------------------
          2.7  Memory grants – instantaneous snapshot
        ----------------------------------------------------------*/
        DELETE dbo.Perf_MemGrant WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_MemGrant
            (SnapshotLabel,waiting_grants_kb,granted_grants_kb,active_grants_kb,CapturedAt)
        SELECT  @SnapshotLabel,
                SUM(requested_memory_kb)                      AS waiting_grants_kb,
                SUM(granted_memory_kb)                        AS granted_grants_kb,
                SUM(used_memory_kb)                           AS active_grants_kb,
                GETDATE()
        FROM    sys.dm_exec_query_memory_grants;

        /*----------------------------------------------------------
          2.8  Plan cache size (proc vs ad-hoc)
        ----------------------------------------------------------*/
        DELETE dbo.Perf_PlanCache WHERE SnapshotLabel = @SnapshotLabel;

        INSERT INTO dbo.Perf_PlanCache
            (SnapshotLabel,cachestore,total_mb,CapturedAt)
        SELECT  @SnapshotLabel,
                name,
                pages_kb/1024,
                GETDATE()
        FROM    sys.dm_os_memory_cache_counters
        WHERE   name IN ('CACHESTORE_OBJCP','CACHESTORE_SQLCP');

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Err nvarchar(4000) = ERROR_MESSAGE();
        RAISERROR('Capture_PerfMetrics failed: %s',16,1,@Err);
    END CATCH
END
GO

PRINT '?  Capture_PerfMetrics deployed.   EXEC dbo.Capture_PerfMetrics  -- to capture a snapshot.'
