@echo off
rem ==========================================================================
rem  Instalador do Helper Ericsson (Ferramenta Ericsson RAN <-> OSS/AMOS)
rem  Rode UMA VEZ em cada computador. Depois o helper inicia sozinho com o
rem  Windows, escondido (sem janela). Para remover:  Instalar_Helper_Ericsson.bat remover
rem  ARQUIVO GERADO por tools/gerar_instalador.py - edite o modelo, nao este.
rem ==========================================================================
title Instalador do Helper Ericsson
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%~f0'; $acao='%~1'; $c=[IO.File]::ReadAllText($f); iex $c.Substring($c.IndexOf('#'+'POWERSHELL#')+12)"
echo.
pause
exit /b
#POWERSHELL#
$ErrorActionPreference = 'Stop'
$dir  = Join-Path $env:LOCALAPPDATA 'Ericsson_Helper'
$py_file = Join-Path $dir 'ericsson_helper.py'
$lnk  = Join-Path ([Environment]::GetFolderPath('Startup')) 'Ericsson Helper.lnk'
$reg  = 'HKCU:\Software\Classes\enmhelper'

function Stop-Helper {
  Get-CimInstance Win32_Process -Filter "Name like 'python%' or Name like 'py%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*ericsson_helper.py*' } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
}

function Find-Python {
  foreach ($c in @('py', 'python')) {
    try {
      $p = (& $c -c "import sys;print(sys.executable)" 2>$null | Select-Object -First 1)
      if ($LASTEXITCODE -eq 0 -and $p -and (Test-Path $p.Trim())) { return $p.Trim() }
    } catch {}
  }
  $g = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
       Sort-Object FullName -Descending | Select-Object -First 1
  if ($g) { return $g.FullName }
  return $null
}

Write-Host ''
Write-Host '=== Helper Ericsson - Ferramenta Ericsson RAN ===' -ForegroundColor Cyan

if ($acao -eq 'remover') {
  Stop-Helper
  Remove-Item $lnk -Force -ErrorAction SilentlyContinue
  Remove-Item $reg -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host 'Helper removido deste computador.' -ForegroundColor Green
  return
}

# 1) Python
$py = Find-Python
if (-not $py) {
  Write-Host 'Python nao encontrado. Instalando pelo winget (fonte winget, sem a Microsoft Store)...' -ForegroundColor Yellow
  $oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    winget install -e --id Python.Python.3.12 --source winget --scope user --silent --accept-package-agreements --accept-source-agreements | Out-Host
  } catch {}
  $ErrorActionPreference = $oldEap
  $py = Find-Python
}
if (-not $py) {
  Write-Host 'winget nao instalou. Baixando o instalador oficial do python.org...' -ForegroundColor Yellow
  $oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Proxy = [Net.WebRequest]::GetSystemWebProxy(); $wc.Proxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { '' }
    $url = if ($arch) { 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' } else { 'https://www.python.org/ftp/python/3.12.7/python-3.12.7.exe' }
    $exe = Join-Path $env:TEMP 'python-3.12.7-instalador.exe'
    $wc.DownloadFile($url, $exe)
    Write-Host 'Instalando o Python (so para este usuario, sem administrador; 1-2 min)...'
    $pr = Start-Process -FilePath $exe -ArgumentList '/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_launcher=0 Include_test=0 Shortcuts=0' -Wait -PassThru
    Remove-Item $exe -Force -ErrorAction SilentlyContinue
  } catch { Write-Host ('Download/instalacao falhou: ' + $_.Exception.Message) -ForegroundColor Yellow }
  $ErrorActionPreference = $oldEap
  $py = Find-Python
}
if (-not $py) {
  Write-Host ''
  Write-Host 'Nao consegui instalar o Python automaticamente (a rede da empresa bloqueou os downloads).' -ForegroundColor Red
  Write-Host 'Instale o Python 3 por uma destas opcoes e rode este instalador de novo:'
  Write-Host '  - Portal de software da empresa (Company Portal / Central de Software), se houver'
  Write-Host '  - https://www.python.org/downloads/  (marque "Add python.exe to PATH")'
  return
}
$pyw = Join-Path (Split-Path $py) 'pythonw.exe'
if (-not (Test-Path $pyw)) { $pyw = $py }
Write-Host "Python: $py"

# 1b) paramiko (SSH ate o servidor OSS) - obrigatorio
$oldEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $py -c "import paramiko" *> $null
$okParamiko = ($LASTEXITCODE -eq 0)
if (-not $okParamiko) {
  Write-Host 'Instalando paramiko (biblioteca SSH)...'
  & $py -m ensurepip --user *> $null
  & $py -m pip install --user --disable-pip-version-check -q paramiko *> $null
  & $py -c "import paramiko" *> $null; $okParamiko = ($LASTEXITCODE -eq 0)
}
if (-not $okParamiko) {
  # rede corporativa: proxy do Windows e certificado interceptado
  $px = $null; try { $p = [Net.WebRequest]::GetSystemWebProxy().GetProxy([Uri]'https://pypi.org'); if ($p.Host -ne 'pypi.org') { $px = $p.AbsoluteUri } } catch {}
  $args2 = @('-m','pip','install','--user','--disable-pip-version-check','-q','--trusted-host','pypi.org','--trusted-host','files.pythonhosted.org','paramiko')
  if ($px) { $args2 += @('--proxy', $px); Write-Host "Tentando pelo proxy $px..." }
  & $py @args2 *> $null
  & $py -c "import paramiko" *> $null; $okParamiko = ($LASTEXITCODE -eq 0)
}
$ErrorActionPreference = $oldEap
if ($okParamiko) { Write-Host 'paramiko (SSH): OK' } else {
  Write-Host 'Nao consegui instalar o paramiko (biblioteca SSH): a rede bloqueou o pip.' -ForegroundColor Red
  Write-Host 'Rode manualmente num Prompt de Comando e depois este instalador de novo:'
  Write-Host ('  "' + $py + '" -m pip install --user paramiko')
  return
}

# 2) Copia o helper (embutido neste arquivo)
Stop-Helper
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$code = @'
# ericsson_helper.py - Ponte Ferramenta Ericsson RAN (navegador) <-> servidor OSS/ENM (SSH) <-> AMOS
#
# O navegador nao abre SSH; este helper roda no PC e faz a ponte:
#   index2.html --HTTP--> 127.0.0.1:8766 (este helper) --SSH--> servidor OSS (porta 5022) --> amos <no>
#
# Uso:  python ericsson_helper.py            (porta local 8766)
#       python ericsson_helper.py --port 8766
#
# Usuario e senha chegam da pagina e ficam SO na memoria deste processo (nunca em disco).
import argparse, json, os, re, shlex, sys, threading, time, uuid
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.9"
LOCAL_PORT = 8766
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "helper.log")

# Paginas que podem usar o helper. Qualquer outro site e recusado.
ALLOWED_ORIGINS = {"https://rhbarros.github.io", "null"}
LOCAL_ORIGIN = re.compile(r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$")
WRITE_RE = re.compile(r"^\s*(set|sete|crn|cr|del|rdel|bl|deb|acc|run|ldeb|lbl|lset|lcr|ldel|restart|rbs|confb\+?|trun|pol|upgrade|cvms|cvmk|cvrm|cvset)\b", re.I)
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[=>()][0-9A-Za-z]?")
ASK_RE = re.compile(r"(\[y/n\]|\(y/n\)|\[yes/no\]|\(yes/no\)|y/n\]?|are you sure[^\n]*|continue\?)\s*[:?]?\s*$", re.I)
PWD_RE = re.compile(r"(password|senha)[^\n:]{0,40}:\s*$", re.I)
USER_RE = re.compile(r"(user\s*name|username|login|user|usuario)[^\n:]{0,40}:\s*$", re.I)
AUTH_FAIL_RE = re.compile(r"(permission denied|authentication (fail|error)|auth fail|access denied|login incorrect|incorrect (password|login|user)|wrong password|invalid (user|password|credential|login)|bad password|unable to (connect|login|log ?in|authenticate)|failed to (connect|login|log ?in|authenticate)|could not (connect|login|authenticate)|not authori[sz]ed|too many (authentication )?failures|connection (refused|closed|reset))", re.I)
FOUND_RE = re.compile(r"ip contact\.*\s*ok\b", re.I)
NOTFOUND_RE = re.compile(r"(ip contact\.*\s*not ok|unknown node|node\b[^\n]{0,60}\bnot found|no such node|(could not|unable to|cannot|failed to) resolve|not (found|defined) in (the )?(enm|oss|ipdatabase|database)|does not exist|invalid node|no route to host|host unreachable|name or service not known)", re.I)
SHELL_RE = re.compile(r"^\s*\[?[\w.\-]+@[\w.\-]+[^\n]{0,120}[\$#]\s*$")  # [usuario@servidor ~]$
NODE_PWD_OK = {}  # no -> indice da senha que funcionou (so em memoria)


def logf(msg):
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    except Exception:
        pass


def origin_ok(origin):
    return (not origin) or origin in ALLOWED_ORIGINS or bool(LOCAL_ORIGIN.match(origin))


def clean(s):
    return ANSI.sub("", s).replace("\r\n", "\n").replace("\r", "")


class Session:
    def __init__(self):
        self.client = None; self.chan = None; self.prompt = ""; self.host = ""; self.user = ""
        self.lock = threading.Lock(); self.banner = ""
        self.cur_node = None; self.lt_done = False; self.last_amos = ""; self.depth = 0
        self.key = ""; self.name = ""; self.port = 0; self._cred = None

    # ---------- leitura ----------
    def read_until(self, done, maxsec=60, idle=0.35, job=None, keep=True, quiet=0):
        """Le do canal ate done(tail) ser verdade e o canal ficar quieto por `idle` s."""
        parts, tail, t0, last = [], "", time.time(), time.time()
        total = 0
        while time.time() - t0 < maxsec:
            if job is not None and job.get("kill"):
                self.chan.send("\x03"); job["kill"] = False; job["log"].append("Ctrl-C enviado.")
            got = False
            try:
                if self.chan.recv_ready():
                    d = self.chan.recv(65536)
                    if not d:
                        raise ConnectionError("o servidor fechou a conexao")
                    s = clean(d.decode("utf-8", errors="ignore"))
                    if keep: parts.append(s)
                    total += len(s); tail = (tail + s)[-600:]; last = time.time(); got = True
                    if job is not None: job["bytes"] = job.get("bytes", 0) + len(s)
            except ConnectionError:
                raise
            except Exception:
                pass
            if self.chan.closed:
                raise ConnectionError("conexao SSH encerrada")
            r = done(tail)
            if r and time.time() - last >= idle:
                return "".join(parts), r
            if quiet and time.time() - last >= quiet:
                return "".join(parts), "quiet"  # sem saida nova e sem prompt conhecido: segue (como alguem digitando)
            if not got:
                time.sleep(0.05)
        return "".join(parts), None

    # ---------- login ----------
    def login(self, host, port, user, pwd):
        try:
            import paramiko
        except ImportError:
            raise RuntimeError("paramiko nao instalado: rode o instalador do helper de novo ou 'python -m pip install paramiko'")
        self.logout()
        c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, port=int(port), username=user, password=pwd, timeout=25, banner_timeout=40, auth_timeout=40, look_for_keys=False, allow_agent=False)
        try: c.get_transport().set_keepalive(30)  # mantem a sessao viva enquanto ociosa
        except Exception: pass
        self.port = int(port); self._cred = (host, int(port), user, pwd)  # so em memoria, para reconectar se cair
        ch = c.invoke_shell(term="vt100", width=400, height=2000)
        ch.settimeout(0.3)
        self.client, self.chan, self.host, self.user = c, ch, host, user
        # espera o prompt do shell (fim com $ # > ou %)
        txt, ok = self.read_until(lambda t: re.search(r"[\$#>%]\s*$", t), maxsec=45, idle=1.2)
        lines = [l for l in txt.split("\n") if l.strip()]
        self.prompt = (lines[-1] if lines else "").rstrip()
        self.banner = "\n".join(lines[-15:])
        if not ok:
            logf("login sem prompt claro: " + repr(txt[-300:]))
        # desliga cores e paginacao no shell (ignora se nao for bash)
        self._after_shell()
        logf("login %s@%s:%s prompt=%r" % (user, host, port, self.prompt))
        return {"prompt": self.prompt, "banner": self.banner}

    def _after_shell(self):
        self.chan.send("export TERM=dumb PAGER=cat LESS= 2>/dev/null; stty -echoctl 2>/dev/null\n")
        self.read_until(self.shell_done, maxsec=10, idle=0.6)

    def transport(self):
        c = self.client or (SESS.get(getattr(self, "lane_of", "") or "") or Session()).client
        t = c.get_transport() if c else None
        if not t or not t.is_active(): raise RuntimeError("conexao SSH indisponivel para copiar o arquivo")
        return t

    def run_exec(self, cmd, maxsec=600, limit=400 * 1024 * 1024):
        """Roda um comando num canal separado (sem pty) e devolve os bytes da saida (ex.: cat de um .zip)."""
        ch = self.transport().open_session(); ch.settimeout(30); ch.exec_command(cmd)
        buf, t0 = [], time.time(); n = 0
        while time.time() - t0 < maxsec:
            try: d = ch.recv(1 << 20)
            except Exception: d = None
            if d is None:
                if ch.exit_status_ready() and not ch.recv_ready(): break
                continue
            if not d: break
            buf.append(d); n += len(d)
            if n > limit: ch.close(); raise RuntimeError("arquivo maior que %d MB" % (limit >> 20))
        ch.close(); return b"".join(buf)

    def open_lane(self, main):
        """Abre mais um terminal no mesmo servidor (outro canal na mesma conexao SSH, como outra aba do WinFiol)."""
        self.logout(); self._cred = main._cred; self.host, self.user, self.port = main.host, main.user, main.port
        t = main.client.get_transport() if (main.client and main.logged) else None
        if not t or not t.is_active():
            if not main._cred: raise RuntimeError("servidor %s nao conectado" % main.name)
            return self.login(*main._cred)
        try:
            ch = t.open_session(); ch.get_pty(term="vt100", width=400, height=2000); ch.invoke_shell(); ch.settimeout(0.3)
        except Exception as e:  # servidor nao aceita outro canal na mesma conexao: faz outro login
            logf("canal extra recusado (%s): novo login" % e); return self.login(*main._cred)
        self.chan = ch; self.client = None  # a conexao e do terminal principal
        txt, ok = self.read_until(lambda x: re.search(r"[\$#>%]\s*$", x), maxsec=30, idle=1.2)
        if not ok:
            logf("canal extra sem prompt: novo login"); self.logout(); return self.login(*main._cred)
        lines = [l for l in txt.split("\n") if l.strip()]
        self.prompt = (lines[-1] if lines else main.prompt).rstrip()
        self._after_shell(); logf("terminal extra %s prompt=%r" % (self.key, self.prompt))

    def logout(self):
        try:
            if self.chan: self.chan.close()
            if self.client: self.client.close()
        except Exception:
            pass
        self.client = self.chan = None; self.prompt = ""; self.cur_node = None; self.lt_done = False; self.depth = 0

    def forget(self):
        self.logout(); self._cred = None

    def ensure(self, job=None):
        """Se a sessao caiu (rede/VPN), reconecta com as credenciais guardadas em memoria."""
        if self.logged: return
        if getattr(self, "lane_of", None):
            main = SESS.get(self.lane_of)
            if not main: raise RuntimeError("servidor nao conectado: faca o login de novo")
            if job is not None: job["log"].append("Abrindo terminal extra em %s." % main.name)
            return self.open_lane(main)
        if not self._cred: raise RuntimeError("servidor %s nao conectado: faca o login de novo" % (self.name or self.key))
        if job is not None: job["log"].append("Sessao com %s tinha caido: reconectando..." % (self.name or self.key))
        h, pt, u, pw = self._cred; self.login(h, pt, u, pw)
        if job is not None: job["log"].append("Reconectado.")

    def info(self):
        return {"key": self.key, "name": self.name, "host": self.host, "port": self.port, "user": self.user, "logged": self.logged, "prompt": self.prompt,
                "curNode": (self.cur_node or "") if self.logged else "", "depth": self.depth, "busy": any(j["state"] in ("running", "ask") and j.get("server") == self.key for j in JOBS.values())}

    @property
    def logged(self):
        return bool(self.chan) and not self.chan.closed

    def shell_done(self, tail):
        last = tail.rstrip("\n").split("\n")[-1]
        if self.prompt and last.strip() == self.prompt.strip():
            return "shell"
        return "shell" if re.search(r"[\$#%]\s*$", last) else None

    # ---------- comandos no shell ----------
    def shell(self, cmd, maxsec=120, job=None):
        self.chan.send(cmd + "\n")
        out, _ = self.read_until(self.shell_done, maxsec=maxsec, idle=0.5, job=job)
        return out

    def upload(self, name, text, job=None):
        """Grava um arquivo no HOME do servidor via heredoc (nao depende de SFTP)."""
        safe = re.sub(r"[^\w.\-]", "_", name)[:80] or "script.mos"
        path = "~/.enmhelper/" + safe
        body = text.replace("\r\n", "\n").replace("\r", "\n")
        if "__ENMHELPER_EOF__" in body:
            raise RuntimeError("o arquivo contem o marcador reservado __ENMHELPER_EOF__")
        self.shell("mkdir -p ~/.enmhelper", 20, job)
        # envia em pedacos para nao estourar o buffer do terminal
        self.chan.send("cat > %s <<'__ENMHELPER_EOF__'\n" % path)
        for i in range(0, len(body), 2000):
            self.chan.send(body[i:i + 2000]); time.sleep(0.03)
        if not body.endswith("\n"): self.chan.send("\n")
        self.chan.send("__ENMHELPER_EOF__\n")
        self.read_until(self.shell_done, maxsec=60, idle=0.6, job=job, keep=False)
        chk = self.shell("wc -l < %s" % path, 20, job)
        return path, chk


JOBS = {}
SESS = {}  # "host:porta" -> Session (uma sessao SSH por servidor, todas conectadas ao mesmo tempo)
_TL = threading.local()


class _Cur:
    """S.<x> = sessao da execucao atual (cada job/requisicao escolhe a sua)."""
    def __getattr__(self, n): return getattr(_TL.s, n)
    def __setattr__(self, n, v): setattr(_TL.s, n, v)


S = _Cur()


def use(key):
    s = SESS.get(key)
    if s is None: raise RuntimeError("servidor nao conectado: faca o login")
    _TL.s = s; return s


def lane_key(key, lane):
    """lane 0 = terminal principal; 1, 2... = terminais extras no mesmo servidor (sites ao mesmo tempo)."""
    lane = int(lane or 0)
    if lane <= 0: return key
    main = SESS.get(key)
    if main is None: raise RuntimeError("servidor nao conectado: faca o login")
    lk = "%s#%d" % (key, lane)
    if lk not in SESS:
        s = Session(); s.key = lk; s.name = "%s #%d" % (main.name, lane + 1); s.lane_of = key; SESS[lk] = s
    return lk


def pick(d):
    key = d.get("server") or d.get("key")
    if not key:
        on = [k for k, v in SESS.items() if v.logged]
        if len(on) == 1: key = on[0]
        else: raise RuntimeError("informe o servidor (ha %d conectados)" % len(on))
    return key


def busy(key=None):
    return any(j["state"] in ("running", "ask") and (key is None or j.get("server") == key) for j in JOBS.values())


def amos_prompt(node):
    pat = re.compile(r"^\s*(%s|[\w.\-]+)(\([^)]*\))?>\s*$" % re.escape(node), re.I)
    def done(tail):
        last = tail.rstrip("\n").split("\n")[-1]
        if S.prompt and last.strip() == S.prompt.strip(): return "shell"
        m = pat.match(last)
        if m: S.last_amos = m.group(1); return "amos"
        if PWD_RE.search(last): return "pwd"
        if USER_RE.search(last): return "user"
        if ASK_RE.search(tail[-200:]): return "ask"
        # antes: qualquer linha terminando em $ ou # (ex.: "#####" do pmxet/lt all) era tomada como "AMOS fechou"
        if SHELL_RE.match(last): return "shell"
        return None
    return done


class NodeAuth:
    """Responde usuario/senha do no quando o AMOS pede (nos a partir da 5212). Nunca grava nem loga a senha."""
    def __init__(self, job, node):
        p = job["params"]; self.job = job; self.node = node
        self.user = (p.get("nodeUser") or "").strip(); self.pwds = [x for x in (p.get("nodePwds") or []) if x]
        first = NODE_PWD_OK.get(node.upper(), NODE_PWD_OK.get("*"))
        self.order = ([first] if first is not None and first < len(self.pwds) else []) + [i for i in range(len(self.pwds)) if i != first]
        self.tries = 0; self.cur = None; self.bad = set()

    def handle(self, r):
        if r == "user":
            if not self.user:
                raise RuntimeError("o no pediu usuario e nenhum foi informado na aba 07 (Credenciais do no).")
            self.job["log"].append("O no pediu usuario: enviando '%s'." % self.user)
            S.chan.send(self.user + "\n"); return True
        if r == "pwd":
            if self.cur is not None:  # pediu senha de novo: a anterior foi recusada
                self.bad.add(self.cur); self.job["log"].append("Senha %d recusada pelo no." % (self.cur + 1)); self.cur = None
            if self.tries >= len(self.order):
                raise RuntimeError("o no pediu senha e nenhuma das %d senhas cadastradas funcionou." % len(self.pwds) if self.pwds else
                                   "o no pediu senha e nenhuma foi cadastrada na aba 07 (Credenciais do no).")
            self.cur = self.order[self.tries]; self.tries += 1
            self.job["log"].append("O no pediu senha: tentando a senha %d de %d." % (self.cur + 1, len(self.pwds)))
            S.chan.send(self.pwds[self.cur] + "\n"); return True
        return False

    def verdict(self, txt):
        """Chamado quando o prompt do AMOS volta. O moshell volta ao prompt mesmo quando a senha falha,
        entao so conta como aceita se nao houver mensagem de falha depois da senha."""
        if self.cur is None:
            return "fail" if (self.bad and AUTH_FAIL_RE.search(txt or "")) else "none"
        m = AUTH_FAIL_RE.search(txt or "")
        if m:
            line = [l for l in (txt or "").split("\n") if AUTH_FAIL_RE.search(l)][:1]
            self.bad.add(self.cur); self.job["log"].append("Senha %d recusada pelo no (%s)." % (self.cur + 1, (line[0].strip()[:120] if line else m.group(0))))
            self.cur = None
            return "retry" if self.tries < len(self.order) else "fail"
        NODE_PWD_OK[self.node.upper()] = self.cur; NODE_PWD_OK["*"] = self.cur
        self.job["log"].append("Senha %d aceita pelo no." % (self.cur + 1)); self.cur = None
        return "ok"

    def ok(self):
        return self.verdict("")


def really_shell(node, job, out):
    """Confere se o AMOS fechou mesmo: manda Enter e ve qual prompt volta."""
    S.chan.send("\n"); txt, r = S.read_until(amos_prompt(node), maxsec=20, idle=0.8, job=job); out.append(txt)
    if r == "amos": job["log"].append("(o AMOS continuava aberto; seguindo)")
    return r != "amos"


def close_amos(job=None, out=None):
    """Sai do AMOS (q) e volta ao prompt do servidor."""
    if not S.cur_node: return
    if job is not None: job["log"].append("Fechando AMOS em %s." % S.cur_node)
    # cada troca com "!amos <no>" abre um AMOS dentro do anterior: um q por nivel ate o prompt do servidor
    for _ in range(max(1, S.depth) + 2):
        S.chan.send("q\n")
        txt, r = S.read_until(amos_prompt(S.cur_node), maxsec=40, idle=0.6, job=job)
        if out is not None: out.append(txt)
        if r == "shell": break
    S.cur_node = None; S.lt_done = False; S.depth = 0


def paste_script(job, node, auth, out, p):
    """Envia um script linha a linha, como colar no WinFiol: cada linha sai quando o AMOS volta ao prompt,
    pergunta algo (a linha seguinte do script responde) ou fica quieto. {{SENHA_NO}} e {{SENHA_OSS}} sao
    trocados aqui e mascarados na saida e no log."""
    text = p.get("paste") or ""
    pw_node = None
    if "{{SENHA_NO}}" in text:
        idx = NODE_PWD_OK.get(node.upper())
        if idx is None and auth.pwds:
            job["log"].append("Descobrindo a senha do no %s (lt all) para preencher {{SENHA_NO}}..." % node)
            S.chan.send("lt all\n"); since = ""; retries = 0
            while True:
                txt, r = S.read_until(amos_prompt(node), maxsec=900, idle=0.6, job=job); out.append(txt); since += txt
                if auth.handle(r): continue
                if r == "amos":
                    v = auth.verdict(since)
                    if v == "retry" and retries < len(auth.pwds): retries += 1; since = ""; S.chan.send("lt all\n"); continue
                    if v in ("fail", "retry"): raise RuntimeError("nenhuma senha do no funcionou em %s; {{SENHA_NO}} nao pode ser preenchida." % node)
                    S.lt_done = True
                break
            idx = NODE_PWD_OK.get(node.upper())
            if idx is None and auth.pwds:
                idx = NODE_PWD_OK.get("*", 0)
                job["log"].append("O no nao pediu senha; usando a senha %d para {{SENHA_NO}}." % (idx + 1))
        if idx is None or not auth.pwds:
            raise RuntimeError("o script usa {{SENHA_NO}} e nao ha senhas do no cadastradas na aba 07.")
        pw_node = auth.pwds[idx]
    pw_oss = S._cred[3] if (S._cred and "{{SENHA_OSS}}" in text) else None
    job["_secrets"] = [x for x in (pw_node, pw_oss) if x] + list(auth.pwds)
    lines = text.replace("\r\n", "\n").split("\n")
    while lines and not lines[-1].strip(): lines.pop()
    job["total"] = job.get("step", 0) + len(lines); per = p.get("timeout", 1800)
    for raw in lines:
        if job.get("stop"):
            job["log"].append("Parado pelo usuario."); break
        line = raw.rstrip()
        shown = line.replace("{{SENHA_NO}}", "******").replace("{{SENHA_OSS}}", "******")
        if pw_node: line = line.replace("{{SENHA_NO}}", pw_node)
        if pw_oss: line = line.replace("{{SENHA_OSS}}", pw_oss)
        job["step"] += 1
        if shown.strip(): job["log"].append("%s> %s" % (node, shown.strip()))
        S.chan.send(line + "\n")
        txt, r = S.read_until(amos_prompt(node), maxsec=per, idle=0.5, job=job, quiet=25)
        out.append(txt)
        if r == "user" and auth.user:  # o no pediu login no meio do script: responde com usuario/senha do no e segue
            while r in ("user", "pwd"):
                auth.handle(r); txt, r = S.read_until(amos_prompt(node), maxsec=per, idle=0.5, job=job, quiet=25); out.append(txt)
            if r == "amos": auth.verdict(txt)
        if r == "shell" and really_shell(node, job, out):
            raise RuntimeError("o AMOS fechou durante '%s'" % shown.strip())
        if r is None:
            raise RuntimeError("tempo esgotado em '%s'" % shown.strip())
        if line.strip().lower() == "lt all" and r == "amos": S.lt_done = True


def home_path(p):
    """'~/dcgk/x' -> "$HOME"/'dcgk/x' (com aspas seguras)."""
    p = p.strip()
    if p.startswith("~/"): return '"$HOME"/' + shlex.quote(p[2:])
    if p == "~": return '"$HOME"'
    return shlex.quote(p)


def fetch_dirs(p):
    """Pastas onde o dcgk grava. {user} vira o usuario do servidor (ex.: /home/shared/{user}/dcgk)."""
    v = p.get("fetchDir") or []
    ds = [v] if isinstance(v, str) else list(v)
    out = []
    for d in ds:
        d = (d or "").replace("{user}", S.user or "").strip()
        if d and d not in out: out.append(d)
    return out


def fetch_files(job, node, dirs, mark, text):
    """Depois do dcgk: acha os arquivos novos do no nas pastas e copia para a pagina."""
    found = []
    for m in re.finditer(r"((?:~|/)[\w.@/\-]+\.(?:zip|gz|log|txt|tgz|tar))", text or ""):
        x = m.group(1)
        if node.upper() in x.upper() and x not in found: found.append(x)
    lst = []
    for x in S.run_exec("find %s -maxdepth 2 -type f -newer %s 2>/dev/null" % (" ".join(home_path(d) for d in dirs), home_path(mark)), 60).decode("utf-8", "ignore").split():
        if not any(os.path.basename(x) == os.path.basename(y) for y in lst): lst.append(x)
    d = " ou ".join(dirs)
    mine = [x for x in lst if node.upper() in os.path.basename(x).upper()] or lst
    for x in mine:
        if x not in found and not any(os.path.basename(x) == os.path.basename(f) for f in found): found.append(x)
    zips = [x for x in found if x.lower().endswith(".zip")]
    pick = zips[:3] if zips else found[:6]
    if not pick:
        job["log"].append("Nenhum arquivo novo do no em %s." % d); return
    job["files"] = []
    for x in pick:
        job["log"].append("Copiando %s para a pagina..." % x)
        data = S.run_exec("cat %s" % home_path(x), 900)
        if not data: job["log"].append("(vazio ou sem permissao: %s)" % x); continue
        job["files"].append({"name": os.path.basename(x), "path": x, "data": data})
        job["log"].append("Arquivo recebido: %s (%.1f MB)." % (os.path.basename(x), len(data) / 1048576.0))


def run_job(job):
    """Executa um job: abre o AMOS no no, roda os comandos um a um e fecha."""
    p = job["params"]; node = p.get("node", "").strip(); out = []
    try:
        use(job["server"])
        with S.lock:
            S.ensure(job)
            cmds = [c for c in p.get("cmds", []) if c.strip() and not c.strip().startswith("//")]
            if p.get("kind") == "shell":
                for c in cmds:
                    job["step"] += 1; job["log"].append("$ " + c)
                    out.append(S.shell(c, p.get("timeout", 120), job))
                job["state"] = "done"; return
            keep = p.get("keepOpen", True)
            open_tpl = (p.get("openCmd") or "amos {node}").strip(); switch_tpl = (p.get("switchCmd") or "!amos {node}").strip()
            if p.get("upload"):
                if S.cur_node:  # o upload precisa do shell do servidor
                    close_amos(job, out)
                up = p["upload"]; job["log"].append("Enviando %s para o servidor..." % up["name"])
                path, chk = S.upload(up["name"], up["text"], job)
                job["log"].append("Arquivo gravado em %s (%s linhas)." % (path, re.sub(r"\D", "", chk.split("\n")[-2] if "\n" in chk else chk) or "?"))
                cmds = cmds + ["run " + path]
            auth = NodeAuth(job, node)
            same = S.cur_node and S.cur_node.upper() == node.upper()
            if same and S.lt_done and cmds and cmds[0].strip().lower() == "lt all":
                cmds = cmds[1:]; job["log"].append("lt all ja carregado nesta sessao de %s: pulando." % node)
            job["total"] = len(cmds) + 1
            r = None
            if same:
                job["log"].append("AMOS ja aberto em %s." % node)
                S.chan.send("\n"); txt, r = S.read_until(amos_prompt(node), maxsec=15, idle=0.4, job=job); out.append(txt)
                if r != "amos":
                    job["log"].append("Sessao do no nao respondeu; reabrindo."); S.cur_node = None; same = False
            if not same and S.cur_node and S.depth >= 5:
                job["log"].append("%d AMOS empilhados: fechando todos antes de abrir %s." % (S.depth, node)); close_amos(job, out)
            if not same:
                switching = bool(S.cur_node)
                if S.cur_node:
                    cmd = switch_tpl.replace("{node}", node).replace("{no}", node)
                    job["log"].append("Trocando de %s para %s: %s" % (S.cur_node, node, cmd))
                else:
                    cmd = open_tpl.replace("{node}", node).replace("{no}", node)
                    job["log"].append("Abrindo AMOS em %s: %s" % (node, cmd))
                S.chan.send(cmd + "\n")
                while True:
                    txt, r = S.read_until(amos_prompt(node), maxsec=p.get("openTimeout", 240), idle=0.8, job=job)
                    out.append(txt)
                    if auth.handle(r): continue
                    break
                if r == "amos" and S.last_amos and S.last_amos.upper() != node.upper() and S.cur_node and S.last_amos.upper() == S.cur_node.upper():
                    r = "same-old"
                if r != "amos" and S.cur_node:
                    # a troca nao funcionou: fecha o no atual e abre o novo do jeito normal
                    job["log"].append("A troca com '%s' nao abriu %s; fechando %s e abrindo de novo." % (cmd, node, S.cur_node))
                    close_amos(job, out)
                    cmd = open_tpl.replace("{node}", node).replace("{no}", node); job["log"].append("Abrindo AMOS em %s: %s" % (node, cmd))
                    S.chan.send(cmd + "\n")
                    while True:
                        txt, r = S.read_until(amos_prompt(node), maxsec=p.get("openTimeout", 240), idle=0.8, job=job)
                        out.append(txt)
                        if auth.handle(r): continue
                        break
                if r == "amos" and auth.verdict(txt) in ("fail", "retry"):
                    raise RuntimeError("o no recusou a senha ao abrir o AMOS em %s." % node)
                if r == "amos":
                    S.depth = (S.depth + 1) if (switching and S.cur_node) else 1; S.cur_node = node; S.lt_done = False
                    if S.depth > 1: job["log"].append("AMOS de %s aberto dentro da sessao anterior (nivel %d)." % (node, S.depth))
                else:
                    S.cur_node = None
                    raise RuntimeError("o AMOS nao abriu em %s. Ultimas linhas: %s" % (node, txt.strip()[-400:]))
            mark = None
            dirs = fetch_dirs(p) if p.get("fetchDir") else []
            if dirs:
                mark = "~/.enmhelper/mark_" + job["id"]
                try: S.run_exec("mkdir -p ~/.enmhelper && touch %s" % home_path(mark), 30)
                except Exception as e: job["log"].append("Aviso: nao preparei a copia do arquivo (%s)." % e); mark = None
            if p.get("paste"):
                paste_script(job, node, auth, out, p)
                cmds = []
            else:
                job["step"] = 1
            for c in cmds:
                if job.get("stop"):
                    job["log"].append("Parado pelo usuario."); break
                job["step"] += 1; job["log"].append("%s> %s" % (node, c))
                S.chan.send(c + "\n"); since = ""; retries = 0
                while True:
                    txt, r = S.read_until(amos_prompt(node), maxsec=p.get("timeout", 1800), idle=0.6, job=job)
                    out.append(txt); since += txt
                    if auth.handle(r): continue
                    if r == "amos":
                        v = auth.verdict(since)
                        if v == "retry" and retries < len(auth.pwds):
                            retries += 1; since = ""
                            job["log"].append("O no recusou a senha e voltou ao prompt: repetindo '%s' com a proxima senha." % c)
                            S.chan.send(c + "\n"); continue
                        if v in ("fail", "retry"):
                            msg = [l.strip() for l in since.split("\n") if AUTH_FAIL_RE.search(l)][:1]
                            raise RuntimeError("o no recusou todas as %d senhas cadastradas%s." % (len(auth.pwds), (": " + msg[0][:160]) if msg else ""))
                        if c.strip().lower() == "lt all" and not AUTH_FAIL_RE.search(since): S.lt_done = True
                    if r == "ask":
                        job["state"] = "ask"; job["question"] = txt.strip()[-300:]; job["answer"] = None
                        t0 = time.time()
                        while job["answer"] is None and time.time() - t0 < 900 and not job.get("stop"):
                            time.sleep(0.2)
                        ans = job["answer"] if job["answer"] is not None else "n"
                        job["log"].append("Resposta: " + ans); job["state"] = "running"; job["question"] = ""
                        S.chan.send(ans + "\n"); continue
                    if r == "shell" and really_shell(node, job, out):
                        raise RuntimeError("o AMOS fechou durante '%s'" % c)
                    if r == "shell": break
                    if r is None:
                        raise RuntimeError("tempo esgotado esperando o fim de '%s'" % c)
                    break
            if mark and not job.get("stop"):
                try: fetch_files(job, node, dirs, mark, "".join(out))
                except Exception as e: job["log"].append("Nao consegui copiar o arquivo do servidor: %s" % e)
                try: S.run_exec("rm -f %s" % home_path(mark), 20)
                except Exception: pass
            if not keep:
                close_amos(job, out)
            job["state"] = "done"; job["log"].append("Concluido." + (" AMOS continua aberto em %s." % node if keep and S.cur_node else ""))
    except Exception as e:
        job["state"] = "error"; job["error"] = str(e); job["log"].append("ERRO: " + str(e)); logf("job erro: %s" % e)
        try:
            if S.logged:
                S.chan.send("\x03"); time.sleep(0.4)
                for _ in range(max(1, S.depth) + 2):
                    S.chan.send("q\n"); _t, rr = S.read_until(amos_prompt(S.cur_node or node), maxsec=15, idle=0.6)
                    if rr == "shell": break
            S.cur_node = None; S.lt_done = False; S.depth = 0
        except Exception:
            pass
    finally:
        txt = "".join(out)
        for sec in job.get("_secrets", []):
            if sec: txt = txt.replace(sec, "******")
        for sec in job.get("_secrets", []):
            if sec: job["log"] = [l.replace(sec, "******") for l in job["log"]]
        job["out"] = txt; job["end"] = time.time(); job.pop("_secrets", None)


def node_type(txt, asked_user=False):
    """Tipo do no pelo modelo que o AMOS mostra: BB (RadioNode/Baseband), DUS (ERBS/CPP LTE) ou 3G (RBS/CPP WCDMA)."""
    if re.search(r"MSRBS|RadioNode|Baseband", txt or "", re.I) or asked_user: return "BB"
    if re.search(r"\bERBS_NODE_MODEL|\bERBS\b", txt or ""): return "DUS"
    if re.search(r"\bRBS_NODE_MODEL", txt or ""): return "3G"
    return ""


def probe_job(job):
    """Para cada no da lista, ve se ele abre no AMOS deste servidor (amos <no> / !amos <no>, lt root, q).
    Nao altera nada no no. Se ja havia um AMOS aberto, ele continua aberto no fim."""
    p = job["params"]; res = job["result"]; out = []
    try:
        use(job["server"])
        with S.lock:
            S.ensure(job)
            open_tpl = (p.get("openCmd") or "amos {node}").strip(); switch_tpl = (p.get("switchCmd") or "!amos {node}").strip()
            nodes = [n.strip() for n in p.get("nodes", []) if n and n.strip()]
            job["total"] = len(nodes)
            for node in nodes:
                if job.get("stop"): job["log"].append("Parado pelo usuario."); break
                job["step"] += 1
                had = S.cur_node
                auth = NodeAuth(job, node); auth.job = {"log": [], "params": p}  # sem poluir o log com cada senha
                cmd = (switch_tpl if had else open_tpl).replace("{node}", node).replace("{no}", node)
                job["log"].append("[%s] testando %s: %s" % (S.name or S.key, node, cmd))
                S.chan.send(cmd + "\n"); txt = ""; asked = False
                while True:
                    t, r = S.read_until(amos_prompt(node), maxsec=p.get("openTimeout", 90), idle=0.8, job=job); txt += t
                    if r == "user": asked = True
                    try:
                        if auth.handle(r): continue
                    except RuntimeError:
                        S.chan.send("\x03"); t, r = S.read_until(amos_prompt(node), maxsec=15, idle=0.6); txt += t
                    break
                out.append(txt); info = {"found": False, "type": "", "why": ""}
                opened = r == "amos" and S.last_amos and S.last_amos.upper() == node.upper()
                if r == "shell" or r is None:
                    info["why"] = "o AMOS nao abriu" if r == "shell" else "sem resposta"
                    if had: S.cur_node = None; S.depth = 0; S.lt_done = False; had = None
                    if r is None: S.chan.send("\x03"); S.read_until(S.shell_done, maxsec=10, idle=0.5)
                elif not opened:
                    info["why"] = "a troca nao abriu o no"
                else:
                    nf = NOTFOUND_RE.search(txt)
                    if nf and not asked:
                        info["why"] = nf.group(0).strip()[:80]
                    else:
                        txt2 = ""
                        if p.get("deep", True):
                            S.chan.send("lt root\n"); since = ""
                            while True:
                                t, r2 = S.read_until(amos_prompt(node), maxsec=120, idle=0.6, job=job); txt2 += t
                                if r2 == "user": asked = True
                                try:
                                    if auth.handle(r2): continue
                                except RuntimeError:
                                    S.chan.send("\x03"); t, r2 = S.read_until(amos_prompt(node), maxsec=15, idle=0.6); txt2 += t
                                if r2 == "ask": S.chan.send("y\n"); continue
                                break
                            out.append(txt2)
                        bad = NOTFOUND_RE.search(txt2) or (AUTH_FAIL_RE.search(txt2) and not asked)
                        if FOUND_RE.search(txt) or asked or (txt2 and not bad):
                            info["found"] = True; info["type"] = node_type(txt + txt2, asked)
                            if auth.cur is not None and auth.verdict(txt + txt2) in ("fail", "retry"): info["why"] = "senha do no recusada"
                            elif auth.bad and NODE_PWD_OK.get(node.upper()) is None: info["why"] = "senha do no recusada"
                        else:
                            info["why"] = (bad.group(0).strip()[:80] if bad else "sem contato com o no")
                    # volta: um q fecha so este AMOS (o anterior, se havia, continua aberto)
                    S.chan.send("q\n"); t, r3 = S.read_until(amos_prompt(had or node), maxsec=40, idle=0.6); out.append(t)
                    if had and r3 != "amos":
                        S.cur_node = None; S.depth = 0; S.lt_done = False
                    if not had and r3 == "amos":  # ainda no AMOS: fecha mais um nivel
                        S.chan.send("q\n"); S.read_until(amos_prompt(node), maxsec=30, idle=0.6)
                res[node] = info
                job["log"].append("[%s] %s: %s%s" % (S.name or S.key, node, "ENCONTRADO" if info["found"] else "nao esta aqui",
                                  (" (" + info["type"] + ")" if info["type"] else "") + (" - " + info["why"] if info["why"] else "")))
            job["state"] = "done"
    except Exception as e:
        job["state"] = "error"; job["error"] = str(e); job["log"].append("ERRO: " + str(e)); logf("probe erro: %s" % e)
    finally:
        txt = "".join(out)
        for sec in (p.get("nodePwds") or []) + ([S._cred[3]] if getattr(_TL, "s", None) and S._cred else []):
            if sec: txt = txt.replace(sec, "******")
        job["out"] = txt; job["end"] = time.time()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _hdr(self, code=200, ctype="application/json"):
        origin = self.headers.get("Origin")
        self.send_response(code)
        if origin and origin_ok(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Private-Network", "true")  # pagina https -> localhost
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def _json(self, obj, code=200):
        self._hdr(code); self.wfile.write(json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def _guard(self):
        if not origin_ok(self.headers.get("Origin")):
            self._json({"ok": False, "erro": "origem nao autorizada"}, 403); return False
        return True

    def do_OPTIONS(self):
        self._hdr(204)

    def do_GET(self):
        if not self._guard(): return
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == "/":
            ss = []
            for k, v in list(SESS.items()):
                if getattr(v, "lane_of", None): continue
                i = v.info(); ex = [x for x in SESS.values() if getattr(x, "lane_of", None) == k]
                i["lanes"] = sum(1 for x in ex if x.logged); i["busy"] = i["busy"] or any(busy(x.key) for x in ex); ss.append(i)
            first = next((x for x in ss if x["logged"]), {})
            return self._json({"ok": True, "app": "ericsson-helper", "version": VERSION, "sessions": ss, "logged": any(x["logged"] for x in ss),
                               "host": first.get("host", ""), "user": first.get("user", ""), "prompt": first.get("prompt", ""), "curNode": first.get("curNode", ""), "depth": first.get("depth", 0), "busy": busy()})
        if u.path in ("/job", "/job/out", "/job/file"):
            j = JOBS.get((q.get("id") or [""])[0])
            if not j: return self._json({"ok": False, "erro": "job nao encontrado"}, 404)
            if u.path == "/job/file":
                fs = j.get("files") or []; n = int((q.get("n") or ["0"])[0])
                if n >= len(fs): return self._json({"ok": False, "erro": "arquivo nao encontrado"}, 404)
                self._hdr(200, "application/octet-stream"); self.wfile.write(fs[n]["data"]); return
            if u.path == "/job/out":
                self._hdr(200, "text/plain; charset=utf-8"); self.wfile.write(j.get("out", "").encode("utf-8")); return
            since = int((q.get("since") or ["0"])[0])
            return self._json({"ok": True, "state": j["state"], "step": j["step"], "total": j["total"], "bytes": j.get("bytes", 0), "log": j["log"][since:], "logLen": len(j["log"]),
                               "question": j.get("question", ""), "error": j.get("error", ""), "result": j.get("result"),
                               "files": [{"name": f["name"], "path": f["path"], "size": len(f["data"])} for f in (j.get("files") or [])]})
        self._json({"ok": False, "erro": "rota desconhecida"}, 404)

    def do_POST(self):
        if not self._guard(): return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            d = json.loads(self.rfile.read(n).decode("utf-8") or "{}") if n else {}
        except Exception:
            return self._json({"ok": False, "erro": "JSON invalido"}, 400)
        p = urlparse(self.path).path
        try:
            if p == "/login":
                key = "%s:%s" % (d["host"], int(d.get("port", 5022)))
                if busy(key): return self._json({"ok": False, "erro": "ha uma execucao em andamento neste servidor"})
                for k in [k for k, v in SESS.items() if getattr(v, "lane_of", None) == key and not busy(k)]:
                    x = SESS.pop(k); x.forget()
                sess = SESS.setdefault(key, Session()); sess.key = key; sess.name = d.get("name") or sess.name or d["host"]
                _TL.s = sess
                with sess.lock:
                    r = sess.login(d["host"], d.get("port", 5022), d["user"], d["pwd"])
                return self._json({"ok": True, "key": key, **r})
            if p == "/close":
                key = pick(d)
                if busy(key): return self._json({"ok": False, "erro": "ha uma execucao em andamento neste servidor"})
                use(key)
                with S.lock: close_amos()
                return self._json({"ok": True})
            if p == "/logout":
                keys = [d["key"]] if d.get("key") else list(SESS.keys())
                keys = keys + [k for k, v in SESS.items() if getattr(v, "lane_of", None) in keys and k not in keys]
                for k in keys:
                    for j in JOBS.values():
                        if j.get("server") == k: j["stop"] = True
                    sess = SESS.pop(k, None)
                    if sess:
                        with sess.lock: sess.forget()
                return self._json({"ok": True})
            if p == "/job":
                key = pick(d)
                if key not in SESS: return self._json({"ok": False, "erro": "servidor nao conectado: faca o login"})
                key = lane_key(key, d.get("lane"))
                if busy(key):
                    return self._json({"ok": False, "erro": "ja existe uma execucao em andamento neste servidor"})
                cmds = d.get("cmds", [])
                writes = [c for c in cmds if WRITE_RE.match(c)] + (["run " + d["upload"]["name"]] if d.get("upload") else []) + \
                         [l.strip() for l in (d.get("paste") or "").split("\n") if WRITE_RE.match(l)]
                if writes and not d.get("confirmWrites"):
                    return self._json({"ok": False, "needConfirm": True, "writes": writes[:50], "erro": "comandos de alteracao precisam de confirmacao"})
                jid = uuid.uuid4().hex[:10]
                job = {"id": jid, "server": key, "params": d, "state": "running", "step": 0, "total": len(cmds), "log": [], "start": time.time()}
                JOBS[jid] = job
                for k in [k for k, v in JOBS.items() if v is not job and v["state"] in ("done", "error") and time.time() - v.get("end", 0) > 1800]:
                    JOBS.pop(k, None)
                threading.Thread(target=run_job, args=(job,), daemon=True).start()
                return self._json({"ok": True, "id": jid})
            if p == "/probe":
                key = pick(d)
                if key not in SESS: return self._json({"ok": False, "erro": "servidor nao conectado: faca o login"})
                if busy(key): return self._json({"ok": False, "erro": "ja existe uma execucao em andamento neste servidor"})
                jid = uuid.uuid4().hex[:10]
                job = {"id": jid, "server": key, "params": d, "state": "running", "step": 0, "total": len(d.get("nodes", [])), "log": [], "result": {}, "start": time.time()}
                JOBS[jid] = job
                threading.Thread(target=probe_job, args=(job,), daemon=True).start()
                return self._json({"ok": True, "id": jid})
            if p == "/job/answer":
                j = JOBS.get(d.get("id"))
                if j: j["answer"] = "y" if str(d.get("answer", "")).lower().startswith("y") else "n"
                return self._json({"ok": bool(j)})
            if p == "/job/stop":
                j = JOBS.get(d.get("id"))
                if j:
                    j["stop"] = True
                    if d.get("now"): j["kill"] = True
                return self._json({"ok": bool(j)})
        except Exception as e:
            logf("erro %s: %s" % (p, e))
            return self._json({"ok": False, "erro": str(e)})
        self._json({"ok": False, "erro": "rota desconhecida"}, 404)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=LOCAL_PORT)
    ap.add_argument("url", nargs="?")  # chamado pelo link enmhelper:// (ignorado)
    a = ap.parse_args()
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    except OSError:
        print("Helper ja esta rodando na porta %d." % a.port); return
    print("Helper Ericsson v%s em http://127.0.0.1:%d  (Ctrl+C para sair)" % (VERSION, a.port))
    logf("iniciado v%s porta %d" % (VERSION, a.port))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
'@
[IO.File]::WriteAllText($py_file, $code, (New-Object Text.UTF8Encoding($false)))
Write-Host "Helper copiado para $dir"

# 3) Inicia sozinho com o Windows (atalho na pasta Inicializar, sem janela)
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($lnk)
$s.TargetPath = $pyw
$s.Arguments = '"' + $py_file + '"'
$s.WorkingDirectory = $dir
$s.WindowStyle = 7
$s.Description = 'Helper Ericsson (Ferramenta Ericsson RAN)'
$s.Save()
Write-Host 'Inicializacao automatica: OK'

# 4) Link enmhelper:// (botao "Iniciar helper" da pagina, caso ele tenha sido fechado)
foreach ($k in @($reg, "$reg\shell", "$reg\shell\open", "$reg\shell\open\command")) {
  if (-not (Test-Path $k)) { New-Item -Path $k | Out-Null }
}
Set-ItemProperty -Path $reg -Name '(default)' -Value 'URL:Helper Ericsson'
Set-ItemProperty -Path $reg -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$reg\shell\open\command" -Name '(default)' -Value ('"' + $pyw + '" "' + $py_file + '" "%1"')
Write-Host 'Botao "Iniciar helper" da pagina: OK'

# 5) Liga agora e testa
Start-Process -FilePath $pyw -ArgumentList ('"' + $py_file + '"') -WorkingDirectory $dir -WindowStyle Hidden
$ok = $false
for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
  Start-Sleep -Milliseconds 700
  try { $r = Invoke-RestMethod -Uri 'http://127.0.0.1:8766/' -TimeoutSec 2; $ok = $true } catch {}
}
Write-Host ''
if ($ok) {
  Write-Host ("PRONTO! Helper v" + $r.version + " rodando. Ele vai iniciar sozinho sempre que o Windows ligar.") -ForegroundColor Green
  Write-Host 'Pode fechar esta janela e voltar para a Ferramenta Ericsson RAN.'
} else {
  Write-Host 'Instalado, mas o helper nao respondeu. Veja o arquivo:' -ForegroundColor Yellow
  Write-Host (Join-Path $dir 'helper.log')
}
