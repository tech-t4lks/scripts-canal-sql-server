-- habilitando cdc
use StackOverflowMini
go
EXEC sys.sp_cdc_enable_db;


-- validar se esta ativo
SELECT is_cdc_enabled, name FROM sys.databases

-- quais tabelas estão monitoradas pelo CDC
SELECT name, is_tracked_by_cdc
FROM sys.tables

-- habilitar o cdc em uma tabela 
EXEC sys.sp_cdc_enable_table @source_schema = 'dbo', @source_name = 'Users', @role_name = NULL;


-- tabelas internas do cdc

use Northwind
select * from cdc.captured_columns


select * from cdc.ddl_history



-- consultar alterações
SELECT * FROM cdc.dbo_Comments_CT


-- habilitar o cdc em uma tabela com campos especificos
EXEC sys.sp_cdc_enable_table 
@source_schema = 'dbo', 
@source_name = 'Comments', 
@role_name = NULL,
@captured_column_list = '[id],[Score]'

/* ID das operações

1: DELETE
2: INSERT
3: Valor ANTES do UPDATE
4: Valor APÓS o UPDATE
*/

-- alterando a retenção das tabelas do cdc
EXEC sp_cdc_change_job 
    @job_type='cleanup', 
    @retention=7200 -- 5 dias (quantidade de minutos de retenção)

    -- visualizar os parametros de retenção
SELECT 
    [retention],
    ([retention]) / ((60 * 24)) AS RetentionInDays,
    *
FROM
    msdb.dbo.cdc_jobs;

-- como desabilitar o cdc, primeiro no database
USE Northwind
GO

EXEC sys.sp_cdc_disable_db
GO

-- desativar em uma tabela
USE Northwind
GO

EXEC sys.sp_cdc_help_change_data_capture
GO

SELECT OBJECT_NAME([object_id]), OBJECT_NAME(source_object_id), capture_instance
FROM cdc.change_tables






