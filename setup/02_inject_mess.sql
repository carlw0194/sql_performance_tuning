/*======================================================================
  02_inject_mess.sql
  Purpose  : Intentionally degrade AdventureWorks2022 performance
             (missing indexes, non?SARGable predicates, fragmentation,
              parameter sniffing, over?indexing, stats disable, etc.)
  CAUTION  : Run ONLY in a non?production sandbox!
======================================================================*/

-- Database context set by PowerShell
-- For SSMS, uncomment the following:
/*
USE AdventureWorks2022;
GO
*/

-- Ensure automatic rollback on error inside explicit transaction
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRAN

-----------------------------------------------------------------------
-- Problem 1: Disable or drop helpful indexes
-----------------------------------------------------------------------
PRINT 'Disabling useful non?clustered indexes...';

-- Example: disable an index that supports order lookups
ALTER INDEX IX_SalesOrderHeader_CustomerID ON Sales.SalesOrderHeader DISABLE;
-- Disable a covering index on big detail table
ALTER INDEX IX_SalesOrderDetail_ProductID ON Sales.SalesOrderDetail DISABLE;

-----------------------------------------------------------------------
-- Problem 2: Add redundant / useless indexes (over?indexing)
-----------------------------------------------------------------------
PRINT 'Creating redundant indexes...';

drop index if EXISTS IX_SalesOrderHeader_CustomerID_Dup on SalesOrderHeader;
drop index if exists IX_Employee_Gender on Employee;

-- Duplicate index on same column but different name
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SalesOrderHeader_CustomerID_Dup' AND object_id = OBJECT_ID('Sales.SalesOrderHeader'))
BEGIN
    PRINT 'Creating duplicate index IX_SalesOrderHeader_CustomerID_Dup...';
    CREATE INDEX IX_SalesOrderHeader_CustomerID_Dup
        ON Sales.SalesOrderHeader (CustomerID);
END
ELSE
    PRINT 'Index IX_SalesOrderHeader_CustomerID_Dup already exists - skipped.';

-- Low-value index on low-cardinality column
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Employee_Gender' AND object_id = OBJECT_ID('HumanResources.Employee'))
BEGIN
    PRINT 'Creating low-value index IX_Employee_Gender...';
    CREATE INDEX IX_Employee_Gender
        ON HumanResources.Employee (Gender);
END
ELSE
    PRINT 'Index IX_Employee_Gender already exists - skipped.';

-----------------------------------------------------------------------
-- Problem 3: Turn off auto?update statistics
-----------------------------------------------------------------------
PRINT 'Disabling AUTO_UPDATE_STATISTICS (for demo)...';

-- Must run outside transaction due to ALTER DATABASE restrictions
IF @@TRANCOUNT > 0 COMMIT;  -- Commit any open transaction

ALTER DATABASE AdventureWorks2022
SET AUTO_UPDATE_STATISTICS OFF;

-- Restart transaction for remaining operations
IF @@TRANCOUNT = 0 
    BEGIN TRAN;


-----------------------------------------------------------------------
-- Problem 4: Introduce non?SARGable views & queries
-----------------------------------------------------------------------
PRINT 'Creating bad-view anti?patterns...';

-- Drop and recreate view using dynamic SQL to avoid batch separation issues
-- For SSMS compatibility, each DDL statement needs to be in its own batch

-- First drop the view if it exists
IF OBJECT_ID('dbo.vw_BadSalesDateFilter') IS NOT NULL
    DROP VIEW dbo.vw_BadSalesDateFilter;



-- Then create the view with proper batch separation
DECLARE @sql NVARCHAR(MAX) = N'CREATE VIEW dbo.vw_BadSalesDateFilter
AS
SELECT *
FROM Sales.SalesOrderHeader
WHERE CONVERT(varchar(10), OrderDate, 120) LIKE ''%2023%'';  -- forces scan';

EXEC sp_executesql @sql;


/*---------------------------------------------------------------
--  Problem 5: Create skewed data for parameter?sniffing demo
----------------------------------------------------------------*/
PRINT 'Duplicating rows to skew CustomerID distribution...';

DECLARE @RareCustomer INT;

/* Pick a customer that currently has very few orders (? 3) */
SELECT TOP (1) 
       @RareCustomer = soh.CustomerID
FROM   Sales.SalesOrderHeader AS soh
GROUP  BY soh.CustomerID
HAVING COUNT(*) <= 3
ORDER  BY COUNT(*) ASC;   -- least-used customer first

PRINT 'Using CustomerID = ' + CAST(@RareCustomer AS varchar(10));

/* Duplicate 10?000 random source rows for that customer */
INSERT INTO Sales.SalesOrderHeader
(RevisionNumber, OrderDate, DueDate, ShipDate,
 Status, OnlineOrderFlag, PurchaseOrderNumber,
 AccountNumber, CustomerID, SalesPersonID,
 TerritoryID, BillToAddressID, ShipToAddressID,
 ShipMethodID, CreditCardApprovalCode,
 SubTotal, TaxAmt, Freight,           --  ?  TotalDue omitted (computed)
 Comment, rowguid, ModifiedDate)
SELECT TOP (10000)
       RevisionNumber, OrderDate, DueDate, ShipDate,
       Status, OnlineOrderFlag, PurchaseOrderNumber,
       AccountNumber, @RareCustomer, SalesPersonID,
       TerritoryID, BillToAddressID, ShipToAddressID,
       ShipMethodID, CreditCardApprovalCode,
       SubTotal, TaxAmt, Freight,
       Comment, NEWID(), GETDATE()
FROM   Sales.SalesOrderHeader
ORDER  BY NEWID();

PRINT 'Skewed data inserted  parameter-sniffing scenario ready.';

--create stored proc for parameter sniffing demo
IF OBJECT_ID('dbo.usp_GetSalesByCustomer') IS NOT NULL
    DROP PROC dbo.usp_GetSalesByCustomer;

-----------------------------------------------------------------------
-- Problem 6: Fragment a large table
-----------------------------------------------------------------------
/* Fragment Sales.SalesOrderDetail � RI?safe version */
PRINT '???  Fragmenting Sales.SalesOrderDetail (RI?safe)...';

INSERT TOP (50000) INTO Sales.SalesOrderDetail
        (SalesOrderID,
         CarrierTrackingNumber,
         OrderQty,
         ProductID,
         SpecialOfferID,
         UnitPrice,
         UnitPriceDiscount,
         rowguid,
         ModifiedDate)
SELECT
       soh.SalesOrderID,                 -- shipped orders
       NULL,
       1,
       sop.ProductID,
       sop.SpecialOfferID,               -- ? matches FK table
       p.ListPrice,
       0,
       NEWID(),
       GETDATE()
FROM   Sales.SalesOrderHeader   AS soh
JOIN   Sales.SpecialOfferProduct AS sop  /* guarantees FK match */
           ON 1 = 1                      -- cross?join effect
JOIN   Production.Product       AS p
           ON p.ProductID = sop.ProductID
WHERE  soh.Status = 5                    -- shipped
ORDER  BY NEWID();                       -- random sampling

-- Delete random 20k rows to cause fragmentation
DELETE TOP (20000)
FROM Sales.SalesOrderDetail
WHERE UnitPrice < 100;


-----------------------------------------------------------------------
-- Problem 7: Confirm �mess� metrics (optional quick checks)
-----------------------------------------------------------------------
PRINT 'Quick sanity checks of bad state...';

-- Count disabled indexes
SELECT COUNT(*) AS DisabledIndexes
FROM sys.indexes
WHERE is_disabled = 1
  AND object_id IN (OBJECT_ID('Sales.SalesOrderHeader'),
                    OBJECT_ID('Sales.SalesOrderDetail'));

-- Show AUTO_UPDATE_STATISTICS setting
SELECT name, is_auto_update_stats_on
FROM sys.databases
WHERE name = DB_NAME();

-- Show fragmentation level on target index
SELECT  OBJECT_NAME(i.object_id) AS [Table],
        i.name                  AS [Index],
        ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON  ips.object_id = i.object_id
                   AND ips.index_id  = i.index_id
WHERE i.object_id = OBJECT_ID('Sales.SalesOrderDetail')
ORDER BY ips.avg_fragmentation_in_percent DESC;

PRINT 'Database chaos injected. Ready for diagnostics.';

    COMMIT; -- success
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    DECLARE @ErrMsg nvarchar(4000) = ERROR_MESSAGE();
    DECLARE @ErrLine int = ERROR_LINE();
    RAISERROR('InjectMess failed at line %d: %s', 16, 1, @ErrLine, @ErrMsg);
END CATCH

