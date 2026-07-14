#!/usr/bin/env python3
"""
visualizador_deadlock.py
============================================================
Cole o XML do deadlock (da coluna deadlock_graph da tabela)
e o script abre um diagrama visual no navegador.

Uso:
    python visualizador_deadlock.py

Depois cole o XML quando solicitado, ou passe um arquivo:
    python visualizador_deadlock.py deadlock.xml

Dependências: nenhuma além da stdlib do Python
============================================================
"""

import sys
import xml.etree.ElementTree as ET
import webbrowser
import tempfile
import os
import re
from datetime import datetime


# ── Parser do XML de deadlock ─────────────────────────────────

def parse_deadlock_xml(xml_str: str) -> dict:
    """
    Extrai informações estruturadas do XML de deadlock.
    Suporta os formatos:
      - <deadlock-graph><deadlock>...</deadlock></deadlock-graph>
      - <deadlock>...</deadlock>
      - <event name="xml_deadlock_report">...<data name="xml_report">...</event>
    """
    xml_str = xml_str.strip()

    # Normaliza: tenta extrair o nó <deadlock> de qualquer wrapper
    if "<deadlock-graph>" in xml_str:
        m = re.search(r"<deadlock>.*?</deadlock>", xml_str, re.DOTALL)
        if m:
            xml_str = m.group(0)
    elif 'name="xml_report"' in xml_str or 'name="xml_deadlock_report"' in xml_str:
        m = re.search(r"<deadlock>.*?</deadlock>", xml_str, re.DOTALL)
        if m:
            xml_str = m.group(0)

    try:
        root = ET.fromstring(xml_str)
    except ET.ParseError as e:
        return {"erro": f"XML inválido: {e}"}

    # Garante que estamos no nó <deadlock>
    if root.tag != "deadlock":
        deadlock_node = root.find(".//deadlock")
        if deadlock_node is None:
            return {"erro": "Nó <deadlock> não encontrado no XML."}
        root = deadlock_node

    result = {
        "vitima_id":    None,
        "processos":    [],
        "recursos":     [],
        "erro":         None,
    }

    # Vítima
    victim_el = root.find("victim-list/victimProcess")
    if victim_el is not None:
        result["vitima_id"] = victim_el.get("id", "")

    # Processos
    for proc in root.findall("process-list/process"):
        pid      = proc.get("id", "")
        inputbuf = proc.findtext("inputbuf", "").strip()
        result["processos"].append({
            "id":          pid,
            "spid":        proc.get("spid", "?"),
            "login":       proc.get("loginname", "?"),
            "host":        proc.get("hostname", "?"),
            "app":         proc.get("clientapp", "?"),
            "database":    proc.get("currentdbname", "?"),
            "lock_mode":   proc.get("lockMode", "?"),
            "wait":        proc.get("waitresource", ""),
            "status":      proc.get("status", ""),
            "query":       inputbuf[:500] if inputbuf else "(sem query)",
            "e_vitima":    pid == result["vitima_id"],
        })

    # Recursos
    for res in root.findall("resource-list/*"):
        owners  = [o.get("id","") for o in res.findall("owner-list/owner")]
        waiters = [w.get("id","") for w in res.findall("waiter-list/waiter")]
        result["recursos"].append({
            "tipo":      res.tag,
            "objeto":    res.get("objectname", res.get("objectname", "?")),
            "indice":    res.get("indexname", ""),
            "modo":      res.get("mode", "?"),
            "dbid":      res.get("dbid", ""),
            "owners":    owners,
            "waiters":   waiters,
        })

    return result


# ── Gerador do HTML visual ────────────────────────────────────

def gerar_html(data: dict, xml_original: str) -> str:

    if data.get("erro"):
        return f"""<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;padding:40px;background:#f5f5f0;color:#c00">
        <h2>Erro ao processar o XML</h2><pre>{data['erro']}</pre></body></html>"""

    processos  = data["processos"]
    recursos   = data["recursos"]
    vitima_id  = data["vitima_id"]
    agora      = datetime.now().strftime("%d/%m/%Y %H:%M:%S")

    # ── Cards dos processos ───────────────────────────────────
    cards_html = ""
    for p in processos:
        is_vitima  = p["e_vitima"]
        border_clr = "#cc0000" if is_vitima else "#007a5e"
        badge_bg   = "#cc0000" if is_vitima else "#007a5e"
        badge_lbl  = "VITIMA"  if is_vitima else "SOBREVIVENTE"

        query_esc = (p["query"]
                     .replace("&","&amp;").replace("<","&lt;").replace(">","&gt;"))

        cards_html += f"""
        <div class="proc-card" style="border-left:4px solid {border_clr}">
            <div class="proc-header">
                <span class="proc-spid">Session {p['spid']}</span>
                <span class="badge" style="background:{badge_bg}">{badge_lbl}</span>
            </div>
            <table class="info-table">
                <tr><td class="lbl">Login</td><td>{p['login']}</td></tr>
                <tr><td class="lbl">Host</td><td>{p['host']}</td></tr>
                <tr><td class="lbl">Aplicação</td><td>{p['app']}</td></tr>
                <tr><td class="lbl">Database</td><td>{p['database']}</td></tr>
                <tr><td class="lbl">Lock Mode</td><td><b class="lm-{p['lock_mode'].lower()}">{p['lock_mode']}</b></td></tr>
                <tr><td class="lbl">Status</td><td>{p['status']}</td></tr>
                <tr><td class="lbl">Aguardando</td><td class="small">{p['wait']}</td></tr>
            </table>
            <div class="query-label">Query</div>
            <pre class="query-code">{query_esc}</pre>
        </div>"""

    # ── Tabela de recursos ────────────────────────────────────
    recursos_rows = ""
    for r in recursos:
        def resolve(ids):
            nomes = []
            for pid in ids:
                for p in processos:
                    if p["id"] == pid:
                        tag = " (vitima)" if p["e_vitima"] else " (sobrev.)"
                        nomes.append(f"Session {p['spid']}{tag}")
            return ", ".join(nomes) if nomes else "—"

        recursos_rows += f"""
        <tr>
            <td><code>{r['tipo']}</code></td>
            <td>{r['objeto']}</td>
            <td>{r['indice']}</td>
            <td><b class="lm-{r['modo'].lower()}">{r['modo']}</b></td>
            <td>{resolve(r['owners'])}</td>
            <td>{resolve(r['waiters'])}</td>
        </tr>"""

    # ── Diagrama de setas ─────────────────────────────────────
    diagrama_html = ""
    if len(processos) == 2:
        p0, p1   = processos[0], processos[1]
        l0       = "VITIMA"       if p0["e_vitima"] else "SOBREVIVENTE"
        l1       = "VITIMA"       if p1["e_vitima"] else "SOBREVIVENTE"
        c0       = "#cc0000"      if p0["e_vitima"] else "#007a5e"
        c1       = "#cc0000"      if p1["e_vitima"] else "#007a5e"
        obj_nome = recursos[0]["objeto"] if recursos else "recurso disputado"
        idx_nome = recursos[0]["indice"] if recursos else ""

        diagrama_html = f"""
        <div class="diagrama">
            <div class="dia-node" style="border:2px solid {c0}">
                <div class="dia-spid" style="color:{c0}">Session {p0['spid']}</div>
                <div class="dia-role" style="color:{c0}">{l0}</div>
                <div class="dia-info">{p0['login']} @ {p0['host']}</div>
            </div>

            <div class="dia-mid">
                <div class="dia-obj">
                    <b>{obj_nome}</b>
                    <span class="dia-idx">{idx_nome}</span>
                </div>
                <svg width="200" height="70" viewBox="0 0 200 70">
                    <defs>
                        <marker id="a1" markerWidth="8" markerHeight="6"
                                refX="7" refY="3" orient="auto">
                            <polygon points="0 0, 8 3, 0 6" fill="#888"/>
                        </marker>
                        <marker id="a2" markerWidth="8" markerHeight="6"
                                refX="7" refY="3" orient="auto">
                            <polygon points="0 0, 8 3, 0 6" fill="#888"/>
                        </marker>
                    </defs>
                    <path d="M 5,18 Q 100,2 195,18"
                          stroke="#888" stroke-width="1.5" fill="none"
                          marker-end="url(#a1)" stroke-dasharray="5,3"/>
                    <path d="M 195,52 Q 100,68 5,52"
                          stroke="#888" stroke-width="1.5" fill="none"
                          marker-end="url(#a2)" stroke-dasharray="5,3"/>
                    <text x="100" y="13" text-anchor="middle"
                          fill="#555" font-size="10" font-family="Arial">quer lock →</text>
                    <text x="100" y="65" text-anchor="middle"
                          fill="#555" font-size="10" font-family="Arial">← quer lock</text>
                </svg>
                <div class="dia-dead">DEADLOCK</div>
            </div>

            <div class="dia-node" style="border:2px solid {c1}">
                <div class="dia-spid" style="color:{c1}">Session {p1['spid']}</div>
                <div class="dia-role" style="color:{c1}">{l1}</div>
                <div class="dia-info">{p1['login']} @ {p1['host']}</div>
            </div>
        </div>"""

    # ── XML colapsável ────────────────────────────────────────
    xml_esc = (xml_original[:8000]
               .replace("&","&amp;").replace("<","&lt;").replace(">","&gt;"))

    # ── HTML final ────────────────────────────────────────────
    return f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Deadlock Visualizer</title>
<style>
* {{ box-sizing:border-box; margin:0; padding:0; }}

body {{
    font-family: Arial, sans-serif;
    font-size: 13px;
    background: #f5f5f0;
    color: #222;
    line-height: 1.5;
}}

/* ── Header ── */
header {{
    background: #fff;
    border-bottom: 2px solid #ccc;
    padding: 14px 28px;
    display: flex;
    align-items: center;
    justify-content: space-between;
}}
header h1 {{ font-size:16px; font-weight:bold; color:#222; }}
header p  {{ font-size:11px; color:#777; margin-top:2px; }}
.ts        {{ font-size:11px; color:#777; }}

/* ── Layout ── */
main    {{ padding:24px 28px; max-width:1200px; margin:0 auto; }}
section {{ margin-bottom:32px; }}

h2 {{
    font-size:12px;
    font-weight:bold;
    text-transform:uppercase;
    letter-spacing:.06em;
    color:#555;
    border-bottom:1px solid #ccc;
    padding-bottom:6px;
    margin-bottom:14px;
}}

/* ── Diagrama ── */
.diagrama {{
    display: flex;
    align-items: center;
    gap: 0;
    background: #fff;
    border: 1px solid #ccc;
    padding: 20px;
    justify-content: center;
    flex-wrap: wrap;
    gap: 12px;
}}
.dia-node {{
    background: #fafafa;
    padding: 14px 18px;
    min-width: 170px;
    text-align: center;
}}
.dia-spid {{ font-size:17px; font-weight:bold; font-family:monospace; }}
.dia-role {{ font-size:11px; font-weight:bold; margin-top:3px; }}
.dia-info {{ font-size:11px; color:#666; margin-top:5px; }}
.dia-mid  {{ display:flex; flex-direction:column; align-items:center; gap:4px; padding:0 12px; }}
.dia-obj  {{ text-align:center; font-size:12px; }}
.dia-idx  {{ display:block; font-size:10px; color:#777; font-family:monospace; }}
.dia-dead {{
    background:#cc0000; color:#fff;
    font-size:11px; font-weight:bold;
    padding:3px 10px; margin-top:2px;
}}

/* ── Cards dos processos ── */
.proc-grid {{
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(360px,1fr));
    gap: 16px;
}}
.proc-card {{
    background: #fff;
    border: 1px solid #ccc;
    padding: 0;
}}
.proc-header {{
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    background: #f0f0ec;
    border-bottom: 1px solid #ccc;
}}
.proc-spid {{ font-size:15px; font-weight:bold; font-family:monospace; }}
.badge {{
    font-size:10px; font-weight:bold;
    color:#fff; padding:2px 8px;
}}
.info-table {{
    width:100%; border-collapse:collapse;
    margin:0; font-size:12px;
}}
.info-table tr {{ border-bottom:1px solid #eee; }}
.info-table tr:last-child {{ border-bottom:none; }}
.info-table td {{ padding:5px 14px; vertical-align:top; }}
.lbl {{
    color:#666; width:90px; white-space:nowrap;
    font-size:11px;
}}
.small {{ font-size:10px; font-family:monospace; }}
.query-label {{
    font-size:10px; font-weight:bold; color:#555;
    padding:6px 14px 2px 14px;
    text-transform:uppercase; letter-spacing:.04em;
}}
.query-code {{
    font-family: monospace;
    font-size: 11px;
    background: #f8f8f4;
    border-top: 1px solid #e8e8e0;
    padding: 8px 14px;
    white-space: pre-wrap;
    word-break: break-all;
    max-height: 140px;
    overflow-y: auto;
    color: #333;
}}

/* ── Lock modes ── */
.lm-x {{ color:#cc0000; }}
.lm-s {{ color:#007a5e; }}
.lm-u {{ color:#b05a00; }}

/* ── Tabela de recursos ── */
.table-wrap {{ overflow-x:auto; border:1px solid #ccc; }}
table   {{ width:100%; border-collapse:collapse; font-size:12px; background:#fff; }}
thead tr {{ background:#e8e8e4; }}
th      {{
    padding:8px 12px; text-align:left;
    font-size:11px; font-weight:bold;
    text-transform:uppercase; color:#444;
    border-bottom:2px solid #ccc;
}}
tbody tr {{ border-top:1px solid #eee; }}
tbody tr:hover {{ background:#fafaf6; }}
td      {{ padding:7px 12px; vertical-align:top; }}
td code {{ font-family:monospace; font-size:11px; color:#555; }}

/* ── XML colapsável ── */
details {{
    background:#fff;
    border:1px solid #ccc;
}}
summary {{
    padding:10px 14px;
    cursor:pointer;
    font-size:12px;
    font-weight:bold;
    color:#555;
    user-select:none;
    list-style:none;
}}
summary:hover {{ color:#222; }}
.xml-pre {{
    margin:0;
    padding:12px 14px;
    font-family:monospace;
    font-size:11px;
    color:#444;
    white-space:pre-wrap;
    word-break:break-all;
    max-height:280px;
    overflow-y:auto;
    border-top:1px solid #ddd;
    background:#f8f8f4;
}}

footer {{
    text-align:center;
    padding:16px;
    border-top:1px solid #ccc;
    color:#888;
    font-size:11px;
    margin-top:16px;
    background:#fff;
}}
</style>
</head>
<body>

<header>
  <div>
    <h1>Deadlock Visualizer — Tech T4lks</h1>
    <p>Diagrama do XML de deadlock — SQL Server</p>
  </div>
  <div class="ts">Gerado em {agora}</div>
</header>

<main>

  <section>
    <h2>Diagrama do Ciclo</h2>
    {diagrama_html if diagrama_html else '<p style="color:#888">Diagrama não disponível.</p>'}
  </section>

  <section>
    <h2>Processos Envolvidos ({len(processos)})</h2>
    <div class="proc-grid">
      {cards_html}
    </div>
  </section>

  <section>
    <h2>Recursos em Disputa ({len(recursos)})</h2>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Tipo</th><th>Objeto</th><th>Índice</th>
            <th>Modo</th><th>Dono (tem o lock)</th><th>Esperando (quer o lock)</th>
          </tr>
        </thead>
        <tbody>
          {recursos_rows if recursos_rows else
           '<tr><td colspan="6" style="text-align:center;color:#888;padding:16px">Sem recursos encontrados.</td></tr>'}
        </tbody>
      </table>
    </div>
  </section>

  <section>
    <details>
      <summary>XML Original (clique para expandir)</summary>
      <pre class="xml-pre">{xml_esc}</pre>
    </details>
  </section>

</main>

<footer>
  Tech T4lks &nbsp;·&nbsp; Deadlock Visualizer &nbsp;·&nbsp; {agora}
</footer>

</body>
</html>"""


# ── Entrada do XML ────────────────────────────────────────────

def ler_xml() -> str:
    """Lê o XML do arquivo passado como argumento ou pelo stdin."""

    # Se passou um arquivo como argumento
    if len(sys.argv) > 1:
        path = sys.argv[1]
        if not os.path.exists(path):
            print(f"❌ Arquivo não encontrado: {path}")
            sys.exit(1)
        with open(path, "r", encoding="utf-8") as f:
            return f.read()

    # Modo interativo: cola o XML no terminal
    print("=" * 60)
    print("  Tech T4lks · Deadlock Visualizer")
    print("=" * 60)
    print()
    print("Cole o XML do deadlock abaixo.")
    print("(Quando terminar, pressione Enter duas vezes)")
    print()

    linhas = []
    try:
        while True:
            linha = input()
            if linha == "" and linhas and linhas[-1] == "":
                break
            linhas.append(linha)
    except EOFError:
        pass

    return "\n".join(linhas).strip()


# ── Main ──────────────────────────────────────────────────────

def main():
    xml_str = ler_xml()

    if not xml_str:
        print("❌ Nenhum XML fornecido.")
        sys.exit(1)

    print("\n⏳ Processando XML...")
    data = parse_deadlock_xml(xml_str)

    if data.get("erro"):
        print(f"❌ Erro: {data['erro']}")
        sys.exit(1)

    vitima = next((p for p in data["processos"] if p["e_vitima"]), None)
    sobrev = next((p for p in data["processos"] if not p["e_vitima"]), None)

    print(f"✅ Deadlock processado:")
    if vitima:
        print(f"   💀 Vítima      : Session {vitima['spid']} — {vitima['login']} @ {vitima['host']}")
    if sobrev:
        print(f"   ✅ Sobrevivente: Session {sobrev['spid']} — {sobrev['login']} @ {sobrev['host']}")
    if data["recursos"]:
        print(f"   🔒 Recurso     : {data['recursos'][0]['objeto']}")

    html = gerar_html(data, xml_str)

    # Salva em arquivo temporário e abre no navegador
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".html", delete=False,
        encoding="utf-8", prefix="deadlock_viz_"
    )
    tmp.write(html)
    tmp.close()

    print(f"\n🌐 Abrindo no navegador: {tmp.name}")
    webbrowser.open(f"file://{tmp.name}")
    print("✅ Pronto!")


if __name__ == "__main__":
    main()
