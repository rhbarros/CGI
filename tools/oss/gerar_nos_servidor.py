# Nós Ericsson por servidor (CVOA/CVOB/CVO) e IP de gerência, a partir dos exports dos servidores.
# Aceita qualquer export com NodeId na 1a coluna (EARFCN, UtranFreqRelation...) e o ComConnectivityInformation
# (NodeId, ComConnectivityInformationId, ipAddress), que traz todos os nós COM (2G/3G/4G/5G Baseband) com o IP.
# Uso: python gerar_nos_servidor.py CVOA=arq1,arq2 CVOB=arq3 CVO=arq4  -> grava nos_servidor.json ao lado
import sys, json, os, re, collections
m = collections.defaultdict(set); ip = {}
IPRE = re.compile(r'^\d{1,3}(\.\d{1,3}){3}$|^[0-9a-fA-F:]+:[0-9a-fA-F:]+$')
for a in sys.argv[1:]:
    srv, fs = a.split('=', 1)
    for f in fs.split(','):
        for l in open(f, encoding='latin1'):
            c = l.rstrip('\r\n').split('\t')
            if len(c) < 3 or not c[1].strip(): continue
            n = c[0].strip().upper()
            if not n or ' ' in n or n.startswith('>') or n.startswith('NODE'): continue
            m[n].add(srv)
            if 'connectivity' in f.lower() and IPRE.match(c[2].strip()): ip[n] = c[2].strip()
out = collections.defaultdict(list); dup = []
for n, v in sorted(m.items()):
    if len(v) == 1: out[next(iter(v))].append(n)
    else: dup.append(n)  # aparece em mais de um servidor: fica para a busca automática decidir
res = {'_info': 'Nós por servidor (exports ComConnectivityInformation, EARFCN e UtranFreqRelation); nós em mais de um servidor ficam de fora. _ip = IP de gerência.',
       '_dup': dup, '_ip': dict(sorted(ip.items()))}
res.update({k: sorted(v) for k, v in out.items()})
json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nos_servidor.json'), 'w'), separators=(',', ':'))
print({k: len(v) for k, v in out.items()}, 'com IP', len(ip), 'duplicados', dup)
