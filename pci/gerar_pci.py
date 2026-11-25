# Gera PCI.zip (PCI.csv: CELULA;PCI;RACH;FONTE) a partir das planilhas "lógico" 4G/5G dos vendors (formato longo:
# célula, Parâmetro, Data, Valor Actual). Uso: python gerar_pci.py originais/*.xlsx   (precisa de openpyxl)
import sys, os, re, io, zipfile, openpyxl, warnings
warnings.filterwarnings('ignore')
PCI = {'physicallayercellid', 'phycellid', 'pci', 'nrpci', 'physicalcellid', 'physcellid'}
RACH = {'rootseqindex', 'rachrootsequence', 'rootsequenceidx', 'logicalrootsequenceindex', 'prachrootsequenceindex', 'rootsequenceindex'}
NOMES = ['CELL_NAME', 'NRCELL_NAME', 'LNCEL_NAME', 'NRCELL', 'NRCELLDU', 'EUTRANCELLFDD']
cells = {}; datas = set()
for f in sys.argv[1:]:
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
out = io.StringIO(); out.write('CELULA;PCI;RACH;FONTE\n'); n = 0
for c, d in sorted(cells.items()):
    if 'p' not in d: continue
    out.write('%s;%s;%s;%s\n' % (c, d['p'], d.get('r', ''), d['f'])); n += 1
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'PCI.zip')
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.writestr('PCI.csv', out.getvalue()); z.writestr('LEIAME.txt', 'Data: %s\nCelulas: %d\n' % (max(datas) if datas else '', n))
print(n, 'celulas ->', os.path.abspath(dst), os.path.getsize(dst))
