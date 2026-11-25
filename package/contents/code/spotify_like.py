#!/usr/bin/env python3
"""Helper do widget Spotify Disc: autenticação e "curtir" via Spotify Web API.

Uso:
    spotify_like.py auth <client_id>   # abre o navegador e salva o token
    spotify_like.py status [track_id]  # {"liked": bool, "trackId": ...}
    spotify_like.py toggle [track_id]  # alterna curtida e devolve o novo estado

Sempre imprime uma linha JSON no stdout. Sem dependências externas.
"""
import base64
import hashlib
import html
import http.server
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

REDIRECT_PORT = 8898
REDIRECT_URI = f"http://127.0.0.1:{REDIRECT_PORT}/callback"
SCOPES = "user-library-read user-library-modify"
CONFIG_DIR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "spotifydisc"
)
TOKEN_FILE = os.path.join(CONFIG_DIR, "token.json")
API = "https://api.spotify.com/v1"


def out(obj):
    print(json.dumps(obj), flush=True)
    sys.exit(0)


# ---------------------------------------------------------------- token store
def load_token():
    try:
        with open(TOKEN_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_token(tok):
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    tmp = TOKEN_FILE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(tok, f)
    os.replace(tmp, TOKEN_FILE)


def token_request(params):
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def access_token():
    tok = load_token()
    if not tok or "refresh_token" not in tok:
        out({"error": "noauth"})
    if tok.get("expires_at", 0) - 60 > time.time():
        return tok["access_token"]
    try:
        new = token_request(
            {
                "grant_type": "refresh_token",
                "refresh_token": tok["refresh_token"],
                "client_id": tok["client_id"],
            }
        )
    except urllib.error.HTTPError as e:
        if e.code in (400, 401):
            out({"error": "noauth"})
        out({"error": f"refresh failed: HTTP {e.code}"})
    except OSError as e:
        out({"error": f"network: {e}"})
    tok["access_token"] = new["access_token"]
    tok["expires_at"] = time.time() + int(new.get("expires_in", 3600))
    if new.get("refresh_token"):
        tok["refresh_token"] = new["refresh_token"]
    save_token(tok)
    return tok["access_token"]


# ---------------------------------------------------------------------- auth
def cmd_auth(client_id):
    client_id = client_id.strip()
    if not re.fullmatch(r"[0-9a-fA-F]{32}", client_id):
        out({"error": "Client ID inválido (deve ter 32 caracteres hexadecimais)"})

    verifier = base64.urlsafe_b64encode(secrets.token_bytes(64)).rstrip(b"=").decode()
    challenge = (
        base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
        .rstrip(b"=")
        .decode()
    )
    state = secrets.token_urlsafe(16)
    result = {}
    done = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if urllib.parse.urlparse(self.path).path != "/callback":
                self.send_response(404)
                self.end_headers()
                return
            if q.get("state", [""])[0] != state:
                # requisição que não veio do nosso login: ignora e segue esperando
                self.send_response(400)
                self.end_headers()
                return
            if "code" in q:
                result["code"] = q["code"][0]
            else:
                result["error"] = q.get("error", ["desconhecido"])[0]
            ok = "code" in result
            body = (
                "<html><body style='font-family:sans-serif;background:#121212;color:#fff;"
                "display:flex;align-items:center;justify-content:center;height:100vh'>"
                f"<h2>{'Conectado! Pode fechar esta aba.' if ok else 'Falhou: ' + html.escape(result.get('error', ''))}</h2>"
                "</body></html>"
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
            done.set()

    try:
        server = http.server.HTTPServer(("127.0.0.1", REDIRECT_PORT), Handler)
    except OSError as e:
        out({"error": f"porta {REDIRECT_PORT} ocupada: {e}"})
    threading.Thread(target=server.serve_forever, daemon=True).start()

    url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode(
        {
            "client_id": client_id,
            "response_type": "code",
            "redirect_uri": REDIRECT_URI,
            "code_challenge_method": "S256",
            "code_challenge": challenge,
            "scope": SCOPES,
            "state": state,
        }
    )
    subprocess.Popen(
        ["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    if not done.wait(timeout=300):
        server.shutdown()
        out({"error": "tempo esgotado aguardando o login"})
    server.shutdown()
    if "code" not in result:
        out({"error": result.get("error", "falha")})

    try:
        tok = token_request(
            {
                "grant_type": "authorization_code",
                "code": result["code"],
                "redirect_uri": REDIRECT_URI,
                "client_id": client_id,
                "code_verifier": verifier,
            }
        )
    except urllib.error.HTTPError as e:
        out({"error": f"troca de token falhou: HTTP {e.code} {e.read()[:200]!r}"})
    save_token(
        {
            "client_id": client_id,
            "access_token": tok["access_token"],
            "refresh_token": tok["refresh_token"],
            "expires_at": time.time() + int(tok.get("expires_in", 3600)),
        }
    )
    out({"ok": True})


# ------------------------------------------------------------------- library
def current_track_id():
    try:
        res = subprocess.run(
            [
                "gdbus", "call", "--session",
                "--dest", "org.mpris.MediaPlayer2.spotify",
                "--object-path", "/org/mpris/MediaPlayer2",
                "--method", "org.freedesktop.DBus.Properties.Get",
                "org.mpris.MediaPlayer2.Player", "Metadata",
            ],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    m = re.search(r"/com/spotify/track/([A-Za-z0-9]{22})", res.stdout)
    if not m:
        m = re.search(r"spotify:track:([A-Za-z0-9]{22})", res.stdout)
    return m.group(1) if m else None


def api(method, path, token):
    req = urllib.request.Request(
        API + path, method=method, headers={"Authorization": f"Bearer {token}"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, None


def is_liked(tid, token):
    uri = urllib.parse.quote(f"spotify:track:{tid}")
    st, body = api("GET", f"/me/library/contains?uris={uri}", token)
    if st != 200:  # endpoint antigo como fallback
        st, body = api("GET", f"/me/tracks/contains?ids={tid}", token)
    if st == 401:
        out({"error": "noauth"})
    if st != 200 or not isinstance(body, list) or not body:
        out({"error": f"HTTP {st}", "trackId": tid})
    return bool(body[0])


def set_liked(tid, token, liked):
    method = "PUT" if liked else "DELETE"
    uri = urllib.parse.quote(f"spotify:track:{tid}")
    st, _ = api(method, f"/me/library?uris={uri}", token)
    if st not in (200, 201, 204):
        st, _ = api(method, f"/me/tracks?ids={tid}", token)
    if st not in (200, 201, 204):
        out({"error": f"HTTP {st}", "trackId": tid})


def resolve_tid(args):
    tid = args[0] if args else None
    if tid:
        m = re.search(r"([A-Za-z0-9]{22})$", tid)
        tid = m.group(1) if m else None
    tid = tid or current_track_id()
    if not tid:
        out({"error": "notrack"})
    return tid


def main():
    if len(sys.argv) < 2:
        out({"error": "uso: auth|status|toggle"})
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "auth":
        cmd_auth(args[0] if args else "")
    elif cmd == "status":
        tid = resolve_tid(args)
        out({"liked": is_liked(tid, access_token()), "trackId": tid})
    elif cmd == "toggle":
        tid = resolve_tid(args)
        token = access_token()
        new = not is_liked(tid, token)
        set_liked(tid, token, new)
        out({"liked": new, "trackId": tid})
    elif cmd == "logout":
        try:
            os.remove(TOKEN_FILE)
        except OSError:
            pass
        out({"ok": True})
    else:
        out({"error": f"comando desconhecido: {cmd}"})


if __name__ == "__main__":
    main()
