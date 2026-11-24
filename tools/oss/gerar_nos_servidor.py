# Nós Ericsson por servidor (CVOA/CVOB/CVO) e IP de gerência, a partir dos exports dos servidores.
# Aceita qualquer export com NodeId na 1a coluna (EARFCN, UtranFreqRelation...) e o ComConnectivityInformation
# (NodeId, ComConnectivityInformationId, ipAddress), que traz todos os nós COM (2G/3G/4G/5G Baseband) com o IP.
# Uso: python gerar_nos_servidor.py CVOA=arq1,arq2 CVOB=arq3 CVO=arq4 IP:CVOA=bsc_cvoa  -> grava nos_servidor.json ao lado
# (IP:SERVIDOR=arquivo grava só o IP, sem marcar o nó como daquele servidor: usado para as BSCs, que vão pelo servidor 2G)
import sys, json, os, re, collections
m = collections.defaultdict(set); ip = {}
IPRE = re.compile(r'^\d{1,3}(\.\d{1,3}){3}$|^[0-9a-fA-F:]+:[0-9a-fA-F:]+$')
bscx = {}
for a in sys.argv[1:]:
    srv, fs = a.split('=', 1)
    iponly = srv.startswith('IP:')          # IP:CVOA=arq -> só o IP (ex.: BSC, que a aba 07 abre pelo servidor 2G)
    srv = srv[3:] if iponly else srv
    for f in fs.split(','):
        ipcol = 2 if 'connectivity' in f.lower() else None; hdr = None
        for l in open(f, encoding='latin1'):
            c = l.rstrip('\r\n').split('\t')
            if c and c[0].strip() == 'NodeId':   # cabeçalho: acha a coluna ipAddress (BSC tem várias colunas)
                hdr = [x.strip() for x in c]
                if 'ipAddress' in hdr: ipcol = hdr.index('ipAddress')
                continue
            if len(c) < 3 or not c[1].strip(): continue
            n = c[0].strip().upper()
            if not n or ' ' in n or n.startswith('>') or n.startswith('NODE'): continue
            if not iponly: m[n].add(srv)
            if ipcol is not None and ipcol < len(c) and IPRE.match(c[ipcol].strip()): ip[n] = c[ipcol].strip()
            if hdr and 'apnodeAIpAddress' in hdr:
                bscx[n] = {'srv': srv, 'apA': c[hdr.index('apnodeAIpAddress')].strip(), 'apB': c[hdr.index('apnodeBIpAddress')].strip()}
out = collections.defaultdict(list); dup = []
for n, v in sorted(m.items()):
    if len(v) == 1: out[next(iter(v))].append(n)
    else: dup.append(n)  # aparece em mais de um servidor: fica para a busca automática decidir
res = {'_info': 'Nós por servidor (exports ComConnectivityInformation, EARFCN e UtranFreqRelation); nós em mais de um servidor ficam de fora. _ip = IP de gerência.',
       '_dup': dup, '_ip': dict(sorted(ip.items())), '_bsc': bscx}
res.update({k: sorted(v) for k, v in out.items()})
json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nos_servidor.json'), 'w'), separators=(',', ':'))
print({k: len(v) for k, v in out.items()}, 'com IP', len(ip), 'duplicados', dup)
