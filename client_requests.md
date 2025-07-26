
# Client Requests

My MS SQL Server is currently slow, taking over 20 seconds to fetch 5000 records. I'm looking for an expert to optimize query execution speed. Key issues: SELECT queries with subqueries, sorting, and ordering are especially slow. Although indexes are already in place, performance is still lacking. <https://www.fi.freelancer.com/projects/sql/optimize-sql-server-performance>

“We are seeking an experienced professional to enhance the performance of our SQL Server database. The role involves analyzing slow queries, updating indexes, and providing structural improvement recommendations. The ideal candidate should have extensive experience in SQL Server performance tuning, query optimization, and index management.”
<https://www.upwork.com/freelance-jobs/apply/SQL-Server-Database-Performance-Optimization-Expert-Needed_~021945008727084809970>

## Assumptions about client environment

| Category                 | Assumption                                                                                 | Why it’s Reasonable                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| **Database**             | Microsoft SQL Server 2016 or later (on-premises)                                           | Still widely used; Query Store and DMVs are available from 2016 onward  |
| **OS**                   | Windows Server 2016/2019                                                                   | Most SQL Server deployments outside Azure use this                      |
| **Management Tool**      | SQL Server Management Studio (SSMS)                                                        | Still the dominant GUI for DBAs                                         |
| **Workload Type**        | OLTP system (transactional workload)                                                       | Performance tuning pain points often stem from OLTP workloads           |
| **Access**               | Local access to SSMS and permissions to run `DBCC`, view `sys.dm_*` views, and Query Store | Necessary for meaningful diagnostics                                    |
| **Indexing Situation**   | Indexes exist but may not be optimal                                                       | Most clients think they have indexes but don’t measure efficiency       |
| **Monitoring Tools**     | No 3rd-party monitoring tool; basic usage of Activity Monitor or none at all               | Many small to medium companies don’t invest in paid monitoring tools    |
| **Automation Readiness** | SQL Agent is enabled for scheduled jobs                                                    | Lets you build in proactive maintenance scripts                         |
| **Backup/Restore**       | Full backups are happening nightly (even if suboptimally)                                  | You won’t need to simulate the whole backup chain but can comment on it |
