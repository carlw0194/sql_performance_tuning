--get top CPU queries (Query Store)
USE AdventureWorks2022;
GO

/* Ensure Query Store is collecting runtime stats */
ALTER DATABASE AdventureWorks2022
SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);
GO

/*--------------------------------------------------------------------
Return the 10 queries with the highest average CPU time (ms)
JOIN path:  query  -> plan -> runtime stats          
--------------------------------------------------------------------*/
SELECT TOP (10)
       q.query_id,
       rs.avg_cpu_time / 1000.0             AS avg_cpu_ms,   -- micro-seconds → ms
       qt.query_sql_text
FROM   sys.query_store_query        AS q
JOIN   sys.query_store_query_text   AS qt ON qt.query_text_id = q.query_text_id
JOIN   sys.query_store_plan         AS p  ON p.query_id      = q.query_id
JOIN   sys.query_store_runtime_stats AS rs ON rs.plan_id     = p.plan_id
ORDER  BY rs.avg_cpu_time DESC;
