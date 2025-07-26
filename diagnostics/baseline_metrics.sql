/*======================================================================
  diagnostics/baseline_metrics.sql
  Purpose : Snapshot key performance metrics for before/after comparison
            Run 1) immediately after chaos injection
            Run 2) after all tuning for “after” snapshot
  Author  : Carlton Njong
======================================================================*/
USE AdventureWorks2022;   -- ensure we log to the right DB
SET NOCOUNT ON;

DECLARE @SnapshotLabel sysname = N'Baseline';   -- change to 'After' for second run

/*====================================================================
   Ensure target tables exist (drop & recreate to avoid legacy schema)
  ====================================================================*/
IF OBJECT_ID('dbo.Perf_TopCPU') IS NOT NULL DROP TABLE dbo.Perf_TopCPU;
CREATE TABLE dbo.Perf_TopCPU
(
    SnapshotLabel    sysname NULL,
    total_cpu_ms     bigint NULL,
    execution_count  bigint NULL,
    avg_cpu_ms       bigint NULL,
    max_cpu_ms       bigint NULL,
    dbname           sysname NULL,
    object_name      sysname NULL,
    query_snippet    nvarchar(200) NULL,
    CapturedAt       datetime NULL
);

IF OBJECT_ID('dbo.Perf_TopIO') IS NOT NULL DROP TABLE dbo.Perf_TopIO;
CREATE TABLE dbo.Perf_TopIO
(
    SnapshotLabel       sysname NULL,
    total_logical_reads bigint NULL,
    execution_count     bigint NULL,
    avg_logical_reads   bigint NULL,
    dbname              sysname NULL,
    object_name         sysname NULL,
    query_snippet       nvarchar(200) NULL,
    CapturedAt          datetime NULL
);

IF OBJECT_ID('dbo.Perf_Waits') IS NOT NULL DROP TABLE dbo.Perf_Waits;
CREATE TABLE dbo.Perf_Waits
(
    wait_type             nvarchar(120) NULL,
    waiting_tasks_count    bigint NULL,
    wait_time_ms           bigint NULL,
    SnapshotLabel          sysname NULL,
    CapturedAt             datetime NULL
);

IF OBJECT_ID('dbo.Perf_MissingIdx') IS NOT NULL DROP TABLE dbo.Perf_MissingIdx;
CREATE TABLE dbo.Perf_MissingIdx
(
    database_id            int NULL,
    object_id              int NULL,
    equality_columns       nvarchar(max) NULL,
    inequality_columns     nvarchar(max) NULL,
    included_columns       nvarchar(max) NULL,
    avg_total_user_cost    float NULL,
    avg_user_impact        float NULL,
    SnapshotLabel          sysname NULL,
    CapturedAt             datetime NULL
);

/*====================================================================
   Capture metrics inside single transaction for consistency
  ====================================================================*/
BEGIN TRY
    BEGIN TRAN;

    /* 1️⃣ Top CPU */
    DELETE dbo.Perf_TopCPU WHERE SnapshotLabel = @SnapshotLabel;

    INSERT INTO dbo.Perf_TopCPU
        (SnapshotLabel,total_cpu_ms,execution_count,avg_cpu_ms,max_cpu_ms,
         dbname,object_name,query_snippet,CapturedAt)
    SELECT TOP (10)
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

    /* 2️⃣ Top I/O */
    DELETE dbo.Perf_TopIO WHERE SnapshotLabel = @SnapshotLabel;

    INSERT INTO dbo.Perf_TopIO
        (SnapshotLabel,total_logical_reads,execution_count,avg_logical_reads,
         dbname,object_name,query_snippet,CapturedAt)
    SELECT TOP (10)
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

    /* 3️⃣ Wait statistics */
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
                              'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE',
                              'FT_IFTS_SCHEDULER_IDLE_WAIT');

    /* 4️⃣ Missing index suggestions */
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

    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    DECLARE @Err nvarchar(4000)=ERROR_MESSAGE();
    RAISERROR('baseline_metrics failed: %s',16,1,@Err);
END CATCH

PRINT N'✅  ' + @SnapshotLabel + N' metrics captured to dbo.Perf_* tables.';
