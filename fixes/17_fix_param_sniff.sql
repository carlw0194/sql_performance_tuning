/*===================================================================
  fixes/17_fix_param_sniff.sql
  Purpose : Stabilise performance of usp_GetSalesByCustomer
            by forcing OPTIMIZE FOR UNKNOWN.
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

  -- Drop & recreate with recompile/optimize hint
  IF OBJECT_ID('dbo.usp_GetSalesByCustomer') IS NOT NULL
      DROP PROC dbo.usp_GetSalesByCustomer;
  
  DECLARE @ddl nvarchar(max) = N'CREATE OR ALTER PROC dbo.usp_GetSalesByCustomer @CustomerID INT AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM Sales.SalesOrderHeader
    WHERE CustomerID = @CustomerID
    OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));
END';
   EXEC (@ddl);
  

  COMMIT;
  PRINT 'Parameter-sniffing mitigated (OPTIMIZE FOR UNKNOWN).';
END TRY
BEGIN CATCH
  ROLLBACK;
  THROW;
END CATCH;

-- For SSMS, uncomment the following:
/*
GO
*/
