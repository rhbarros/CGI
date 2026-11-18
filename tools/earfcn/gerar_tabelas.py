import csv, glob, collections, os, re, sys
A='/mnt/user-data/attachments/d7132abd-c78b-5a1d-bacc-49aa74bffb36/'
SRC={'CVOA':A+'d9ff4c43-cvoa_earfcndl','CVOB':A+'c68444c5-CVOB_EARFCNDL__1_','CVO':A+'47b08d56-CVO_EARFCNDL__1_'}
cgi=glob.glob('/tmp/claude-0/cgiz/*.csv')[0]
bycell, bysite, bybase, byst = {}, {}, {}, {}
with open(cgi, encoding='latin1') as f:
    r=csv.reader(f, delimiter=';'); h=next(r)
    for c in r:
        if len(c)<16: continue
        reg,st,uf,cid,tec,site,cel,ven=c[0].strip(),c[1].strip(),c[2].strip(),c[3].strip(),c[5].strip(),c[10].strip().upper(),c[11].strip().upper(),c[15].strip().upper()
        if ven!='ERICSSON' or not reg: continue
        info=(reg,uf,cid,st)
        if cel: bycell.setdefault(cel,info)
        if site and tec!='2G': bysite.setdefault(site,info); bybase.setdefault(re.sub(r'^[0-9][A-Z]-','',site),info)
def band_name(b):
    return {'1':'2100','3':'1800','5':'850','7':'2600','8':'900','28':'700','38':'2600 TDD','40':'2300 TDD','41':'2500 TDD'}.get(b, 'B'+b)
rows=[]; miss=collections.Counter()
for srv,p in SRC.items():
    for l in open(p, encoding='latin1'):
        c=l.rstrip('\n').split('\t')
        if len(c)<9 or c[0]=='NodeId': continue
        node,cell,bw,dl,band=c[0].strip(),c[2].strip(),c[4].strip(),c[6].strip(),c[7].strip()
        if not dl.isdigit(): continue
        n=node.upper(); k=cell.upper()
        info=bycell.get(k) or bysite.get(n) or bysite.get(re.sub(r'-\d+$','',n)) or bybase.get(re.sub(r'^[0-9][A-Z]-','',re.sub(r'-\d+$','',n)))
        if not info: miss[srv]+=1
        reg,uf,cid,st=info if info else ('SEM_REGIONAL','','','')
        rows.append(dict(regional=reg,servidor=srv,uf=uf,cidade=cid,station=st,node=node,celula=cell,earfcndl=int(dl),banda=band_name(band),freqBand=band,bw=bw))
print('células', len(rows), 'sem regional', dict(miss))
out='/tmp/claude-0/earfcn/out'; os.makedirs(out, exist_ok=True)
for f in glob.glob(out+'/*'): os.remove(f)
regs=sorted(set(r['regional'] for r in rows))
cols=['regional','servidor','uf','cidade','station','node','celula','earfcndl','banda','freqBand','bw']
summ={}
for reg in regs:
    R=[r for r in rows if r['regional']==reg]
    with open(f'{out}/EARFCN_{reg}_celulas.csv','w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f, fieldnames=cols, delimiter=';'); w.writeheader(); [w.writerow(r) for r in sorted(R,key=lambda r:(r['node'],r['celula']))]
    agg=collections.OrderedDict()
    for r in R:
        k=(r['earfcndl'],r['banda'],r['freqBand'])
        a=agg.setdefault(k,{'cells':0,'sites':set(),'bw':collections.Counter(),'srv':collections.Counter()})
        a['cells']+=1; a['sites'].add(r['node']); a['bw'][r['bw']]+=1; a['srv'][r['servidor']]+=1
    summ[reg]=agg
    with open(f'{out}/EARFCN_{reg}.csv','w',newline='',encoding='utf-8-sig') as f:
        w=csv.writer(f, delimiter=';'); w.writerow(['regional','earfcndl','banda','freqBand','larguras_khz','celulas','sites','servidores'])
        for (dl,bn,fb),a in sorted(agg.items(), key=lambda x:(-x[1]['cells'])):
            w.writerow([reg,dl,bn,fb,' / '.join(f'{b} ({n})' for b,n in a['bw'].most_common()),a['cells'],len(a['sites']),' / '.join(f'{s} ({n})' for s,n in a['srv'].most_common())])
# markdown resumo
md=['# EARFCN DL por regional (Ericsson 4G)\n','Fonte: export `earfcndl` dos servidores CVOA, CVOB e CVO (EUtranCellFDD), regional pela CGI (`CGI.zip`, coluna REGIONAL, por célula/site).\n',
    f'Total: {len(rows)} células · {len(set(r["node"] for r in rows))} nós.\n']
# visao geral: todos os EARFCN DL por regional, por banda (mais usados primeiro)
BORD=['700','850','900','1800','2100','2600']
bands=sorted({k[1] for a in summ.values() for k in a}, key=lambda b:(BORD.index(b) if b in BORD else 99, b))
ordem=sorted(regs, key=lambda g:(g in ('ND','SEM_REGIONAL'), g=='SEM_REGIONAL', -sum(a['cells'] for a in summ[g].values())))
def lst(agg,b): return ' · '.join(f"{k[0]} ({a['cells']})" for k,a in sorted(agg.items(), key=lambda x:-x[1]['cells']) if k[1]==b) or '—'
md.append('\n## EARFCN DL mais usados — todas as regionais\n')
md.append('Todos os EARFCN DL encontrados, por banda, do mais usado para o menos usado. Entre parênteses: número de células.\n')
md.append('| Regional | Células | Nós | '+' | '.join(bands)+' |'); md.append('|---|---|---|'+'---|'*len(bands))
with open(f'{out}/EARFCN_RESUMO.csv','w',newline='',encoding='utf-8-sig') as f:
    w=csv.writer(f, delimiter=';'); w.writerow(['regional','celulas','nos']+bands)
    for reg in ordem:
        agg=summ[reg]; R=[r for r in rows if r['regional']==reg]; nn=len(set(r['node'] for r in R))
        md.append(f"| **{reg}** | {len(R)} | {nn} | "+' | '.join(lst(agg,b) for b in bands)+' |')
        w.writerow([reg,len(R),nn]+[lst(agg,b) for b in bands])
for reg in ordem:
    agg=summ[reg]; R=[r for r in rows if r['regional']==reg]
    md.append(f'\n## {reg} — {len(R)} células, {len(set(r["node"] for r in R))} nós\n')
    md.append('| EARFCN DL | Banda | Larguras (kHz) | Células | Sites | Servidores |'); md.append('|---|---|---|---|---|---|')
    for (dl,bn,fb),a in sorted(agg.items(), key=lambda x:(x[0][2].zfill(3), -x[1]['cells'])):
        md.append(f"| {dl} | {bn} (B{fb}) | {', '.join(f'{b}' for b,n in a['bw'].most_common())} | {a['cells']} | {len(a['sites'])} | {', '.join(f'{s} {n}' for s,n in a['srv'].most_common())} |")
md.append('\nArquivos: `EARFCN_RESUMO.csv` (visão geral acima), `EARFCN_<REGIONAL>.csv` (resumo por EARFCN) e `EARFCN_<REGIONAL>_celulas.csv` (célula a célula).\n')
open(out+'/README.md','w').write('\n'.join(md)+'\n')
