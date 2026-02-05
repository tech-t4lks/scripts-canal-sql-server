-- procedure

CREATE OR ALTER PROCEDURE dbo.stp_monitor_SalesOrderDetail_growth
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @RowCount BIGINT,
        @TableSizeMB DECIMAL(18,2),
        @LastRowCount BIGINT,
        @LastTableSizeMB DECIMAL(18,2),
        @GrowthRows BIGINT,
        @GrowthMB DECIMAL(18,2),
        @GrowthPercent DECIMAL(10,2);

    -- Coleta atual
    SELECT 
        @RowCount = SUM(row_count),
        @TableSizeMB = SUM(reserved_page_count) * 8.0 / 1024
    FROM AdventureWorks2022.sys.dm_db_partition_stats
    WHERE object_id = OBJECT_ID('AdventureWorks2022.Sales.SalesOrderDetail')
      AND index_id IN (0,1)-- 0 = HEAP, 1= INDICE CLUSTERED

    -- Última coleta
    SELECT TOP 1
        @LastRowCount = row_count,
        @LastTableSizeMB = table_size_mb
    FROM dbo.growth_table_monitoring
    ORDER BY insert_info_dt DESC;

    -- Cálculos
    SET @GrowthRows = @RowCount - ISNULL(@LastRowCount, @RowCount);
    SET @GrowthMB   = @TableSizeMB - ISNULL(@LastTableSizeMB, @TableSizeMB);

    SET @GrowthPercent =
        CASE 
            WHEN ISNULL(@LastTableSizeMB, 0) = 0 THEN 0
            ELSE (@GrowthMB / @LastTableSizeMB) * 100
        END;

    -- Insert
    INSERT INTO dbo.growth_table_monitoring
    (
        database_name,
        schema_name,
        table_name,
        row_count,
        table_size_mb,
        growth_rows,
        growth_mb,
        growth_percent
    )
    VALUES
    (
        'AdventureWorks2022',
        'Sales',
        'SalesOrderDetail',
        @RowCount,
        @TableSizeMB,
        @GrowthRows,
        @GrowthMB,
        @GrowthPercent
    );
END;
GO
