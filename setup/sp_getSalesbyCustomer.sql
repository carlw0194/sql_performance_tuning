-- Database context set by PowerShell
-- For SSMS, uncomment the following:
/*
USE AdventureWorks2022;
GO
*/

-- Create the stored procedure for parameter sniffing demo if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_GetSalesByCustomer')
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'CREATE PROC dbo.usp_GetSalesByCustomer @CustomerID INT
    AS
    BEGIN
        SET NOCOUNT ON;
        SELECT *  -- deliberately SELECT *
        FROM   Sales.SalesOrderHeader
        WHERE  CustomerID = @CustomerID;
    END;';
    
    EXEC sp_executesql @sql;
    PRINT 'usp_GetSalesByCustomer created.';
END
ELSE
    PRINT 'usp_GetSalesByCustomer already exists - skipped.';
