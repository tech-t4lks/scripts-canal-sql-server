-- query ira fazer scan , b-tree
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, nome, preco
FROM produtos
WHERE preco BETWEEN 100 AND 2000;

-- b-tree
CREATE INDEX produtos_01 ON produtos (preco)
include(id, nome)


-- hash
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT nome, preco FROM produtos
where sku ='NB-LENOVO-006'

VACUUM ANALYZE produtos;
create INDEX produtos_02 ON produtos USING HASH (sku)

-- gin

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, nome, preco, tags FROM produtos
WHERE tags @> ARRAY['cpu'];

CREATE INDEX gin_produtos ON produtos USING GIN (tags)

-- GIST
-- ranges 
EXPLAIN (ANALYZE, BUFFERS)
SELECT nome, desconto_pct FROM promocoes
WHERE periodo && '[2024-12-01, 2024-12-31]'::tstzrange;

CREATE INDEX gist_promocoes on  promocoes USING GIST (periodo)

-- query PG exibe info completa indices
-- ============================================================
-- Consulta completa de índices por tabela — PostgreSQL
-- Uso: substitua 'nome_da_tabela' pelo nome real
-- ============================================================

SELECT
    -- Identificação
    t.relname                               AS tabela,
    i.relname                               AS indice,
    ix.indisprimary                         AS chave_primaria,
    ix.indisunique                          AS unico,
    ix.indisvalid                           AS valido,
    ix.indisprimary OR ix.indisunique       AS constraint,

    -- Tipo do índice (B-tree, Hash, GIN, GiST, BRIN, etc.)
    am.amname                               AS tipo_indice,

    -- Colunas indexadas (na ordem correta do índice)
    ARRAY_AGG(
        a.attname
        ORDER BY array_position(ix.indkey, a.attnum)
    )                                       AS colunas,

    -- Colunas do INCLUDE (covering index — PostgreSQL 11+)
    (
        SELECT ARRAY_AGG(att.attname)
        FROM pg_attribute att
        WHERE att.attrelid = t.oid
          AND att.attnum = ANY(
              ix.indkey[ix.indnkeyatts : array_length(ix.indkey, 1) - 1]
          )
    )                                       AS colunas_include,

    -- Definição DDL completa (o CREATE INDEX exato)
    pg_get_indexdef(i.oid)                  AS definicao_ddl,

    -- Índice parcial? (tem cláusula WHERE?)
    CASE
        WHEN pg_get_indexdef(i.oid) LIKE '%WHERE%'
        THEN SUBSTRING(pg_get_indexdef(i.oid)
                       FROM POSITION('WHERE' IN pg_get_indexdef(i.oid)))
        ELSE NULL
    END                                     AS condicao_where,

    -- Tamanho em disco
    pg_size_pretty(pg_relation_size(i.oid)) AS tamanho,
    pg_relation_size(i.oid)                 AS tamanho_bytes,

    -- Estatísticas de uso (desde o último ANALYZE ou restart)
    s.idx_scan                              AS total_varreduras,
    s.idx_tup_read                          AS linhas_lidas,
    s.idx_tup_fetch                         AS linhas_retornadas,

    -- Índice nunca foi usado?
    CASE WHEN s.idx_scan = 0 THEN '⚠ NUNCA USADO' ELSE NULL END
                                            AS alerta

FROM pg_index        ix
JOIN pg_class        t   ON t.oid  = ix.indrelid
JOIN pg_class        i   ON i.oid  = ix.indexrelid
JOIN pg_am           am  ON am.oid = i.relam
JOIN pg_attribute    a   ON a.attrelid = t.oid
                        AND a.attnum   = ANY(ix.indkey)
                        AND a.attnum   > 0
LEFT JOIN pg_stat_user_indexes s
                         ON s.indexrelid = i.oid

WHERE t.relname  = 'produtos'   -- << troque aqui
  AND t.relkind  = 'r'                -- apenas tabelas normais

GROUP BY
    t.relname, i.relname, i.oid,
    ix.indisprimary, ix.indisunique, ix.indisvalid,
    ix.indnkeyatts, ix.indkey, t.oid,
    am.amname,
    s.idx_scan, s.idx_tup_read, s.idx_tup_fetch

ORDER BY
    ix.indisprimary DESC,   -- PK primeiro
    ix.indisunique  DESC,   -- únicos depois
    pg_relation_size(i.oid) DESC;  -- maiores por último



