# Gera PCI.zip (PCI.csv: CELULA;PCI;RACH;FONTE) a partir das planilhas "lógico" 4G/5G dos vendors (formato longo:
# célula, Parâmetro, Data, Valor Actual) e do "LTE Cell Report" do MAE da Huawei (.csv: Cell Name, Physical Cell ID).
# Também lê os exports do ENM Ericsson (.txt, tab: NodeId, ...FunctionId, célula, physicalLayerCellId|nRPCI, rachRootSequence)
# e o "NR Cell Report" do MAE da Huawei (5G). Dados da gerência (ENM/MAE) valem por cima das planilhas.
# Uso: python gerar_pci.py originais/*   (precisa de openpyxl).
import sys, os, re, io, csv, zipfile, openpyxl, warnings
warnings.filterwarnings('ignore')
PCI = {'physicallayercellid', 'phycellid', 'pci', 'nrpci', 'physicalcellid', 'physcellid'}
RACH = {'rootseqindex', 'rachrootsequence', 'rootsequenceidx', 'logicalrootsequenceindex', 'prachrootsequenceindex', 'rootsequenceindex'}
NOMES = ['CELL_NAME', 'NRCELL_NAME', 'LNCEL_NAME', 'NRCELL', 'NRCELLDU', 'EUTRANCELLFDD']
cells = {}; datas = set()
mae = [f for f in sys.argv[1:] if f.lower().endswith('.csv')]
enm = [f for f in sys.argv[1:] if f.lower().endswith('.txt')]
for f in [f for f in sys.argv[1:] if f.lower().endswith('.xlsx')]:
    b = os.path.basename(f).upper(); tec = '5G' if '5G' in b else '4G'
    vend = next((v for v in ['ERICSSON', 'HUAWEI', 'NOKIA', 'ZTE'] if v in b), '?')
    ws = openpyxl.load_workbook(f, read_only=True).worksheets[0]; hdr = None
    for r in ws.iter_rows(values_only=True):
        if hdr is None:
            hdr = [str(x) for x in r]; ip = hdr.index('Parâmetro'); ic = next((hdr.index(h) for h in NOMES if h in hdr), ip - 1); continue
        cel = str(r[ic] or '').strip().upper(); p = str(r[ip] or '').strip().lower(); v = str(r[-1] if r[-1] is not None else '').strip()
        if len(r) > ip + 1 and r[ip + 1]: datas.add(str(r[ip + 1])[:10])
        if not cel or cel == '-' or not re.match(r'^\d+$', v): continue
        d = cells.setdefault(cel, {'f': vend[:3] + tec})
        if p in PCI: d['p'] = v
        elif p in RACH: d['r'] = v
for f in enm:   # exports ENM Ericsson (podem ter vários blocos de cabeçalho)
    hdr = None
    for ln in open(f, encoding='utf-8', errors='replace'):
        t = ln.rstrip('\r\n').split('\t')
        if t[0] == 'NodeId':
            hdr = [x.strip().lower() for x in t]; fo = 'ERI5' if 'nrpci' in hdr else 'ERI4'
            ip = next(i for i, h in enumerate(hdr) if h in PCI); ir = next((i for i, h in enumerate(hdr) if h in RACH), None); continue
        if hdr is None or len(t) < len(hdr): continue
        cel = t[2].strip().upper(); v = t[ip].strip()
        if not cel or not v.isdigit(): continue
        d = cells.setdefault(cel, {}); d['f'] = fo; d['p'] = v
        if ir is not None and t[ir].strip().isdigit(): d['r'] = t[ir].strip()
for f in mae:   # LTE / NR Cell Report do MAE (Huawei 4G / 5G)
    m = re.search(r'(\d{8})', os.path.basename(f))
    if m: datas.add('%s-%s-%s' % (m.group(1)[:4], m.group(1)[4:6], m.group(1)[6:8]))
    fo = 'HUA5' if os.path.basename(f).upper().startswith('NR') else 'HUA4'
    for r in csv.DictReader(open(f, encoding='utf-8-sig', errors='replace')):
        cel = (r.get('Cell Name') or '').strip().upper(); v = (r.get('Physical Cell ID') or '').strip()
        if not cel or not v.isdigit(): continue
        d = cells.setdefault(cel, {}); d['p'] = v; d['f'] = fo
out = io.StringIO(); out.write('CELULA;PCI;RACH;FONTE\n'); n = 0
for c, d in sorted(cells.items()):
    if 'p' not in d: continue
    out.write('%s;%s;%s;%s\n' % (c, d['p'], d.get('r', ''), d['f'])); n += 1
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'PCI.zip')
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.writestr('PCI.csv', out.getvalue()); z.writestr('LEIAME.txt', 'Data: %s\nCelulas: %d\n' % (max(datas) if datas else '', n))
print(n, 'celulas ->', os.path.abspath(dst), os.path.getsize(dst))
