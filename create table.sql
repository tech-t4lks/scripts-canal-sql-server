use DBA_MONITOR
GO
CREATE TABLE growth_table_monitoring(
	id INT IDENTITY(1,1)PRIMARY KEY,
	database_name SYSNAME NOT NULL,
	schema_name SYSNAME NOT NULL,
	table_name SYSNAME NOT NULL,
	row_count BIGINT NOT NULL,
	table_size_MB DECIMAL(18,2) NOT NULL,
	growth_rows BIGINT NULL,
	growth_mb DECIMAL(18,2) NOT NULL,
	growth_percent DECIMAL(10,2) NOT NULl,
	insert_info_dt DATETIME NOT NULL DEFAULT GETDATE()



)

CREATE INDEX SK01_growth_table_monitoring  ON growth_table_monitoring (insert_info_dt)
WITH(FILLFACTOR=95, DATA_COMPRESSION=PAGE, SORT_IN_TEMPDB=ON)
