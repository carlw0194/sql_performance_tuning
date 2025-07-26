/*===================================================================
  fixes/11_drop_bad_indexes.sql
  Purpose : Remove duplicate or low-selectivity indexes that add
            write overhead but little read benefit.
  Rollback: Recreate indexes (scripts at bottom, commented)
===================================================================*/
-- Database context set by PowerShell
-- For SSMS, uncomment the following:
/*
USE AdventureWorks2022;
GO
*/
BEGIN TRY
  BEGIN TRAN;

  -- 1. Duplicate index on SalesOrderHeader(CustomerID)
  IF EXISTS (SELECT 1
             FROM sys.indexes
             WHERE name = 'IX_SalesOrderHeader_CustomerID_Dup'
               AND object_id = OBJECT_ID('Sales.SalesOrderHeader'))
  BEGIN
      PRINT 'Dropping duplicate index IX_SalesOrderHeader_CustomerID_Dup...';
      DROP INDEX IX_SalesOrderHeader_CustomerID_Dup
        ON Sales.SalesOrderHeader;
  END

  -- 2. Low-selectivity Gender index
  IF EXISTS (SELECT 1
             FROM sys.indexes
             WHERE name = 'IX_Employee_Gender'
               AND object_id = OBJECT_ID('HumanResources.Employee'))
  BEGIN
      PRINT 'Dropping low-value index IX_Employee_Gender...';
      DROP INDEX IX_Employee_Gender
        ON HumanResources.Employee;
  END

  COMMIT;
  PRINT 'Redundant / low-value indexes removed.';
END TRY
BEGIN CATCH
  ROLLBACK;
  THROW;
END CATCH;
GO
-- Rollback recreation scripts (commented)
/*
CREATE INDEX IX_SalesOrderHeader_CustomerID_Dup
  ON Sales.SalesOrderHeader(CustomerID);
CREATE INDEX IX_Employee_Gender
  ON HumanResources.Employee(Gender);
*/
