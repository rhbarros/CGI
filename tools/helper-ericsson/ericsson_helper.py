# ericsson_helper.py - Ponte Ferramenta Ericsson RAN (navegador) <-> servidor OSS/ENM (SSH) <-> AMOS
#
# O navegador nao abre SSH; este helper roda no PC e faz a ponte:
#   index2.html --HTTP--> 127.0.0.1:8766 (este helper) --SSH--> servidor OSS (porta 5022) --> amos <no>
#
# Uso:  python ericsson_helper.py            (porta local 8766)
#       python ericsson_helper.py --port 8766
#
# Usuario e senha chegam da pagina e ficam SO na memoria deste processo (nunca em disco).
import argparse, json, os, re, sys, threading, time, uuid
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.0"
LOCAL_PORT = 8766
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "helper.log")

# Paginas que podem usar o helper. Qualquer outro site e recusado.
ALLOWED_ORIGINS = {"https://rhbarros.github.io", "null"}
LOCAL_ORIGIN = re.compile(r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$")
WRITE_RE = re.compile(r"^\s*(set|sete|crn|cr|del|rdel|bl|deb|acc|run|ldeb|lbl|lset|lcr|ldel|restart|rbs|confb\+?|trun|pol|upgrade|cvms|cvmk|cvrm|cvset)\b", re.I)
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[=>()][0-9A-Za-z]?")
ASK_RE = re.compile(r"(\[y/n\]|\(y/n\)|\[yes/no\]|\(yes/no\)|y/n\]?|are you sure[^\n]*|continue\?)\s*[:?]?\s*$", re.I)
PWD_RE = re.compile(r"(password|senha)\s*:\s*$", re.I)


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

    # ---------- leitura ----------
    def read_until(self, done, maxsec=60, idle=0.35, job=None, keep=True):
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
        self.chan.send("export TERM=dumb PAGER=cat LESS= 2>/dev/null; stty -echoctl 2>/dev/null\n")
        self.read_until(self.shell_done, maxsec=10, idle=0.6)
        logf("login %s@%s:%s prompt=%r" % (user, host, port, self.prompt))
        return {"prompt": self.prompt, "banner": self.banner}

    def logout(self):
        try:
            if self.chan: self.chan.close()
            if self.client: self.client.close()
        except Exception:
            pass
        self.client = self.chan = None; self.prompt = ""

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


S = Session()
JOBS = {}


def amos_prompt(node):
    pat = re.compile(r"^\s*(%s|[\w.\-]+)(\([^)]*\))?>\s*$" % re.escape(node), re.I)
    def done(tail):
        last = tail.rstrip("\n").split("\n")[-1]
        if S.prompt and last.strip() == S.prompt.strip(): return "shell"
        if pat.match(last): return "amos"
        if ASK_RE.search(tail[-200:]): return "ask"
        if PWD_RE.search(last): return "pwd"
        if re.search(r"[\$#]\s*$", last): return "shell"
        return None
    return done


def run_job(job):
    """Executa um job: abre o AMOS no no, roda os comandos um a um e fecha."""
    p = job["params"]; node = p.get("node", "").strip(); out = []
    try:
        with S.lock:
            if not S.logged:
                raise RuntimeError("helper nao conectado ao servidor: faca o login de novo")
            cmds = [c for c in p.get("cmds", []) if c.strip() and not c.strip().startswith("//")]
            if p.get("kind") == "shell":
                for c in cmds:
                    job["step"] += 1; job["log"].append("$ " + c)
                    out.append(S.shell(c, p.get("timeout", 120), job))
                job["state"] = "done"; return
            if p.get("upload"):
                up = p["upload"]; job["log"].append("Enviando %s para o servidor..." % up["name"])
                path, chk = S.upload(up["name"], up["text"], job)
                job["log"].append("Arquivo gravado em %s (%s linhas)." % (path, re.sub(r"\D", "", chk.split("\n")[-2] if "\n" in chk else chk) or "?"))
                cmds = cmds + ["run " + path]
            job["total"] = len(cmds) + 1
            job["log"].append("Abrindo AMOS em %s..." % node)
            S.chan.send("amos %s\n" % node)
            txt, r = S.read_until(amos_prompt(node), maxsec=p.get("openTimeout", 240), idle=0.8, job=job)
            out.append(txt)
            if r == "pwd":
                raise RuntimeError("o AMOS pediu senha do no. Abra o AMOS uma vez pelo WinFiol para gravar a senha e tente de novo.")
            if r != "amos":
                raise RuntimeError("o AMOS nao abriu em %s. Ultimas linhas: %s" % (node, txt.strip()[-400:]))
            job["step"] = 1
            for c in cmds:
                if job.get("stop"):
                    job["log"].append("Parado pelo usuario."); break
                job["step"] += 1; job["log"].append("%s> %s" % (node, c))
                S.chan.send(c + "\n")
                while True:
                    txt, r = S.read_until(amos_prompt(node), maxsec=p.get("timeout", 1800), idle=0.6, job=job)
                    out.append(txt)
                    if r == "ask":
                        job["state"] = "ask"; job["question"] = txt.strip()[-300:]; job["answer"] = None
                        t0 = time.time()
                        while job["answer"] is None and time.time() - t0 < 900 and not job.get("stop"):
                            time.sleep(0.2)
                        ans = job["answer"] if job["answer"] is not None else "n"
                        job["log"].append("Resposta: " + ans); job["state"] = "running"; job["question"] = ""
                        S.chan.send(ans + "\n"); continue
                    if r == "shell":
                        raise RuntimeError("o AMOS fechou durante '%s'" % c)
                    if r is None:
                        raise RuntimeError("tempo esgotado esperando o fim de '%s'" % c)
                    break
            S.chan.send("q\n")
            txt, _ = S.read_until(S.shell_done, maxsec=40, idle=0.6, job=job)
            job["state"] = "done"; job["log"].append("Concluido.")
    except Exception as e:
        job["state"] = "error"; job["error"] = str(e); job["log"].append("ERRO: " + str(e)); logf("job erro: %s" % e)
        try:
            if S.logged:
                S.chan.send("\x03"); time.sleep(0.4); S.chan.send("q\n")
                S.read_until(S.shell_done, maxsec=15, idle=0.6)
        except Exception:
            pass
    finally:
        job["out"] = "".join(out); job["end"] = time.time()


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
            return self._json({"ok": True, "app": "ericsson-helper", "version": VERSION, "logged": S.logged, "host": S.host, "user": S.user, "prompt": S.prompt,
                               "busy": any(j["state"] in ("running", "ask") for j in JOBS.values())})
        if u.path in ("/job", "/job/out"):
            j = JOBS.get((q.get("id") or [""])[0])
            if not j: return self._json({"ok": False, "erro": "job nao encontrado"}, 404)
            if u.path == "/job/out":
                self._hdr(200, "text/plain; charset=utf-8"); self.wfile.write(j.get("out", "").encode("utf-8")); return
            since = int((q.get("since") or ["0"])[0])
            return self._json({"ok": True, "state": j["state"], "step": j["step"], "total": j["total"], "bytes": j.get("bytes", 0), "log": j["log"][since:], "logLen": len(j["log"]),
                               "question": j.get("question", ""), "error": j.get("error", "")})
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
                if any(j["state"] in ("running", "ask") for j in JOBS.values()):
                    return self._json({"ok": False, "erro": "ha uma execucao em andamento"})
                with S.lock:
                    r = S.login(d["host"], d.get("port", 5022), d["user"], d["pwd"])
                return self._json({"ok": True, **r})
            if p == "/logout":
                for j in JOBS.values(): j["stop"] = True
                with S.lock: S.logout()
                return self._json({"ok": True})
            if p == "/job":
                if any(j["state"] in ("running", "ask") for j in JOBS.values()):
                    return self._json({"ok": False, "erro": "ja existe uma execucao em andamento"})
                cmds = d.get("cmds", [])
                writes = [c for c in cmds if WRITE_RE.match(c)] + (["run " + d["upload"]["name"]] if d.get("upload") else [])
                if writes and not d.get("confirmWrites"):
                    return self._json({"ok": False, "needConfirm": True, "writes": writes[:50], "erro": "comandos de alteracao precisam de confirmacao"})
                jid = uuid.uuid4().hex[:10]
                job = {"id": jid, "params": d, "state": "running", "step": 0, "total": len(cmds), "log": [], "start": time.time()}
                JOBS[jid] = job
                for k in [k for k, v in JOBS.items() if v is not job and v["state"] in ("done", "error") and time.time() - v.get("end", 0) > 1800]:
                    JOBS.pop(k, None)
                threading.Thread(target=run_job, args=(job,), daemon=True).start()
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
