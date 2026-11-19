# Nós Ericsson por servidor (CVOA/CVOB/CVO) a partir dos exports dos servidores (NodeId na 1a coluna).
# Uso: python gerar_nos_servidor.py CVOA=arq1,arq2 CVOB=arq3 CVO=arq4  -> grava nos_servidor.json ao lado
import sys, json, os, collections
m = collections.defaultdict(set)
for a in sys.argv[1:]:
    srv, fs = a.split('=', 1)
    for f in fs.split(','):
        for l in open(f, encoding='latin1'):
            c = l.rstrip('\r\n').split('\t')
            if len(c) < 3 or not c[1].strip(): continue
            n = c[0].strip().upper()
            if not n or ' ' in n or n.startswith('>') or n.startswith('NODE'): continue
            m[n].add(srv)
out = collections.defaultdict(list); dup = []
for n, v in sorted(m.items()):
    if len(v) == 1: out[next(iter(v))].append(n)
    else: dup.append(n)  # aparece em mais de um servidor: fica para a busca automática decidir
res = {'_info': 'Nós 4G (EUtranCell) exportados dos servidores; nós em mais de um servidor ficam de fora.', '_dup': dup}
res.update({k: sorted(v) for k, v in out.items()})
json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nos_servidor.json'), 'w'), separators=(',', ':'))
print({k: len(v) for k, v in out.items()}, 'duplicados', dup)
