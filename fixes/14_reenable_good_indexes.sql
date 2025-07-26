/*---------------------------------------------------------------
  fixes/14_reenable_good_indexes.sql
  Purpose : Rebuild the two useful NC indexes disabled by chaos
  Rollback: ALTER INDEX IX_SalesOrderHeader_CustomerID DISABLE;
            ALTER INDEX IX_SalesOrderDetail_ProductID DISABLE;
----------------------------------------------------------------*/
-- Database context set by PowerShell
-- USE AdventureWorks2022;
BEGIN TRY
    BEGIN TRAN;

    PRINT 'Rebuilding IX_SalesOrderHeader_CustomerID...';
    ALTER INDEX IX_SalesOrderHeader_CustomerID
        ON Sales.SalesOrderHeader
        REBUILD WITH (ONLINE = ON);

    PRINT 'Rebuilding IX_SalesOrderDetail_ProductID...';
    ALTER INDEX IX_SalesOrderDetail_ProductID
        ON Sales.SalesOrderDetail
        REBUILD WITH (ONLINE = ON);

    COMMIT;
    PRINT 'Helpful indexes rebuilt.';
END TRY
BEGIN CATCH
    ROLLBACK;
    THROW;
END CATCH;
