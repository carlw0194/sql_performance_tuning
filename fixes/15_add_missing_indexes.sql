/*===================================================================
  fixes/15_add_missing_indexes.sql   (v2 – matches Perf_MissingIdx)
  Purpose : Add high‑impact missing indexes reported in baseline.
  Rollback: DROP INDEX … ON …  (see comments at bottom)
===================================================================*/
-- Database context set by PowerShell
-- USE AdventureWorks2022;
BEGIN TRY
  BEGIN TRAN;

  /*--------------------------------------------------------------
    1. Sales.SalesOrderDetail  (object_id 1490104349)
       Best candidate:  ProductID  (equality)
                         INCLUDE (UnitPrice)
  --------------------------------------------------------------*/
  IF NOT EXISTS (SELECT 1
                 FROM sys.indexes
                 WHERE name = 'IX_SOD_ProductID_inc_UnitPrice'
                   AND object_id = OBJECT_ID('Sales.SalesOrderDetail'))
  BEGIN
      PRINT 'Creating IX_SOD_ProductID_inc_UnitPrice...';
      CREATE NONCLUSTERED INDEX IX_SOD_ProductID_inc_UnitPrice
          ON Sales.SalesOrderDetail (ProductID)
          INCLUDE (UnitPrice);
  END
  ELSE
      PRINT 'IX_SOD_ProductID_inc_UnitPrice already exists - skipped.';

  /*--------------------------------------------------------------
    2. Sales.SalesOrderHeader (object_id 1602104748)
       Best candidate: Status (equality)
                       OrderDate (inequality)
                       INCLUDE (SalesPersonID, SubTotal)
  --------------------------------------------------------------*/
  IF NOT EXISTS (SELECT 1
                 FROM sys.indexes
                 WHERE name = 'IX_SOH_Status_OrderDate_inc_SalesPerson_SubTotal'
                   AND object_id = OBJECT_ID('Sales.SalesOrderHeader'))
  BEGIN
      PRINT 'Creating IX_SOH_Status_OrderDate_inc_SalesPerson_SubTotal...';
      CREATE NONCLUSTERED INDEX IX_SOH_Status_OrderDate_inc_SalesPerson_SubTotal
          ON Sales.SalesOrderHeader (Status, OrderDate)
          INCLUDE (SalesPersonID, SubTotal);
  END
  ELSE
      PRINT 'IX_SOH_Status_OrderDate_inc_SalesPerson_SubTotal already exists - skipped.';

  /*--------------------------------------------------------------*/
  COMMIT;
  PRINT 'Missing indexes added / verified.';
END TRY
BEGIN CATCH
  ROLLBACK;
  THROW;
END CATCH;
/*--------------------------------------------------------------
  ROLLBACK SNIPPETS (if needed)
  DROP INDEX IX_SOD_ProductID_inc_UnitPrice
      ON Sales.SalesOrderDetail;
  DROP INDEX IX_SOH_Status_OrderDate_inc_SalesPerson_SubTotal
      ON Sales.SalesOrderHeader;
--------------------------------------------------------------*/
