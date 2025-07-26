# SQL Server Performance Tuning & Optimization

*Simulating real‑world client pain points sourced from Upwork, Freelancer, and LinkedIn posts using AdventureWorks database2022 OLTP edition.*

> **Goal:** Reproduce common OLTP performance bottlenecks in the AdventureWorks2022 OLTP sample database, diagnose root causes, implement best‑practice fixes, and document measurable gains.

---

## 📦 Client Environment Assumptions

| Area | Assumption |
|------|------------|
| **SQL Server Version** | 2017 or 2019 (on‑prem) |
| **Operating System** | Windows Server 2019 |
| **Workload Type** | High‑volume OLTP (e‑commerce style) |
| **Access** | sysadmin role; SSMS 19 installed |
| **Monitoring** | No 3rd‑party tool—only built‑in DMVs, Query Store, and SQL Agent |
| **Backups** | Nightly FULL + LOG backups; SQL Agent enabled |



---

## 🔧 Problem Statement

Freelance clients consistently report:

1. **Slow transactional queries** (e.g., order look‑ups > 5 s).  
2. **High I/O waits** and blocking during peak hours.  
3. **“We added indexes but performance is still bad.”**  
4. **Statistics out of date** → poor cardinality estimates.  
5. Lack of proactive **maintenance or monitoring**.

This repo recreates each pain point, then walks through the remediation process and proves the improvement.

---

## 🛠 Solution Overview

| Phase | Deliverables | Key Scripts |
|-------|--------------|-------------|
| **1. Baseline & Diagnostics** | Waits, top expensive queries, fragmentation report | `diagnostics/00_baseline_metrics.sql` |
| **2. Query Analysis** | Execution‑plan screenshots, SARGability checklist | `diagnostics/01_missing_indexes.sql` |
| **3. Index Tuning** | New / dropped indexes, covering & filtered indexes | `fixes/10_add_helpful_indexes.sql` |
| **4. Statistics Updates** | Auto‑update review, manual stats refresh | `fixes/12_update_statistics.sql` |
| **5. Query Plan Review** | Before/after `.sqlplan` gallery | `screenshots/plans/` |
| **6. Automation (Optional)** | Ola Hallengren jobs, slow‑query capture, email alerts | `automation/` |

### Tooling Used

- **SSMS 19** (plan viewer, Query Store GUI)  
- DMVs: `sys.dm_exec_query_stats`, `sys.dm_db_index_usage_stats`, `sys.dm_os_wait_stats`  
- **Query Store** for regression tracking  
- **Ola Hallengren** maintenance scripts  
- **PowerShell** & SQL Agent for scheduled jobs  
- Excel / Power BI for before‑vs‑after charts

---

## ♻️ Reusing This Project

1. **Restore your database** (replace `backup/AdventureWorks2022.bak`).  
2. Run `setup/02_inject_mess.sql` to simulate bottlenecks, or comment out sections you don’t need.  
3. Execute `diagnostics/00_baseline_metrics.sql` to capture initial metrics.  
4. Apply fixes under `/fixes` in numerical order.  
5. Re‑run diagnostics to produce the “after” snapshot.  
6. Update `/reports` with new CSV/XLSX outputs; replace screenshots in `/screenshots`.

> **Tip:** All scripts reference the database name via a variable at the top—change `SET @DB = 'YourDB'` once and you’re good to go.

---

## 📊 Before vs After

| Metric | Baseline | Tuned | Δ % |
|--------|---------:|------:|----:|
| Avg CPU (ms) | 1 240 | **310** | ‑75 % |
| Logical Reads | 5.8 M | **1.2 M** | ‑79 % |
| P99 Latency | 6.2 s | **0.9 s** | ‑85 % |

*Visuals live in `/reports` (Excel) and `/screenshots/dashboards`.*

---

## 📝 Conclusions & Client Recommendations

- **Index coverage + fresh stats** solved 80 % of latency issues.  
- Implement the **automation suite** to keep performance steady (index maintenance, stats drift checker, nightly slow‑query capture).  
- For long‑term scalability, consider **partitioning** the `Sales.SalesOrderDetail` table by `OrderDate` and evaluating **In‑Memory OLTP** for hot lookup tables.

> **Takeaway:** Routine housekeeping plus targeted tuning yields outsized gains—no hardware upgrade needed.

---

### ✨ Credits

Based on real freelance briefs collected from Upwork, Freelancer.com, and LinkedIn (2025). Built and documented by **Carlton Njong**.
