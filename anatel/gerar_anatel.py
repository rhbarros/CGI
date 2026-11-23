# Gera ANATEL.zip (ANATEL_ERBS.csv compacto) a partir da tabela "Operadoras_TABELAS ... .xlsb" (aba Operadoras_SITES).
# Uso: python gerar_anatel.py "Operadoras_TABELAS 2026_W11 (08-Mar a 14-Mar).xlsb"   (precisa de: pip install pyxlsb)
import sys, os, io, zipfile, re, collections
from pyxlsb import open_workbook
src = sys.argv[1]
wb = open_workbook(src)
out = io.StringIO(); out.write('OPERADORA;ENTIDADE;LAT;LON;TECS;UF;MUNICIPIO;ESTACAO\n')
n = 0; ents = collections.Counter()
def fix(s):
    s = '' if s is None else str(s)
    try: s = s.encode('cp437').decode('utf-8')   # endereços/nomes vieram com acentos quebrados (├â → Ã)
    except Exception: pass
    return s.replace(';', ',').strip()
with wb.get_sheet('Operadoras_SITES') as sh:
    for i, r in enumerate(sh.rows()):
        v = [c.v for c in r]
        if i < 2 or len(v) < 20: continue
        try: lat = float(v[7]); lon = float(v[8])
        except Exception: continue
        op = fix(v[13]).upper(); ent = fix(v[1]) if op == 'OUTRAS' else ''
        if ent: ents[ent] += 1
        out.write('%s;%s;%.5f;%.5f;%s;%s;%s;%s\n' % (op, ent, lat, lon, fix(v[19]), fix(v[5]), fix(v[14]), fix(v[3])))
        n += 1
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ANATEL.zip')
m = re.search(r'(\d{4}_W\d+[^.]*)', os.path.basename(src))
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.writestr('ANATEL_ERBS.csv', out.getvalue().encode('utf-8'))
    z.writestr('LEIAME.txt', 'Fonte: %s\nEstacoes: %d\n' % (os.path.basename(src), n))
print(n, 'estacoes ->', os.path.abspath(dst), os.path.getsize(dst)); print(ents.most_common(12))
