#!/usr/bin/env python3
# Offline advanced analytics dashboard for Nixo MT5 CSV exports (stdlib only).
from __future__ import annotations
import argparse, csv, html, json, math, os, statistics, sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


def num(v, default=0.0):
    try: return float(v)
    except (TypeError, ValueError): return default

def read_rows(path: Path):
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            with path.open("r", newline="", encoding=enc) as f:
                return list(csv.DictReader(f))
        except UnicodeDecodeError:
            continue
    raise RuntimeError(f"Cannot decode {path}")

def parse_time(value):
    if not value: return None
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y.%m.%d %H:%M", "%Y-%m-%d %H:%M"):
        try: return datetime.strptime(value, fmt)
        except ValueError: pass
    return None

def load_sources(csv_path: Path):
    path=csv_path.parent/"source_registry.csv"
    result={}
    if path.exists():
        try:
            for row in read_rows(path):
                if len(row)>=2:
                    result[str(row.get("0", row.get("source_hash", "")) or "")] = str(row.get("1", row.get("source_id", "")) or "")
        except Exception: pass
        # Registry is a headerless 2-column file; handle it directly.
        try:
            with path.open("r",newline="",encoding="cp1252") as f:
                for r in csv.reader(f):
                    if len(r)>=2: result[str(r[0])]=r[1]
        except Exception: pass
    return result

STRATEGIES={0:"RTM + LFT",1:"Dreams Liquidity",2:"Safe Breakout",3:"EMA + RSI + ADX + MTF",4:"VWAP Retest",5:"Supertrend",6:"ATR Momentum",7:"RTM Scalp",8:"Liquidity Scalp",9:"Micro Pullback",10:"Squeeze",11:"RSI-3 Dip",12:"EMA Pullback",13:"Ensemble",14:"Tick Turbo",15:"UltraHFT",16:"Nyao Straddle",17:"UltraNyao Hybrid",18:"Public Telegram",19:"Copy Site"}

def make_report(csv_path: Path, out_path: Path):
    rows=read_rows(csv_path)
    source_map=load_sources(csv_path)
    deals=defaultdict(list); opens=[]
    for r in rows:
        typ=(r.get("record_type") or "").upper()
        if typ=="OPEN": opens.append(r); continue
        if typ!="DEAL": continue
        pid=r.get("position_id") or ""
        if not pid: continue
        deals[pid].append(r)
    trades=[]
    for pid, ds in deals.items():
        ds.sort(key=lambda x: parse_time(x.get("time","")) or datetime.min)
        entry=[d for d in ds if "IN" in (d.get("entry") or "")]
        exits=[d for d in ds if (d.get("entry") or "").startswith("DEAL_ENTRY_OUT") or (d.get("entry") or "")=="DEAL_ENTRY_INOUT"]
        if not entry: continue
        first=entry[0]
        last=max(ds,key=lambda x: parse_time(x.get("time","")) or datetime.min)
        net=sum(num(d.get("profit"))+num(d.get("commission"))+num(d.get("swap"))+num(d.get("fee")) for d in ds)
        # If an INOUT reversal is used, include its profit/fees as realized too.
        if not exits and all((d.get("entry") or "")=="DEAL_ENTRY_IN" for d in ds): continue
        open_t=parse_time(first.get("time","")); close_t=parse_time(last.get("time",""))
        duration=((close_t-open_t).total_seconds()/60) if open_t and close_t else 0
        risk=num(first.get("risk_money")) or num(last.get("risk_money"))
        rr=num(first.get("planned_rr")) or num(last.get("planned_rr"))
        rmultiple=(net/risk) if risk>0 else 0.0
        mode=first.get("mode") or "UNKNOWN"
        strategy_id=first.get("strategy_id") or "-1"
        source_hash=first.get("source_hash") or "0"
        if mode=="EXTERNAL SIGNALS": group=f"External · {source_map.get(source_hash, source_hash if source_hash!='0' else 'Unknown source')}"
        elif mode=="STRATEGY":
            label=STRATEGIES.get(int(strategy_id),strategy_id) if str(strategy_id).lstrip('-').isdigit() else strategy_id
            group=f"Strategy · {label}"
        else: group="Manual"
        vol=sum(num(d.get("volume")) for d in entry)
        avg_entry=(sum(num(d.get("volume"))*num(d.get("price")) for d in entry)/vol) if vol else 0
        exitvol=sum(num(d.get("volume")) for d in exits)
        avg_exit=(sum(num(d.get("volume"))*num(d.get("price")) for d in exits)/exitvol) if exitvol else 0
        trades.append({"pid":pid,"symbol":first.get("symbol",""),"mode":mode,"group":group,"strategy_id":strategy_id,
          "source":source_map.get(source_hash,source_hash if source_hash!="0" else "—"),"side":first.get("deal_type",""),
          "open":first.get("time",""),"close":last.get("time",""),"duration":duration,"volume":vol,
          "avg_entry":avg_entry,"avg_exit":avg_exit,"initial_sl":num(first.get("initial_sl")),"risk":risk,
          "planned_rr":rr,"net":net,"r":rmultiple,"deals":len(ds)})
    trades.sort(key=lambda t: parse_time(t["close"]) or datetime.min)
    wins=[t for t in trades if t["net"]>0]; losses=[t for t in trades if t["net"]<0]
    net=sum(t["net"] for t in trades); gp=sum(t["net"] for t in wins); gl=-sum(t["net"] for t in losses)
    pf=gp/gl if gl else (float("inf") if gp else 0)
    wr=100*len(wins)/len(trades) if trades else 0
    expectancy=net/len(trades) if trades else 0
    avg_r=statistics.mean(t["r"] for t in trades if t["risk"]>0) if any(t["risk"]>0 for t in trades) else 0
    # Position-level equity and max drawdown using realized net, chronological.
    equity=peak=dd=0.0; curve=[]
    for t in trades:
        equity+=t["net"]; peak=max(peak,equity); dd=max(dd,peak-equity); curve.append({"label":t["close"],"value":round(equity,2)})
    # Longest consecutive W/L streaks.
    streak_w=streak_l=max_w=max_l=0
    for t in trades:
        if t["net"]>0: streak_w+=1; streak_l=0
        elif t["net"]<0: streak_l+=1; streak_w=0
        else: streak_w=streak_l=0
        max_w=max(max_w,streak_w); max_l=max(max_l,streak_l)
    groups=defaultdict(list)
    for t in trades: groups[t["group"]].append(t)
    summaries=[]
    for name, arr in sorted(groups.items(), key=lambda kv:sum(x["net"] for x in kv[1]), reverse=True):
        n=len(arr); w=sum(x["net"]>0 for x in arr); p=sum(x["net"] for x in arr); pos=sum(x["net"] for x in arr if x["net"]>0); neg=-sum(x["net"] for x in arr if x["net"]<0)
        summaries.append({"name":name,"trades":n,"win_rate":100*w/n if n else 0,"net":p,"pf":pos/neg if neg else (float("inf") if pos else 0),"avg_r":statistics.mean(x["r"] for x in arr if x["risk"]>0) if any(x["risk"]>0 for x in arr) else 0,"avg_volume":statistics.mean(x["volume"] for x in arr) if n else 0,"avg_duration":statistics.mean(x["duration"] for x in arr) if n else 0})
    payload={"file":csv_path.name,"trades":trades,"opens":opens,"groups":summaries,"curve":curve,
      "kpi":{"closed":len(trades),"win_rate":wr,"net":net,"profit_factor":("∞" if math.isinf(pf) else pf),"expectancy":expectancy,"avg_r":avg_r,"max_dd":dd,"avg_win":statistics.mean(t["net"] for t in wins) if wins else 0,"avg_loss":statistics.mean(t["net"] for t in losses) if losses else 0,"avg_hold":statistics.mean(t["duration"] for t in trades) if trades else 0,"max_win_streak":max_w,"max_loss_streak":max_l,"open":len(opens)}}
    data=json.dumps(payload,ensure_ascii=False).replace("</","<\\/")
    page=HTML.replace("__DATA__",data).replace("__TITLE__",html.escape(csv_path.name))
    out_path.write_text(page,encoding="utf-8")
    return payload

HTML=r'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Nixo Advanced Analytics</title><style>
:root{color-scheme:dark;--bg:#0a1020;--panel:#121c30;--panel2:#18263e;--line:#2d3c56;--text:#e8eef8;--muted:#9aa9bf;--gold:#e6bd70;--green:#49d5a0;--red:#ff7778;--blue:#80cfff}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 10% 0%,#182c43 0,#0a1020 42%);color:var(--text);font:14px Segoe UI,Arial,sans-serif}.wrap{max-width:1500px;margin:auto;padding:28px}.top{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;margin-bottom:22px}.brand{font-size:26px;font-weight:750;letter-spacing:.04em}.brand span{color:var(--gold)}.sub{color:var(--muted);margin-top:5px}.file{color:var(--muted);font-size:12px}.grid{display:grid;grid-template-columns:repeat(6,minmax(130px,1fr));gap:12px}.card,.panel{background:linear-gradient(145deg,rgba(24,38,62,.96),rgba(15,24,41,.96));border:1px solid var(--line);border-radius:16px;padding:16px;box-shadow:0 14px 30px #0003}.klabel{font-size:11px;color:var(--muted);letter-spacing:.09em;text-transform:uppercase}.kval{font-size:23px;font-weight:700;margin-top:10px}.positive{color:var(--green)}.negative{color:var(--red)}.layout{display:grid;grid-template-columns:1.35fr 1fr;gap:14px;margin-top:14px}.panel h2{font-size:14px;margin:0 0 14px;color:#f2d8a5;letter-spacing:.04em}.chart{width:100%;height:260px;display:block}.barrow{display:grid;grid-template-columns:minmax(130px,1.1fr) 2fr 80px;gap:10px;align-items:center;margin:14px 0}.track{height:12px;border-radius:99px;background:#0b1425;overflow:hidden}.fill{height:100%;border-radius:99px}.barval{text-align:right;font-variant-numeric:tabular-nums}.filters{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}.filters input,.filters select{background:#0c1729;color:var(--text);border:1px solid var(--line);border-radius:9px;padding:9px}.tablewrap{overflow:auto;border-radius:12px;border:1px solid var(--line)}table{width:100%;border-collapse:collapse;white-space:nowrap;font-variant-numeric:tabular-nums}th,td{padding:10px 12px;border-bottom:1px solid #26364e;text-align:right}th{background:#17253a;color:#b6c5da;font-size:11px;text-transform:uppercase;position:sticky;top:0}td:first-child,th:first-child{text-align:left}.muted{color:var(--muted)}.pill{padding:4px 7px;border:1px solid var(--line);border-radius:20px;color:#c8d5e6;font-size:11px}.empty{padding:30px;color:var(--muted);text-align:center}.wide{margin-top:14px}.legend{display:flex;gap:18px;color:var(--muted);font-size:12px;margin-top:8px}@media(max-width:1100px){.grid{grid-template-columns:repeat(3,1fr)}}@media(max-width:780px){.wrap{padding:14px}.layout{grid-template-columns:1fr}.grid{grid-template-columns:repeat(2,1fr)}.kval{font-size:19px}}
</style></head><body><div class="wrap"><div class="top"><div><div class="brand">NIXO <span>ADVANCED ANALYTICS</span></div><div class="sub">Performance intelligence · Strategy / Entry type / External source</div></div><div class="file">Source export: __TITLE__</div></div>
<div class="grid" id="kpis"></div><div class="layout"><section class="panel"><h2>REALIZED EQUITY CURVE</h2><svg id="equity" class="chart" viewBox="0 0 760 260" preserveAspectRatio="none"></svg><div class="legend"><span>Position-level realized net P/L</span><span id="drawdown"></span></div></section><section class="panel"><h2>PERFORMANCE BY ENTRY GROUP</h2><div id="groups"></div></section></div>
<section class="panel wide"><h2>TRADE EXPLORER</h2><div class="filters"><input id="search" placeholder="Search symbol / strategy / source"><select id="mode"><option value="">All modes</option><option>MANUAL</option><option>STRATEGY</option><option>EXTERNAL SIGNALS</option></select><select id="result"><option value="">All results</option><option value="win">Winners</option><option value="loss">Losers</option></select></div><div class="tablewrap"><table><thead><tr><th>Group / Source</th><th>Symbol</th><th>Side</th><th>Open</th><th>Close</th><th>Volume</th><th>Risk $</th><th>Plan RR</th><th>Realized $</th><th>R multiple</th><th>Hold min</th></tr></thead><tbody id="trades"></tbody></table></div></section>
<section class="panel wide"><h2>CURRENT OPEN POSITIONS</h2><div class="tablewrap"><table><thead><tr><th>Mode</th><th>Symbol</th><th>Side</th><th>Volume</th><th>Floating P/L</th><th>Initial SL</th><th>Risk $</th></tr></thead><tbody id="opens"></tbody></table></div></section><div class="sub" style="margin:18px 2px">Metrics are computed from the exported Nixo deal history. R multiple is realized net P/L divided by the entry-time risk snapshot; trades without a recorded risk snapshot show R = 0. Export after deals have fully closed for final statistics.</div></div>
<script>const D=__DATA__;const fmt=n=>Number(n||0).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2});const pct=n=>Number(n||0).toFixed(1)+'%';const k=D.kpi;const items=[['Closed trades',k.closed],['Win rate',pct(k.win_rate)],['Net profit',fmt(k.net)],['Profit factor',Number.isFinite(k.profit_factor)?k.profit_factor.toFixed(2):'∞'],['Expectancy / trade',fmt(k.expectancy)],['Average R',k.avg_r.toFixed(2)],['Max drawdown',fmt(k.max_dd)],['Average win',fmt(k.avg_win)],['Average loss',fmt(k.avg_loss)],['Average hold',k.avg_hold.toFixed(1)+' min'],['Max win streak',k.max_win_streak],['Max loss streak',k.max_loss_streak]];document.getElementById('kpis').innerHTML=items.map((x,i)=>`<div class="card"><div class="klabel">${x[0]}</div><div class="kval ${i===2?(k.net>=0?'positive':'negative'):''}">${x[1]}</div></div>`).join('');document.getElementById('drawdown').textContent='Max drawdown: '+fmt(k.max_dd);
const curve=D.curve;const svg=document.getElementById('equity');if(curve.length){let min=Math.min(0,...curve.map(x=>x.value)),max=Math.max(0,...curve.map(x=>x.value));if(max===min)max=min+1;const pts=curve.map((x,i)=>[18+i*(724/Math.max(1,curve.length-1)),238-(x.value-min)/(max-min)*210]);const path=pts.map((p,i)=>(i?'L':'M')+p[0].toFixed(1)+','+p[1].toFixed(1)).join(' ');svg.innerHTML=`<path d="M18 238 H742" stroke="#30435d" fill="none"/><path d="${path}" stroke="#e6bd70" stroke-width="3" fill="none" stroke-linejoin="round"/><text x="18" y="16" fill="#96a9c2" font-size="11">${fmt(max)}</text><text x="18" y="252" fill="#96a9c2" font-size="11">${fmt(min)}</text>`}else svg.innerHTML='<text x="50%" y="50%" text-anchor="middle" fill="#9aa9bf">No closed trades in this export</text>';
const maxAbs=Math.max(1,...D.groups.map(x=>Math.abs(x.net)));document.getElementById('groups').innerHTML=D.groups.length?D.groups.map(g=>`<div class="barrow"><div title="${g.name}">${g.name}</div><div><div class="track"><div class="fill" style="width:${Math.abs(g.net)/maxAbs*100}%;background:${g.net>=0?'#49d5a0':'#ff7778'}"></div></div><div class="muted" style="font-size:11px;margin-top:5px">${g.trades} trades · WR ${pct(g.win_rate)} · PF ${Number.isFinite(g.pf)?g.pf.toFixed(2):'∞'} · Avg R ${g.avg_r.toFixed(2)}</div></div><div class="barval ${g.net>=0?'positive':'negative'}">${fmt(g.net)}</div></div>`).join(''):'<div class="empty">No grouped trades.</div>';
function render(){const q=document.getElementById('search').value.toLowerCase(),m=document.getElementById('mode').value,r=document.getElementById('result').value;const rows=D.trades.filter(t=>(!m||t.mode===m)&&(!r||(r==='win'?t.net>0:t.net<0))&&(`${t.group} ${t.symbol} ${t.source} ${t.strategy_id}`.toLowerCase().includes(q)));document.getElementById('trades').innerHTML=rows.length?rows.map(t=>`<tr><td>${t.group}</td><td>${t.symbol}</td><td>${t.side}</td><td>${t.open}</td><td>${t.close}</td><td>${t.volume.toFixed(2)}</td><td>${fmt(t.risk)}</td><td>${t.planned_rr.toFixed(2)}</td><td class="${t.net>=0?'positive':'negative'}">${fmt(t.net)}</td><td>${t.r.toFixed(2)}R</td><td>${t.duration.toFixed(1)}</td></tr>`).join(''):'<tr><td colspan="11" class="empty">No trades match the current filters.</td></tr>';}['search','mode','result'].forEach(id=>document.getElementById(id).addEventListener('input',render));render();document.getElementById('opens').innerHTML=D.opens.length?D.opens.map(o=>`<tr><td>${o.mode}</td><td>${o.symbol}</td><td>${o.deal_type}</td><td>${Number(o.volume||0).toFixed(2)}</td><td>${fmt(o.profit)}</td><td>${o.initial_sl}</td><td>${fmt(o.risk_money)}</td></tr>`).join(''):'<tr><td colspan="7" class="empty">No open Nixo positions in this snapshot.</td></tr>';</script></body></html>'''

def main():
    parser=argparse.ArgumentParser(description="Build an offline Nixo analytics dashboard")
    parser.add_argument("--input", required=True, type=Path, help="Nixo MT5 report CSV")
    parser.add_argument("--output", type=Path, default=None, help="Optional HTML output path")
    args=parser.parse_args()
    source=args.input.expanduser().resolve()
    if not source.is_file():
        parser.error(f"Input CSV not found: {source}")
    destination=(args.output.expanduser().resolve() if args.output else source.parent/"Nixo_Analytics_Report.html")
    payload=make_report(source,destination)
    print(f"Nixo report created: {destination}")
    print(f"Closed trades: {payload['kpi']['closed']} | Win rate: {payload['kpi']['win_rate']:.1f}% | Net: {payload['kpi']['net']:.2f}")

if __name__ == "__main__":
    main()
