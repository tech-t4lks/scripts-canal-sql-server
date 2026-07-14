-- DEMO 


CREATE TABLE deadlocks_monitor (
ID INT IDENTITY (1,1) PRIMARY KEY,
dt_hora DATETIME,
vitima_session_id INT NULL, -- PROCESSO QUE O SQL MATOU
vitima_login varchar(128) NULL,
vitima_hostname varchar(128) null,
vitima_sistema varchar(200) null, -- qual aplicação
vitima_database varchar(128) null,
vitima_query NVARCHAR(MAX) null,
-- sobrevivente
sobrevivente_session_id INT NULL,
sobrevivente_login VARCHAR(128) NULL,
sobrevivente_query NVARCHAR(MAX),

-- recurso em disputa
obj_disputado VARCHAR(256) NULL, -- QUAL TABELA/INDICE
modo_lock VARCHAR(50) NULL, -- X, S, U
-- diagrama
deadlock_graph XML null
)

-- a proc que conecta tudo isso
-- ============================================================
-- PROCEDURE CORRIGIDA — baseada na estrutura XML real
-- Descobertas do debug:
--   1. @id do processo é STRING hex (process20de02fb088), não INT
--   2. Não existe atributo @victim no <process>
--   3. A vítima é identificada pelo <victim-list><victimProcess id="..."/>
--   4. O spid (INT real da sessão) está em @spid, não em @id
-- ============================================================
-- ============================================================
-- PARTE 1 — Índices na tabela deadlocks_monitor
-- ============================================================

-- Índice principal: usado pelo NOT EXISTS (anti-duplicata)
-- Cobre exatamente as duas colunas do WHERE
CREATE NONCLUSTERED INDEX SK01_deadlocks_monitor
    ON dbo.deadlocks_monitor (dt_hora, vitima_session_id)
    WITH (FILLFACTOR = 90);

-- Índice para consultas de análise (mais comuns no dia a dia)
CREATE NONCLUSTERED INDEX SK02_deadlocks_monitor
    ON dbo.deadlocks_monitor (dt_hora DESC)
    INCLUDE (vitima_login, vitima_hostname, vitima_sistema,
             obj_disputado, modo_lock)
    WITH (FILLFACTOR = 90);

CREATE OR ALTER PROCEDURE dbo.stp_take_deadlocks
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inseridos  INT = 0;
    DECLARE @xel_path   NVARCHAR(500);

    -- ── 1. Descobre o caminho do .xel dinamicamente ───────────
    SELECT @xel_path = REPLACE(
        CAST(fld.value AS NVARCHAR(500)),
        '.xel', '*.xel'
    )
    FROM sys.server_event_sessions        ses
    JOIN sys.server_event_session_targets tgt
      ON tgt.event_session_id = ses.event_session_id
    JOIN sys.server_event_session_fields  fld
      ON fld.event_session_id = tgt.event_session_id
     AND fld.object_id        = tgt.target_id
    WHERE ses.name = 'deadlock_capture_dba'
      AND fld.name = 'filename';

    IF @xel_path IS NULL
    BEGIN
        RAISERROR('Sessão deadlock_capture_dba não encontrada.', 10, 1);
        RETURN;
    END

    -- ── 2. Extrai eventos para tabela temporária ──────────────
    CREATE TABLE #novos_deadlocks (
        dt_hora                 DATETIME       NOT NULL,
        vitima_session_id       INT            NULL,
        vitima_login            VARCHAR(128)   NULL,
        vitima_hostname         VARCHAR(128)   NULL,
        vitima_sistema          VARCHAR(200)   NULL,
        vitima_database         VARCHAR(128)   NULL,
        vitima_query            NVARCHAR(MAX)  NULL,
        sobrevivente_session_id INT            NULL,
        sobrevivente_login      VARCHAR(128)   NULL,
        sobrevivente_query      NVARCHAR(MAX)  NULL,
        obj_disputado           VARCHAR(256)   NULL,
        modo_lock               VARCHAR(50)    NULL,
        deadlock_graph          XML            NULL
    );

    -- ── Estrutura confirmada pelo XML real: ───────────────────
    -- <event name="xml_deadlock_report" timestamp="...">
    --   <data name="xml_report">
    --     <value>
    --       <deadlock>
    --         <victim-list><victimProcess id="processXXX"/></victim-list>
    --         <process-list><process id="processXXX" spid="63" .../></process-list>
    --         <resource-list><keylock objectname="..." mode="X" .../></resource-list>
    --       </deadlock>
    --     </value>
    --   </data>
    -- </event>

    INSERT INTO #novos_deadlocks
    SELECT
        dt_hora,
        vitima_session_id,
        vitima_login,
        vitima_hostname,
        vitima_sistema,
        vitima_database,
        vitima_query,
        sobrevivente_session_id,
        sobrevivente_login,
        sobrevivente_query,
        obj_disputado,
        modo_lock,
        deadlock_graph
    FROM (
        SELECT
            -- Timestamp UTC → hora local
            DATEADD(MINUTE,
                DATEDIFF(MINUTE, GETUTCDATE(), GETDATE()),
                CAST(xdata.value('(event/@timestamp)[1]', 'VARCHAR(33)') AS DATETIME2)
            )                                                               AS dt_hora,

            -- Vítima: processo cujo @id está em victim-list/victimProcess/@id
            vitima.value('(@spid)[1]',           'INT')                    AS vitima_session_id,
            vitima.value('(@loginname)[1]',      'VARCHAR(128)')           AS vitima_login,
            vitima.value('(@hostname)[1]',       'VARCHAR(128)')           AS vitima_hostname,
            vitima.value('(@clientapp)[1]',      'VARCHAR(200)')           AS vitima_sistema,
            vitima.value('(@currentdbname)[1]',  'VARCHAR(128)')           AS vitima_database,
            vitima.value('(inputbuf)[1]',        'NVARCHAR(MAX)')          AS vitima_query,

            -- Sobrevivente: processo cujo @id NÃO está na victim-list
            sobrev.value('(@spid)[1]',           'INT')                    AS sobrevivente_session_id,
            sobrev.value('(@loginname)[1]',      'VARCHAR(128)')           AS sobrevivente_login,
            sobrev.value('(inputbuf)[1]',        'NVARCHAR(MAX)')          AS sobrevivente_query,

            -- Objeto disputado: confirmado no XML como keylock/@objectname
            -- ISNULL em cascata cobre keylock, pagelock e ridlock
            ISNULL(ISNULL(
                xdata.value('(event/data[@name="xml_report"]/value/deadlock/resource-list/keylock/@objectname)[1]',  'VARCHAR(256)'),
                xdata.value('(event/data[@name="xml_report"]/value/deadlock/resource-list/pagelock/@objectname)[1]', 'VARCHAR(256)')
            ),  xdata.value('(event/data[@name="xml_report"]/value/deadlock/resource-list/ridlock/@objectname)[1]',  'VARCHAR(256)')
            )                                                               AS obj_disputado,

            -- Modo do lock (X, S, U)
            recurso.value('(@mode)[1]',          'VARCHAR(50)')            AS modo_lock,

            -- XML no formato exato que o SSMS usa para o diagrama visual
            -- O viewer exige <deadlock-graph><deadlock>...</deadlock></deadlock-graph>
            CAST(('<deadlock-graph>' +
                CAST(xdata.query(
                    'event/data[@name="xml_report"]/value/deadlock'
                ) AS NVARCHAR(MAX))
            + '</deadlock-graph>') AS XML)                                  AS deadlock_graph,

            -- Deduplicação: garante 1 linha por evento único no arquivo
            ROW_NUMBER() OVER (
                PARTITION BY
                    xdata.value('(event/@timestamp)[1]', 'VARCHAR(33)'),
                    vitima.value('(@spid)[1]', 'INT')
                ORDER BY
                    xdata.value('(event/@timestamp)[1]', 'VARCHAR(33)')
            ) AS rn

        FROM sys.fn_xe_file_target_read_file(@xel_path, NULL, NULL, NULL) xef
        CROSS APPLY (SELECT CAST(xef.event_data AS XML)) AS x(xdata)

        -- Vítima: cruza @id do process com @id do victimProcess
        CROSS APPLY xdata.nodes(
            'event/data[@name="xml_report"]/value/deadlock
             /process-list/process[
                 @id = ../../victim-list/victimProcess/@id
             ]'
        ) AS v(vitima)

        -- Sobrevivente: processo que NÃO está na victim-list
        CROSS APPLY xdata.nodes(
            'event/data[@name="xml_report"]/value/deadlock
             /process-list/process[
                 @id != ../../victim-list/victimProcess/@id
             ]'
        ) AS s(sobrev)

        -- Recurso em disputa (para o modo_lock)
        CROSS APPLY xdata.nodes(
            'event/data[@name="xml_report"]/value/deadlock
             /resource-list/*'
        ) AS r(recurso)

        -- Filtra só eventos de deadlock
        WHERE xef.object_name IN (
            'xml_deadlock_report',
            'database_xml_deadlock_report'
        )

    ) src
    WHERE rn = 1;

    -- ── 3. Insere apenas registros novos (anti-duplicata) ─────
    INSERT INTO dbo.deadlocks_monitor (
        dt_hora,
        vitima_session_id,
        vitima_login,
        vitima_hostname,
        vitima_sistema,
        vitima_database,
        vitima_query,
        sobrevivente_session_id,
        sobrevivente_login,
        sobrevivente_query,
        obj_disputado,
        modo_lock,
        deadlock_graph
    )
    SELECT
        n.dt_hora,
        n.vitima_session_id,
        n.vitima_login,
        n.vitima_hostname,
        n.vitima_sistema,
        n.vitima_database,
        n.vitima_query,
        n.sobrevivente_session_id,
        n.sobrevivente_login,
        n.sobrevivente_query,
        n.obj_disputado,
        n.modo_lock,
        n.deadlock_graph
    FROM #novos_deadlocks          n
    LEFT JOIN dbo.deadlocks_monitor d
           ON d.dt_hora           = n.dt_hora
          AND d.vitima_session_id = n.vitima_session_id
    WHERE d.ID IS NULL;

    SET @inseridos = @@ROWCOUNT;

    DROP TABLE #novos_deadlocks;

    PRINT CONCAT('Deadlocks inseridos: ', @inseridos);

END;
GO

-- ── Teste ─────────────────────────────────────────────────────
-- EXEC dbo.stp_take_deadlocks;
--
-- SELECT
--     ID, dt_hora,
--     vitima_login, vitima_hostname, vitima_sistema, vitima_database,
--     LEFT(vitima_query, 100)  AS vitima_query,
--     sobrevivente_login,
--     obj_disputado, modo_lock,
--     deadlock_graph           -- clique para o diagrama visual
-- FROM dbo.deadlocks_monitor
-- ORDER BY dt_hora DESC;


-- ── Teste ─────────────────────────────────────────────────────
-- EXEC dbo.stp_take_deadlocks;
--
-- SELECT
--     ID, dt_hora,
--     vitima_login, vitima_hostname, vitima_sistema, vitima_database,
--     LEFT(vitima_query, 100)  AS vitima_query,
--     sobrevivente_login,
--     obj_disputado, modo_lock,
--     deadlock_graph           -- clique para o diagrama visual
-- FROM dbo.deadlocks_monitor
-- ORDER BY dt_hora DESC;
-- ── Verificar resultado ───────────────────────────────────────
-- EXEC dbo.stp_take_deadlocks;

 SELECT
     ID, dt_hora,
     vitima_login, vitima_hostname, vitima_sistema, vitima_database,
     LEFT(vitima_query, 100)  AS vitima_query,
     sobrevivente_login,
     obj_disputado, modo_lock,
     deadlock_graph           -- clique para o diagrama visual
 FROM dbo.deadlocks_monitor
 ORDER BY dt_hora DESC;


EXEC dbo.stp_take_deadlocks

select * from deadlocks_monitor

SELECT
    ID,
    dt_hora,
    vitima_session_id,
    vitima_login,
    vitima_hostname,
    vitima_sistema,
    vitima_database,
    LEFT(vitima_query, 100)      AS vitima_query,
    sobrevivente_session_id,
    sobrevivente_login,
    obj_disputado,
    modo_lock,
    deadlock_graph               -- clique para ver o diagrama visual
FROM dbo.deadlocks_monitor
ORDER BY dt_hora DESC;


truncate table deadlocks_monitor


-- objeto mais disputado
SELECT
obj_disputado,
modo_lock,
COUNT(*) AS total_deadlocks,
COUNT(DISTINCT vitima_login) AS logins_envolvidos,
MIN(dt_hora) AS primeiro,
MAX(dt_hora) AS ultimo
FROM deadlocks_monitor
WHERE dt_hora >= DATEADD(HOUR, -24, GETDATE())
GROUP BY obj_disputado, modo_lock
ORDER BY total_deadlocks DESC;


-- aplicações que mais geram locks 
SELECT
vitima_sistema,
vitima_hostname,
COUNT(*) AS total
FROM deadlocks_monitor
GROUP BY vitima_sistema, vitima_hostname
ORDER BY total DESC;
