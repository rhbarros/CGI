import re, json, sys
HEAD = re.compile(r'^\s*\d+(?:\.\d+)+\s+(SO|AO)\s+([A-Z]+)\s+(I1A|I1B|I2A|EC1|EC2|RU):(\d+)\s+-\s+(.+?)\s*$')
JUNK = re.compile(r'^\s*(1/006 51-LZA.*|Fault List RBS.*|\d+\s+1/006 51-LZA.*|.*1/006 51-LZA 701.*|\s*(SO|AO) [A-Z]+ Fault Maps\s*|AO Fault Maps)\s*$')
SEC = re.compile(r'^\s*\d+(?:\.\d+)*\s+(SO|AO)\s+[A-Z]+\s+(Internal Fault Map|External Condition Map|Replacement Unit Map).*$')
def parse(fn):
    L = open(fn, encoding='utf-8', errors='replace').read().split('\n')
    out = {}; cur = None; buf = []
    def flush():
        if not cur: return
        txt = '\n'.join(buf); f = {'t': cur[4]}
        parts = re.split(r'^\s*(Related RUs|Description|Action)\b', txt, flags=re.M)
        for i in range(1, len(parts) - 1, 2):
            k = {'Related RUs': 'ru', 'Description': 'd', 'Action': 'a'}[parts[i]]
            v = re.sub(r'\s+', ' ', parts[i + 1]).strip()
            v = re.sub(r'\s*— ', ' • ', v).strip(' •')
            if k == 'ru': v = [x.strip() for x in re.split(r'\s*Section\s+[\d.]+\s+.*?on page \d+\s*', v) if x.strip()]
            f[k] = v
        out['%s %s %s:%s' % cur[:4]] = f
    for l in L:
        m = HEAD.match(l)
        if m:
            flush(); cur = m.groups(); buf = []; continue
        if (SEC.match(l) and 'on page' not in l) or re.match(r'^\s*\d+\s+(SO|AO) [A-Z]+ Fault Maps', l) or re.match(r'^\s*5\s+AO Fault Maps', l):
            flush(); cur = None; buf = []; continue
        if JUNK.match(l) or not cur: continue
        buf.append(l)
    flush()
    # tabelas de RU: 'Table n  SO CF Replacement Unit Map' seguidas de linhas 'No  RU'
    mo = None
    for l in L:
        m = re.match(r'^\s*Table \d+\s+(SO|AO)\s+([A-Z]+)\s+Replacement Unit Map', l)
        if m: mo = m.group(1) + ' ' + m.group(2); continue
        if mo:
            if re.match(r'^\s*\d+(\.\d+)+\s+\S', l) or re.match(r'^\s*Table \d+', l): mo = None; continue
            m = re.match(r'^\s{10,}(\d{1,3})\s{2,}(\S.*?)\s*$', l)
            if m and not JUNK.match(l): out['%s RU:%s' % (mo, m.group(1))] = {'t': m.group(2)}
    return out
r2, r6 = parse('r2000.txt'), parse('r6000.txt')
print(len(r2), len(r6))
import collections
print(collections.Counter(k.rsplit(':',1)[0] for k in r6))
json.dump({'RBS6000': r6, 'RBS2000': r2}, open('fault_codes.json', 'w'), ensure_ascii=False, separators=(',', ':'))
for k in ['SO CF I1A:8', 'SO CF I2A:44', 'SO TRXC I1A:4', 'AO TX I1B:47', 'SO CF RU:0']:
    print(k, json.dumps(r6.get(k), ensure_ascii=False)[:500])
