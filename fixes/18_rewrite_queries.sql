/*===================================================================
  fixes/18_rewrite_queries.sql
  Purpose : Replace CONVERT/L LIKE pattern with SARGable predicate.
===================================================================*/
-- Database context set by PowerShell
-- USE AdventureWorks2022;
-- For SSMS, uncomment the following:

BEGIN TRY
  BEGIN TRAN;

  IF OBJECT_ID('dbo.vw_BadSalesDateFilter') IS NOT NULL
      DROP VIEW dbo.vw_BadSalesDateFilter;
  
  DECLARE @vsql nvarchar(max) = N'CREATE OR ALTER VIEW dbo.vw_BadSalesDateFilter AS
SELECT *
FROM Sales.SalesOrderHeader
WHERE OrderDate BETWEEN ''2023-01-01'' AND ''2023-12-31'';';
  EXEC (@vsql);
  

  COMMIT;
  PRINT 'vw_BadSalesDateFilter rewritten to SARGable predicate.';
END TRY
BEGIN CATCH
  ROLLBACK;
  THROW;
END CATCH;

-- For SSMS, uncomment the following:
