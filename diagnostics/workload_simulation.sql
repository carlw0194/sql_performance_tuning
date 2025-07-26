/*======================================================================
  diagnostics/workload_simulation.sql
  Purpose : Simulate a mixed workload to generate performance metrics
  Author  : Carlton Njong
  Usage   : 1. Run this script to simulate a mixed workload.
======================================================================*/

USE AdventureWorks2022;
GO

SET XACT_ABORT OFF;

DECLARE @i int = 0,
        @LoopMax int = 30;  -- reduced to 30 for faster testing

WHILE @i < @LoopMax
BEGIN
    BEGIN TRY
        -- 1. Parameter‑sniffing
        EXEC dbo.usp_GetSalesByCustomer 11000;
        EXEC dbo.usp_GetSalesByCustomer 29825;

        -- 2. Non‑SARGable view
        SELECT COUNT(*) FROM dbo.vw_BadSalesDateFilter;

        -- 3. Table scans on disabled indexes
        SELECT SalesOrderID FROM Sales.SalesOrderHeader WHERE CustomerID = 11643;
        SELECT SalesOrderDetailID FROM Sales.SalesOrderDetail WHERE ProductID = 772;

        -- 4. Join & aggregate with ORDER BY
        SELECT TOP (50) soh.OrderDate,
               SUM(sod.LineTotal) AS OrderValue
        FROM   Sales.SalesOrderHeader soh
        JOIN   Sales.SalesOrderDetail sod ON soh.SalesOrderID = sod.SalesOrderID
        WHERE  soh.OrderDate >= DATEADD(day,-90,GETDATE())
        GROUP  BY soh.OrderDate
        ORDER  BY OrderValue DESC;

        -- 5. Write workload (safe update)
        UPDATE TOP (1) HumanResources.Employee
        SET    SalariedFlag = CASE WHEN SalariedFlag = 1 THEN 0 ELSE 1 END
        WHERE  BusinessEntityID IN (
                SELECT TOP (100) BusinessEntityID
                FROM   HumanResources.Employee
                ORDER  BY NEWID()
              );

        -- 6. TempDB spill
        SELECT DISTINCT TOP (1000) AddressID
        FROM   Person.Address
        ORDER  BY AddressID DESC;

        -- light pause lets the buffer pool clear and simulates think-time
        WAITFOR DELAY '00:00:00.05';  -- 50 ms

        SET @i += 1;
    END TRY
    BEGIN CATCH
        PRINT CONCAT(N'Iteration ',@i,N' failed: ',ERROR_MESSAGE());
        -- continue to next iteration
        SET @i += 1;
    END CATCH;
END
GO

PRINT N'Workload complete.';
