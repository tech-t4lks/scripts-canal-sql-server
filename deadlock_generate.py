# deadlock_generate
# ============================================================
# Simula uma aplicação com transações concorrentes que geram
# deadlocks reais no SQL Server.
#
# Como funciona:
#   - Thread A: atualiza Produto 1, depois tenta Produto 2
#   - Thread B: atualiza Produto 2, depois tenta Produto 1
#   - Resultado: deadlock clássico — SQL Server mata uma das threads ( a de menor custo)
#
# Banco: AdventureWorks2022
# Pré-requisito: pip install pyodbc
# Uso: python deadlock_generate
# ============================================================
from db_conn import open_conn
import threading
import time
import random
import pyodbc
import logging
from datetime import datetime


# Contadores globais
lock_stats       = threading.Lock()
total_deadlocks  = 0
total_sucesso    = 0
total_execs      = 0


# configurando logging para mostrar detalhes dos deadlocks
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(threadName)-12s] %(message)s",
    handlers=[
        logging.StreamHandler(),
    ],
)


# criado a thread A 
def transacao_A(exec: int):
    global total_deadlocks, total_sucesso, total_execs

    conn = open_conn()
    cursor = conn.cursor()

    try:
                # Passo 1: bloqueia Produto 1 com UPDATE
        cursor.execute("""
            UPDATE Production.Product
            SET    ModifiedDate = GETDATE()
            WHERE  ProductID    = 1
        """)

        # pausa para a thread B bloquear o Produto 2
        time.sleep(0.4)

        # passo 2: tenta bloquear Produto 2, mas pode gerar deadlock
        cursor.execute("""
            UPDATE Production.Product
            SET    ModifiedDate = GETDATE()
            WHERE  ProductID    = 2
        """)

        conn.commit()
        with lock_stats:
            total_sucesso += 1

    except pyodbc.Error as e:
        conn.rollback()
        msg = str(e)
        if "1205" in msg or "deadlock" in msg.lower():
            with lock_stats:
                total_deadlocks += 1
            logging.warning(f"[Ciclo {exec}] TxA: DEADLOCK detectado — rollback executado")
        else:
            logging.error(f"[Ciclo {exec}] TxA: erro inesperado — {msg[:120]}")
    finally:
        cursor.close()
        conn.close()


# ── Transação B ───────────────────────────────────────────────
# Ordem de lock: Produto 2 → Produto 1  (inverso de A = deadlock garantido)
def transacao_B(exec: int):
    global total_deadlocks, total_sucesso
    conn = open_conn()
    cursor  = conn.cursor()
    try:
        # Passo 1: bloqueia Produto 2 com UPDATE
        cursor.execute("""
            UPDATE Production.Product
            SET    ModifiedDate = GETDATE()
            WHERE  ProductID    = 2
        """)
        logging.info(f"[Ciclo {exec}] TxB: lock em Produto 2 adquirido")

        # Pausa proposital
        time.sleep(0.3)

        # Passo 2: tenta bloquear Produto 1 (já está com Thread A → DEADLOCK)
        cursor.execute("""
            UPDATE Production.Product
            SET    ModifiedDate = GETDATE()
            WHERE  ProductID    = 1
        """)
        logging.info(f"[Ciclo {exec}] TxB: lock em Produto 1 adquirido — commit")

        conn.commit()
        with lock_stats:
            total_sucesso += 1

    except pyodbc.Error as e:
        conn.rollback()
        msg = str(e)
        if "1205" in msg or "deadlock" in msg.lower():
            with lock_stats:
                total_deadlocks += 1
            logging.warning(f"[Ciclo {exec}] TxB: DEADLOCK detectado — rollback executado")
        else:
            logging.error(f"[Ciclo {exec}] TxB: erro inesperado — {msg[:120]}")
    finally:
        cursor.close()
        conn.close()


# ── Transação C — simula workload normal ─────────────────────
# Queries de leitura que aumentam a pressão de locks
def transacao_leitura(ciclo: int):
    conn = open_conn()
    cursor  = conn.cursor()
    try:
        cursor.execute("""
            SELECT TOP 50
                p.ProductID, p.Name, p.ListPrice,
                SUM(sod.OrderQty)  AS TotalVendido
            FROM Production.Product p
            JOIN Sales.SalesOrderDetail sod ON p.ProductID = sod.ProductID
            WHERE p.ProductID IN (1, 2, 3, 4, 5)
            GROUP BY p.ProductID, p.Name, p.ListPrice
            ORDER BY TotalVendido DESC
        """)
        cursor.fetchall()
        conn.commit()
    except Exception:
        conn.rollback()
    finally:
        cursor.close()
        conn.close()


# ── Ciclo principal ───────────────────────────────────────────
def ciclo_deadlock(num: int):
    global total_execs
    with lock_stats:
        total_execs += 1

    # Dispara A e B simultaneamente — deadlock quase garantido
    ta = threading.Thread(target=transacao_A, args=(num,), name=f"TxA-{num:03d}")
    tb = threading.Thread(target=transacao_B, args=(num,), name=f"TxB-{num:03d}")
    tc = threading.Thread(target=transacao_leitura, args=(num,), name=f"TxC-{num:03d}")

    ta.start()
    tb.start()
    tc.start()

    ta.join()
    tb.join()
    tc.join()


def main():
    logging.info("=" * 65)
    logging.info("GERADOR DE DEADLOCK — Tech T4lks")
    logging.info("Banco     : AdventureWorks2022")
    logging.info("Estratégia: Lock Produto1→2 vs Produto2→1 (deadlock clássico)")
    logging.info("Pressione Ctrl+C para encerrar")
    logging.info("=" * 65)

    ciclo = 0
    try:
        while True:
            ciclo += 1
            logging.info(f"\n{'─'*55}")
            logging.info(f"Iniciando ciclo #{ciclo:03d}...")
            ciclo_deadlock(ciclo)

            # Relatório a cada 5 ciclos
            if ciclo % 5 == 0:
                logging.info(
                    f"\n{'═'*55}\n"
                    f"  RELATÓRIO  |  Ciclos: {total_execs}  "
                    f"|  Deadlocks: {total_deadlocks}  "
                    f"|  Sucessos: {total_sucesso}\n"
                    f"{'═'*55}"
                )

            espera = random.uniform(2, 5)
            logging.info(f"Aguardando {espera:.1f}s...")
            time.sleep(espera)

    except KeyboardInterrupt:
        logging.info(
            f"\nEncerrado.\n"
            f"  Total de ciclos   : {total_execs}\n"
            f"  Total de deadlocks: {total_deadlocks}\n"
            f"  Total de sucessos : {total_sucesso}"
        )


if __name__ == "__main__":
    main()

