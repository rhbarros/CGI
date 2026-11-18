# UtranFreqRelation (WCDMA) por regional: exports CVOA/CVOB/CVO x CGI. Mesma busca de regional do gerar_tabelas.py.
import csv, glob, collections, os, re, json
A='/mnt/user-data/attachments/d7132abd-c78b-5a1d-bacc-49aa74bffb36/'
SRC={'CVOA':A+'36c98815-UtranFreqRelationId_cvoa','CVOB':A+'83c58ea2-UtranFreqRelationId_cvob','CVO':A+'4d4ee012-UtranFreqRelationId_cvo'}
cgi=glob.glob('/tmp/claude-0/cgiz/*.csv')[0]
bycell, bysite, bybase = {}, {}, {}
with open(cgi, encoding='latin1') as f:
    r=csv.reader(f, delimiter=';'); next(r)
    for c in r:
        if len(c)<16: continue
        reg,tec,site,cel,ven=c[0].strip(),c[5].strip(),c[10].strip().upper(),c[11].strip().upper(),c[15].strip().upper()
        if ven!='ERICSSON' or not reg: continue
        if cel: bycell.setdefault(cel,reg)
        if site and tec!='2G': bysite.setdefault(site,reg); bybase.setdefault(re.sub(r'^[0-9][A-Z]-','',site),reg)
def band3g(u):
    u=int(u)
    if 10562<=u<=10838: return '2100'
    if 4357<=u<=4458: return '850'
    if 2937<=u<=3088: return '900'
    return '?'
rows=[]
for srv,p in SRC.items():
    for l in open(p, encoding='latin1'):
        c=l.rstrip('\r\n').split('\t')
        if len(c)<4 or not c[3].startswith('WCDMA_'): continue
        node,cell,rel=c[0].strip(),c[2].strip(),c[3].strip()
        n=node.upper()
        reg=bycell.get(cell.upper()) or bysite.get(n) or bysite.get(re.sub(r'-\d+$','',n)) or bybase.get(re.sub(r'^[0-9][A-Z]-','',re.sub(r'-\d+$','',n))) or 'SEM_REGIONAL'
        u=rel.split('_')[1]
        rows.append(dict(regional=reg,servidor=srv,node=node,celula=cell,uarfcn=u,banda=band3g(u)))
out='/tmp/claude-0/utran/out'; os.makedirs(out,exist_ok=True)
regs=sorted({r['regional'] for r in rows})
summ={}
with open(out+'/UTRAN_RESUMO.csv','w',newline='',encoding='utf-8-sig') as f:
    w=csv.writer(f,delimiter=';'); w.writerow(['regional','uarfcn_dl','banda','celulas_lte_com_relacao','pct_celulas','nos','servidores'])
    for reg in regs:
        R=[r for r in rows if r['regional']==reg]; cells=len({(r['node'],r['celula']) for r in R})
        agg={}
        for r in R:
            a=agg.setdefault(r['uarfcn'],{'c':set(),'n':set(),'s':collections.Counter(),'b':r['banda']}); a['c'].add((r['node'],r['celula'])); a['n'].add(r['node']); a['s'][r['servidor']]+=1
        summ[reg]={'cells':cells,'nodes':len({r['node'] for r in R}),'agg':agg}
        for u,a in sorted(agg.items(), key=lambda x:-len(x[1]['c'])):
            w.writerow([reg,u,a['b'],len(a['c']),round(100*len(a['c'])/cells,1),len(a['n']),' / '.join(f'{s} ({n})' for s,n in a['s'].most_common())])
# regra (mesma ideia do LTE): entra o UARFCN presente em pelo menos 5% das células LTE da regional que têm relação WCDMA (mínimo 10 células)
top={reg:sorted((u for u,a in s['agg'].items() if len(a['c'])>=max(10,0.05*s['cells'])), key=int) for reg,s in summ.items() if reg not in ('SEM_REGIONAL','ND')}
json.dump(top,open(out+'/utran_top.json','w'))
md=['# UtranFreqRelation (WCDMA) por regional (Ericsson 4G)\n','Fonte: export `UtranFreqRelationId` dos servidores CVOA, CVOB e CVO (relações das EUtranCellFDD/TDD), regional pela CGI.\n',
    f'Total: {len(rows)} relações · {len({(r["node"],r["celula"]) for r in rows})} células LTE · {len({r["node"] for r in rows})} nós.\n',
    '\n## UARFCN mais declarados — todas as regionais\n','Formato **UARFCN (células LTE com a relação · % das células da regional)**. Em negrito na coluna "Script 4G": a lista usada na aba 05 (≥ 5% das células, mínimo 10).\n',
    '| Regional | Células LTE | Nós | 2100 | 850 | 900 | Script 4G |','|---|---|---|---|---|---|---|']
ordem=sorted(regs,key=lambda g:(g in ('ND','SEM_REGIONAL'),g=='SEM_REGIONAL',-summ[g]['cells']))
for reg in ordem:
    s=summ[reg]; col=lambda b:' · '.join(f"{u} ({len(a['c'])} · {100*len(a['c'])/s['cells']:.0f}%)" for u,a in sorted(s['agg'].items(),key=lambda x:-len(x[1]['c'])) if a['b']==b) or '—'
    md.append(f"| **{reg}** | {s['cells']} | {s['nodes']} | {col('2100')} | {col('850')} | {col('900')} | {', '.join('WCDMA_'+u for u in top.get(reg,[])) or '—'} |")
md.append('\nArquivo: `UTRAN_RESUMO.csv`. Gerado por `gerar_utran.py`.\n')
open(out+'/UTRAN_README.md','w').write('\n'.join(md)+'\n')
print(len(rows)); print(json.dumps(top))
