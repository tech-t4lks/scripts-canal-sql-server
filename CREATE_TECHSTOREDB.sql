


-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS pg_trgm;       -- para GIN com LIKE
CREATE EXTENSION IF NOT EXISTS btree_gist;    -- para GiST com tipos escalares
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- para gerar UUIDs

-- ============================================================
-- SCHEMA
-- ============================================================

-- ── Categorias ────────────────────────────────────────────────
CREATE TABLE categorias (
    id          SERIAL PRIMARY KEY,
    nome        VARCHAR(100) NOT NULL,
    slug        VARCHAR(100) NOT NULL UNIQUE,
    descricao   TEXT
);

-- ── Produtos ─────────────────────────────────────────────────
-- Usada para demo de: B-tree (preco, criado_em), Hash (sku)
CREATE TABLE produtos (
    id              SERIAL PRIMARY KEY,
    sku             VARCHAR(20)     NOT NULL UNIQUE,   -- Hash demo
    nome            VARCHAR(200)    NOT NULL,
    descricao       TEXT,
    categoria_id    INT             REFERENCES categorias(id),
    preco           NUMERIC(10,2)   NOT NULL,          -- B-tree demo
    estoque         INT             NOT NULL DEFAULT 0,
    ativo           BOOLEAN         NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),  -- B-tree demo
    atualizado_em   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    -- Tags em array → GIN demo
    tags            TEXT[]          DEFAULT '{}',
    -- Especificações técnicas em JSONB → GIN demo
    specs           JSONB           DEFAULT '{}'
);

-- ── Clientes ─────────────────────────────────────────────────
CREATE TABLE clientes (
    id              SERIAL PRIMARY KEY,
    uuid            UUID            NOT NULL DEFAULT uuid_generate_v4(),  -- Hash demo
    nome            VARCHAR(200)    NOT NULL,
    email           VARCHAR(200)    NOT NULL UNIQUE,
    cpf             CHAR(11)        UNIQUE,
    telefone        VARCHAR(20),
    cidade          VARCHAR(100),
    estado          CHAR(2),
    ativo           BOOLEAN         NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ── Pedidos ──────────────────────────────────────────────────
-- Usada para demo de: B-tree (status, criado_em), range queries
CREATE TABLE pedidos (
    id              SERIAL PRIMARY KEY,
    cliente_id      INT             NOT NULL REFERENCES clientes(id),
    status          VARCHAR(20)     NOT NULL DEFAULT 'pendente',
    total           NUMERIC(10,2)   NOT NULL,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),  -- B-tree demo
    entregue_em     TIMESTAMPTZ,
    endereco_json   JSONB           DEFAULT '{}'
);

-- ── Itens do Pedido ───────────────────────────────────────────
CREATE TABLE pedido_itens (
    id              SERIAL PRIMARY KEY,
    pedido_id       INT             NOT NULL REFERENCES pedidos(id),
    produto_id      INT             NOT NULL REFERENCES produtos(id),
    quantidade      INT             NOT NULL,
    preco_unit      NUMERIC(10,2)   NOT NULL
);

-- ── Avaliações ────────────────────────────────────────────────
-- Usada para demo de: GIN (texto livre em conteudo)
CREATE TABLE avaliacoes (
    id              SERIAL PRIMARY KEY,
    produto_id      INT             NOT NULL REFERENCES produtos(id),
    cliente_id      INT             NOT NULL REFERENCES clientes(id),
    nota            SMALLINT        NOT NULL CHECK (nota BETWEEN 1 AND 5),
    titulo          VARCHAR(200),
    conteudo        TEXT,                -- GIN + pg_trgm demo (busca textual)
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ── Logs de Acesso ────────────────────────────────────────────
-- Usada para demo de: B-tree composto (session_id + criado_em)
--                     Hash (session_id lookup exato)
CREATE TABLE logs_acesso (
    id              BIGSERIAL PRIMARY KEY,
    session_id      UUID            NOT NULL,   -- Hash demo
    cliente_id      INT             REFERENCES clientes(id),
    pagina          VARCHAR(200),
    acao            VARCHAR(50),
    ip              INET,
    criado_em       TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ── Promoções com Período ────────────────────────────────────
-- Usada para demo de: GiST (range de datas — tstzrange)
CREATE TABLE promocoes (
    id              SERIAL PRIMARY KEY,
    nome            VARCHAR(200)    NOT NULL,
    desconto_pct    NUMERIC(5,2)    NOT NULL,
    periodo         TSTZRANGE       NOT NULL,   -- GiST demo!
    ativo           BOOLEAN         NOT NULL DEFAULT TRUE,
    categorias_ids  INT[]           DEFAULT '{}'
);

-- ── Estoque por Localização ───────────────────────────────────
-- Usada para demo de: GiST (círculos/pontos geográficos com point)
-- e também exclusão por sobreposição de período (GiST exclusion)
CREATE TABLE reservas_estoque (
    id              SERIAL PRIMARY KEY,
    produto_id      INT             NOT NULL REFERENCES produtos(id),
    pedido_id       INT             REFERENCES pedidos(id),
    quantidade      INT             NOT NULL,
    periodo         TSTZRANGE       NOT NULL,   -- GiST exclusion demo
    EXCLUDE USING GIST (produto_id WITH =, periodo WITH &&)
);

-- ============================================================
-- DADOS FICTÍCIOS
-- ============================================================

-- ── Categorias ────────────────────────────────────────────────

INSERT INTO categorias (nome, slug, descricao) VALUES
    ('Notebooks',        'notebooks',       'Laptops e ultrabooks'),
    ('Smartphones',      'smartphones',     'Celulares e acessórios'),
    ('Monitores',        'monitores',       'Monitores para trabalho e gaming'),
    ('Periféricos',      'perifericos',     'Teclados, mouses e headsets'),
    ('Armazenamento',    'armazenamento',   'SSDs, HDDs e pendrives'),
    ('Componentes',      'componentes',     'Placas de vídeo, memórias, processadores'),
    ('Redes',            'redes',           'Roteadores, switches e cabos'),
    ('Energia',          'energia',         'Nobreaks, estabilizadores e cabos');

-- ── Produtos (100 produtos com dados variados) ────────────────
INSERT INTO produtos (sku, nome, descricao, categoria_id, preco, estoque, tags, specs) VALUES
-- Notebooks
('NB-DELL-001', 'Dell Inspiron 15 3520', 'Notebook para uso geral com processador Intel i5', 1, 3299.00, 15,
 ARRAY['notebook','dell','intel','i5','windows'],
 '{"cpu":"Intel i5-1235U","ram":"8GB","ssd":"256GB","tela":"15.6 FHD","so":"Windows 11"}'::jsonb),

('NB-LENOVO-002', 'Lenovo IdeaPad 3i', 'Notebook custo-benefício com Intel i3', 1, 2499.00, 22,
 ARRAY['notebook','lenovo','intel','i3','windows','barato'],
 '{"cpu":"Intel i3-1215U","ram":"8GB","ssd":"256GB","tela":"15.6 HD","so":"Windows 11"}'::jsonb),

('NB-APPLE-003', 'MacBook Air M2 13"', 'O ultrabook mais fino da Apple com chip M2', 1, 10999.00, 8,
 ARRAY['notebook','apple','macbook','m2','macos','ultrabook'],
 '{"cpu":"Apple M2","ram":"8GB","ssd":"256GB","tela":"13.6 Liquid Retina","so":"macOS"}'::jsonb),

('NB-ASUS-004', 'ASUS VivoBook 15', 'Notebook slim para produtividade', 1, 2899.00, 18,
 ARRAY['notebook','asus','vivobook','slim','windows'],
 '{"cpu":"AMD Ryzen 5 5500U","ram":"8GB","ssd":"512GB","tela":"15.6 FHD","so":"Windows 11"}'::jsonb),

('NB-DELL-005', 'Dell XPS 15 9530', 'Notebook premium para profissionais criativos', 1, 14999.00, 4,
 ARRAY['notebook','dell','xps','premium','4k','criativo'],
 '{"cpu":"Intel i7-13700H","ram":"16GB","ssd":"512GB","tela":"15.6 OLED 4K","so":"Windows 11"}'::jsonb),

('NB-LENOVO-006', 'Lenovo ThinkPad E14', 'Notebook corporativo robusto', 1, 4899.00, 11,
 ARRAY['notebook','lenovo','thinkpad','corporativo','business'],
 '{"cpu":"AMD Ryzen 7 5700U","ram":"16GB","ssd":"512GB","tela":"14 FHD","so":"Windows 11 Pro"}'::jsonb),

('NB-SAMSUNG-007', 'Samsung Galaxy Book3', 'Notebook Samsung com integração Android', 1, 5299.00, 7,
 ARRAY['notebook','samsung','galaxy','android','windows'],
 '{"cpu":"Intel i5-1335U","ram":"8GB","ssd":"256GB","tela":"15.6 FHD","so":"Windows 11"}'::jsonb),

-- Smartphones
('SM-APPLE-001', 'iPhone 15 128GB', 'Smartphone Apple com chip A16 Bionic', 2, 5999.00, 25,
 ARRAY['smartphone','iphone','apple','ios','5g'],
 '{"cpu":"Apple A16","ram":"6GB","armazenamento":"128GB","camera":"48MP","so":"iOS 17"}'::jsonb),

('SM-SAMSUNG-002', 'Samsung Galaxy S24', 'Flagship Samsung com IA integrada', 2, 5499.00, 20,
 ARRAY['smartphone','samsung','android','5g','ia','flagship'],
 '{"cpu":"Snapdragon 8 Gen 3","ram":"8GB","armazenamento":"128GB","camera":"50MP","so":"Android 14"}'::jsonb),

('SM-MOTO-003', 'Motorola Moto G84', 'Custo-benefício com tela OLED', 2, 1599.00, 45,
 ARRAY['smartphone','motorola','moto','android','custo-beneficio','oled'],
 '{"cpu":"Snapdragon 695","ram":"12GB","armazenamento":"256GB","camera":"50MP","so":"Android 13"}'::jsonb),

('SM-XIAOMI-004', 'Xiaomi Redmi Note 13', 'Smartphone com câmera de 200MP', 2, 1899.00, 38,
 ARRAY['smartphone','xiaomi','redmi','android','camera','200mp'],
 '{"cpu":"Snapdragon 7s Gen 2","ram":"8GB","armazenamento":"256GB","camera":"200MP","so":"Android 13"}'::jsonb),

('SM-SAMSUNG-005', 'Samsung Galaxy A55', 'Intermediário premium da Samsung', 2, 2499.00, 30,
 ARRAY['smartphone','samsung','galaxy','android','5g'],
 '{"cpu":"Exynos 1480","ram":"8GB","armazenamento":"128GB","camera":"50MP","so":"Android 14"}'::jsonb),

-- Monitores
('MN-LG-001', 'LG 27" 4K IPS', 'Monitor 4K para profissionais de design', 3, 2299.00, 12,
 ARRAY['monitor','lg','4k','ips','design','profissional'],
 '{"tamanho":"27","resolucao":"3840x2160","painel":"IPS","refresh":"60Hz","hdr":"HDR400"}'::jsonb),

('MN-SAMSUNG-002', 'Samsung Odyssey G5 27"', 'Monitor gamer curvo 165Hz', 3, 1799.00, 17,
 ARRAY['monitor','samsung','gamer','curvo','165hz','qhd'],
 '{"tamanho":"27","resolucao":"2560x1440","painel":"VA curvo","refresh":"165Hz","hdr":"HDR10"}'::jsonb),

('MN-DELL-003', 'Dell UltraSharp 27 USB-C', 'Monitor corporativo com USB-C', 3, 3199.00, 9,
 ARRAY['monitor','dell','ultrasharp','usbc','corporativo','qhd'],
 '{"tamanho":"27","resolucao":"2560x1440","painel":"IPS","refresh":"60Hz","usbc":"96W"}'::jsonb),

('MN-AOC-004', 'AOC 24" Full HD 144Hz', 'Monitor gamer acessível', 3, 899.00, 28,
 ARRAY['monitor','aoc','gamer','144hz','fhd','acessivel'],
 '{"tamanho":"24","resolucao":"1920x1080","painel":"IPS","refresh":"144Hz","hdr":"N/A"}'::jsonb),

-- Periféricos
('PR-LOGITECH-001', 'Logitech MX Master 3S', 'Mouse sem fio premium para produtividade', 4, 699.00, 40,
 ARRAY['mouse','logitech','mx','wireless','produtividade','premium'],
 '{"conexao":"Bluetooth/USB","dpi":"8000","botoes":"7","bateria":"70 dias"}'::jsonb),

('PR-KEYCHRON-002', 'Keychron K2 Pro', 'Teclado mecânico compacto sem fio', 4, 899.00, 22,
 ARRAY['teclado','mecanico','keychron','wireless','compacto','rgb'],
 '{"switch":"Gateron Red","layout":"75%","conexao":"Bluetooth/USB-C","backlight":"RGB"}'::jsonb),

('PR-RAZER-003', 'Razer DeathAdder V3', 'Mouse gamer ergonômico', 4, 499.00, 35,
 ARRAY['mouse','razer','gamer','ergonomico','fps'],
 '{"conexao":"USB","dpi":"30000","botoes":"6","sensor":"Focus Pro 30K"}'::jsonb),

('PR-JBLS-004', 'JBL Quantum 910', 'Headset gamer sem fio com cancelamento de ruído', 4, 1299.00, 15,
 ARRAY['headset','jbl','gamer','wireless','anc','surround'],
 '{"conexao":"USB/3.5mm","surround":"7.1","anc":"Sim","bateria":"34 horas"}'::jsonb),

('PR-LOGITECH-005', 'Logitech G Pro X Superlight 2', 'Mouse gamer ultraleve', 4, 899.00, 18,
 ARRAY['mouse','logitech','gamer','ultraleve','fps','wireless'],
 '{"conexao":"USB sem fio","dpi":"32000","peso":"60g","sensor":"HERO 2"}'::jsonb),

-- Armazenamento
('ST-SAMSUNG-001', 'Samsung 990 Pro SSD 1TB NVMe', 'SSD NVMe de alta performance', 5, 699.00, 30,
 ARRAY['ssd','samsung','nvme','m2','rapido'],
 '{"interface":"PCIe 4.0 NVMe","capacidade":"1TB","leitura":"7450 MB/s","escrita":"6900 MB/s"}'::jsonb),

('ST-SEAGATE-002', 'Seagate Barracuda HDD 2TB', 'HD externo para armazenamento massivo', 5, 349.00, 50,
 ARRAY['hd','seagate','2tb','armazenamento','backup'],
 '{"interface":"SATA 6Gb/s","capacidade":"2TB","rpm":"7200","cache":"256MB"}'::jsonb),

('ST-SANDISK-003', 'SanDisk Extreme SSD Portátil 1TB', 'SSD externo robusto e rápido', 5, 599.00, 25,
 ARRAY['ssd','sandisk','externo','portatil','robusto','usbc'],
 '{"interface":"USB 3.2 Gen 2","capacidade":"1TB","leitura":"1050 MB/s","ip":"IP55"}'::jsonb),

-- Componentes
('CP-NVIDIA-001', 'NVIDIA GeForce RTX 4060', 'Placa de vídeo para gaming 1080p/1440p', 6, 2299.00, 8,
 ARRAY['gpu','nvidia','rtx','gaming','1440p','dlss'],
 '{"vram":"8GB GDDR6","barramento":"128-bit","tdp":"115W","saidas":"HDMI 2.1 x1, DP 1.4 x3"}'::jsonb),

('CP-AMD-002', 'AMD Radeon RX 7600', 'GPU para gaming custo-benefício', 6, 1799.00, 12,
 ARRAY['gpu','amd','radeon','gaming','custo-beneficio'],
 '{"vram":"8GB GDDR6","barramento":"128-bit","tdp":"165W","saidas":"HDMI 2.1 x1, DP 2.1 x3"}'::jsonb),

('CP-CORSAIR-003', 'Corsair Vengeance 32GB DDR5', 'Kit memória RAM DDR5 para plataformas modernas', 6, 599.00, 20,
 ARRAY['ram','corsair','ddr5','32gb','kit','gaming'],
 '{"tipo":"DDR5","capacidade":"2x16GB","frequencia":"5600MHz","latencia":"CL36"}'::jsonb),

('CP-INTEL-004', 'Intel Core i7-14700K', 'Processador desktop de alto desempenho', 6, 2199.00, 6,
 ARRAY['cpu','intel','i7','desktop','gaming','overclock'],
 '{"nucleos":"20 (8P+12E)","threads":"28","boost":"5.6 GHz","tdp":"125W","socket":"LGA1700"}'::jsonb),

-- Redes
('RD-TPLINK-001', 'TP-Link Archer AX73', 'Roteador WiFi 6 AX5400', 7, 699.00, 25,
 ARRAY['roteador','tplink','wifi6','ax5400','gigabit'],
 '{"padrao":"WiFi 6 (802.11ax)","velocidade":"AX5400","portas":"5x Gigabit","usb":"USB 3.0"}'::jsonb),

('RD-INTELBRAS-002', 'Intelbras Switch 8 portas Gigabit', 'Switch não gerenciado para pequenas redes', 7, 199.00, 40,
 ARRAY['switch','intelbras','gigabit','rede','escritorio'],
 '{"portas":"8x 1Gbps","tipo":"Não gerenciado","montagem":"Desktop/Rack"}'::jsonb);

-- ── Inserir mais 70 produtos via generate_series ──────────────
INSERT INTO produtos (sku, nome, descricao, categoria_id, preco, estoque, tags, specs)
SELECT
    'GEN-' || LPAD(gs::text, 5, '0'),
    CASE (gs % 8)
        WHEN 0 THEN 'Notebook Genérico Linha ' || gs
        WHEN 1 THEN 'Smartphone Mid-Range Modelo ' || gs
        WHEN 2 THEN 'Monitor Full HD ' || gs || '"'
        WHEN 3 THEN 'Teclado Membrana Office ' || gs
        WHEN 4 THEN 'SSD SATA 480GB Série ' || gs
        WHEN 5 THEN 'Cabo HDMI 2.0 ' || gs || 'm'
        WHEN 6 THEN 'Hub USB-C 7 em 1 Modelo ' || gs
        ELSE    'Carregador Universal ' || gs || 'W'
    END,
    'Produto de demonstração gerado automaticamente. Referência: ' || gs,
    (gs % 8) + 1,
    ROUND((RANDOM() * 4500 + 99)::numeric, 2),
    (RANDOM() * 100 + 1)::int,
    ARRAY[
        CASE (gs % 4) WHEN 0 THEN 'oferta' WHEN 1 THEN 'novo' WHEN 2 THEN 'popular' ELSE 'destaque' END,
        CASE (gs % 3) WHEN 0 THEN 'frete-gratis' WHEN 1 THEN 'parcelado' ELSE 'garantia-2anos' END
    ],
    jsonb_build_object(
        'garantia', (gs % 3 + 1) || ' ano(s)',
        'peso_kg',  ROUND((RANDOM() * 3 + 0.1)::numeric, 2),
        'cor',      CASE (gs % 5) WHEN 0 THEN 'Preto' WHEN 1 THEN 'Prata' WHEN 2 THEN 'Branco' WHEN 3 THEN 'Azul' ELSE 'Cinza' END
    )
FROM generate_series(1, 70) gs;

-- ── Clientes (200 clientes) ───────────────────────────────────
-- ── Clientes (200 clientes) ───────────────────────────────────
INSERT INTO clientes (nome, email, cpf, telefone, cidade, estado)
SELECT
    (ARRAY['Ana','Bruno','Carlos','Daniela','Eduardo','Fernanda','Gabriel','Helena',
            'Igor','Julia','Kaique','Laura','Marcos','Natalia','Otavio','Patricia',
            'Rafael','Sandra','Thiago','Vanessa'])[((gs-1) % 20) + 1]
    || ' ' ||
    (ARRAY['Silva','Santos','Oliveira','Souza','Lima','Costa','Ferreira','Rodrigues',
            'Alves','Nascimento','Martins','Carvalho','Araujo','Gomes','Dias',
            'Barbosa','Ribeiro','Pereira','Moura','Cardoso'])[((gs*3) % 20) + 1]
    AS nome,
    'cliente' || gs || '@email.com.br',
    LPAD(((gs::bigint * 123456789) % 100000000000)::text, 11, '0'), -- Corrigido aqui com ::bigint
    '(11) 9' || LPAD((RANDOM()*99999999)::bigint::text, 8, '0'),     -- Corrigido aqui com ::bigint
    (ARRAY['São Paulo','Rio de Janeiro','Belo Horizonte','Porto Alegre','Curitiba',
            'Salvador','Fortaleza','Recife','Manaus','Brasília','Campinas','Guarulhos',
            'São Bernardo','Osasco','Ribeirão Preto'])[((gs-1) % 15) + 1],
    (ARRAY['SP','RJ','MG','RS','PR','BA','CE','PE','AM','DF','SP','SP','SP','SP','SP'])[((gs-1) % 15) + 1]
FROM generate_series(1, 200) gs;

-- ── Pedidos (800 pedidos nos últimos 2 anos) ──────────────────
INSERT INTO pedidos (cliente_id, status, total, criado_em, entregue_em)
SELECT
    (RANDOM() * 199 + 1)::int,
    (ARRAY['pendente','aprovado','enviado','entregue','cancelado'])[((gs % 5) + 1)],
    ROUND((RANDOM() * 8000 + 150)::numeric, 2),
    NOW() - (RANDOM() * 730)::int * INTERVAL '1 day'
        - (RANDOM() * 23)::int * INTERVAL '1 hour',
    CASE WHEN (gs % 5) = 3
        THEN NOW() - (RANDOM() * 700)::int * INTERVAL '1 day'
        ELSE NULL
    END
FROM generate_series(1, 800) gs;

-- ── Itens dos Pedidos ─────────────────────────────────────────
INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, preco_unit)
SELECT
    p.id,
    (RANDOM() * 99 + 1)::int,
    (RANDOM() * 4 + 1)::int,
    ROUND((RANDOM() * 2000 + 99)::numeric, 2)
FROM pedidos p
CROSS JOIN generate_series(1, (RANDOM() * 3 + 1)::int) gs;

-- ── Avaliações (1.500 avaliações com texto) ───────────────────
INSERT INTO avaliacoes (produto_id, cliente_id, nota, titulo, conteudo)
SELECT
    (RANDOM() * 99 + 1)::int,
    (RANDOM() * 199 + 1)::int,
    (RANDOM() * 4 + 1)::int,
    (ARRAY[
        'Produto excelente, superou minhas expectativas',
        'Boa qualidade pelo preço',
        'Entrega rápida, produto conforme descrito',
        'Recomendo muito, comprei e não me arrependi',
        'Qualidade mediana, esperava mais',
        'Produto com defeito, tive que devolver',
        'Melhor compra que fiz esse ano',
        'Performance incrível para o valor pago',
        'Chegou bem embalado, funcionando perfeitamente',
        'Custo-benefício excelente para o dia a dia'
    ])[(RANDOM() * 9 + 1)::int],
    (ARRAY[
        'Comprei esse produto há algumas semanas e estou muito satisfeito. A qualidade é excelente e o desempenho supera o esperado.',
        'Produto chegou no prazo, bem embalado. A qualidade é boa para o preço praticado. Recomendo para quem busca custo-benefício.',
        'Infelizmente o produto não correspondeu às minhas expectativas. A qualidade deixou a desejar em alguns pontos.',
        'Excelente produto! Já era cliente da loja e mais uma vez não decepcionou. Entrega rápida e produto de primeira.',
        'Comprei para trabalho e estou adorando. Performance muito boa, sem travamentos. Vale cada centavo.',
        'O produto é bom mas o manual está incompleto. Precisei buscar informações online. No geral funciona bem.',
        'Chegou antes do prazo estimado. Produto idêntico ao descrito no site. Muito satisfeito com a compra.',
        'Ótima compra! Meu filho adorou o presente. Qualidade muito boa e o preço estava ótimo no dia que comprei.',
        'Produto funcional, mas poderia ter melhor acabamento. Para o preço, é aceitável. Entrega dentro do prazo.',
        'Sensacional! Melhor produto que já comprei nessa categoria. Altamente recomendado para quem precisa de performance.'
    ])[(RANDOM() * 9 + 1)::int]
FROM generate_series(1, 1500) gs;

-- ── Logs de Acesso (50.000 registros para demo de performance) ─
INSERT INTO logs_acesso (session_id, cliente_id, pagina, acao, ip, criado_em)
SELECT
    uuid_generate_v4(),
    CASE WHEN RANDOM() > 0.3 THEN (RANDOM() * 199 + 1)::int ELSE NULL END,
    (ARRAY[
        '/produtos','/','/produto/detalhe','/carrinho',
        '/checkout','/minha-conta','/busca','/categoria',
        '/promocoes','/contato'
    ])[(RANDOM() * 9 + 1)::int],
    (ARRAY['view','click','add_cart','remove_cart','purchase','search','login','logout'])[
        (RANDOM() * 7 + 1)::int],
    ('192.168.' || (RANDOM()*254+1)::int || '.' || (RANDOM()*254+1)::int)::inet,
    NOW() - (RANDOM() * 90)::int * INTERVAL '1 day'
        - (RANDOM() * 23)::int * INTERVAL '1 hour'
        - (RANDOM() * 59)::int * INTERVAL '1 minute'
FROM generate_series(1, 50000) gs;

-- ── Promoções com Período (GiST demo) ────────────────────────
INSERT INTO promocoes (nome, desconto_pct, periodo, categorias_ids) VALUES
('Black Friday 2024',         25.00,
 '[2024-11-29 00:00:00+00, 2024-11-30 23:59:59+00]',  ARRAY[1,2,3,4,5,6]),
('Cyber Monday 2024',         15.00,
 '[2024-12-02 00:00:00+00, 2024-12-02 23:59:59+00]',  ARRAY[1,2,6]),
('Natal 2024',                10.00,
 '[2024-12-15 00:00:00+00, 2024-12-25 23:59:59+00]',  ARRAY[1,2,3,4]),
('Ano Novo 2025',             12.00,
 '[2024-12-26 00:00:00+00, 2025-01-05 23:59:59+00]',  ARRAY[1,2,3]),
('Liquidação Janeiro 2025',   20.00,
 '[2025-01-10 00:00:00+00, 2025-01-31 23:59:59+00]',  ARRAY[1,3,5]),
('Dia dos Namorados 2025',    8.00,
 '[2025-06-07 00:00:00+00, 2025-06-12 23:59:59+00]',  ARRAY[2,4]),
('Aniversário da Loja',       18.00,
 '[2025-08-01 00:00:00+00, 2025-08-07 23:59:59+00]',  ARRAY[1,2,3,4,5,6,7,8]),
('Volta às Aulas 2025',       10.00,
 '[2025-01-20 00:00:00+00, 2025-02-10 23:59:59+00]',  ARRAY[1,4]),
('Promoção Notebooks Set/25', 15.00,
 '[2025-09-01 00:00:00+00, 2025-09-30 23:59:59+00]',  ARRAY[1]),
('Semana do Consumidor 2025', 22.00,
 '[2025-03-10 00:00:00+00, 2025-03-15 23:59:59+00]',  ARRAY[1,2,3,4,5,6]);

-- ============================================================
-- VIEWS ÚTEIS PARA O VÍDEO
-- ============================================================

-- Produtos com contagem de avaliações
CREATE OR REPLACE VIEW vw_produtos_resumo AS
SELECT
    p.id,
    p.sku,
    p.nome,
    c.nome          AS categoria,
    p.preco,
    p.estoque,
    p.tags,
    COUNT(a.id)     AS total_avaliacoes,
    ROUND(AVG(a.nota), 2) AS nota_media
FROM produtos p
JOIN categorias c ON c.id = p.categoria_id
LEFT JOIN avaliacoes a ON a.produto_id = p.id
GROUP BY p.id, p.sku, p.nome, c.nome, p.preco, p.estoque, p.tags;

-- Ranking de pedidos por cliente
CREATE OR REPLACE VIEW vw_clientes_resumo AS
SELECT
    c.id,
    c.nome,
    c.email,
    c.cidade,
    c.estado,
    COUNT(p.id)         AS total_pedidos,
    SUM(p.total)        AS valor_total,
    MAX(p.criado_em)    AS ultimo_pedido
FROM clientes c
LEFT JOIN pedidos p ON p.cliente_id = c.id
GROUP BY c.id, c.nome, c.email, c.cidade, c.estado;

-- ============================================================
-- VERIFICAÇÃO FINAL
-- ============================================================
SELECT
    'categorias'        AS tabela, COUNT(*) AS registros FROM categorias
UNION ALL SELECT 'produtos',      COUNT(*) FROM produtos
UNION ALL SELECT 'clientes',      COUNT(*) FROM clientes
UNION ALL SELECT 'pedidos',       COUNT(*) FROM pedidos
UNION ALL SELECT 'pedido_itens',  COUNT(*) FROM pedido_itens
UNION ALL SELECT 'avaliacoes',    COUNT(*) FROM avaliacoes
UNION ALL SELECT 'logs_acesso',   COUNT(*) FROM logs_acesso
UNION ALL SELECT 'promocoes',     COUNT(*) FROM promocoes
ORDER BY tabela;
