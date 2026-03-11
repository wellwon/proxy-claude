#!/usr/bin/env python3
"""proxy-server.py — WellWon Proxy Manager (localhost:7777)"""

import hashlib
import http.cookies
import http.server
import json
import os
import re
import secrets
import subprocess
import urllib.parse
from pathlib import Path

PROXY_DIR = Path(os.environ.get("PROXY_DIR", Path.home() / ".proxy"))
PROJECT_DIR = Path(os.environ.get("PROJECT_DIR", Path(__file__).resolve().parent.parent))
CONF = PROXY_DIR / "profiles.conf"
ACTIVE = PROXY_DIR / "active"
GEO_CACHE = PROXY_DIR / "geo-cache.json"
WEB_DIR = PROXY_DIR / "web"
PORT = 7777

# ── Auth ──
def _load_env():
    """Load .env from project dir or PROXY_DIR."""
    for d in [PROJECT_DIR, PROXY_DIR]:
        env_file = d / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            return

_load_env()
APP_PASSWORD = os.environ.get("APP_PASSWORD", "")
# Session token: random per server start, valid only if password matches
_SESSION_SECRET = secrets.token_hex(16)

def _make_token():
    """Create a session token tied to the current password."""
    return hashlib.sha256((_SESSION_SECRET + APP_PASSWORD).encode()).hexdigest()

def _check_auth(handler):
    """Return True if request is authenticated."""
    if not APP_PASSWORD:
        return True  # no password set — open access
    cookie_header = handler.headers.get("Cookie", "")
    cookies = http.cookies.SimpleCookie(cookie_header)
    token = cookies.get("session")
    return token is not None and token.value == _make_token()

# In-memory geo cache: {profile_name: {countryCode, country, city, ...}}
_geo_cache = {}

def load_geo_cache():
    global _geo_cache
    if GEO_CACHE.exists():
        try:
            _geo_cache = json.loads(GEO_CACHE.read_text())
        except Exception:
            _geo_cache = {}

def save_geo_cache():
    GEO_CACHE.write_text(json.dumps(_geo_cache, ensure_ascii=False, indent=2))

def get_cached_geo(profile_name):
    return _geo_cache.get(profile_name)

def set_cached_geo(profile_name, geo_data):
    _geo_cache[profile_name] = {
        "countryCode": geo_data.get("countryCode", ""),
        "country": geo_data.get("country", ""),
        "city": geo_data.get("city", ""),
        "region": geo_data.get("regionName", ""),
        "isp": geo_data.get("isp", ""),
    }
    save_geo_cache()

load_geo_cache()


def get_profiles():
    profiles = []
    if not CONF.exists():
        return profiles
    for line in CONF.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) == 3:
            name, proto, addr = parts
            host = addr.split("@")[-1] if "@" in addr else addr
            profiles.append({"name": name, "protocol": proto, "host": host, "addr": addr})
    return profiles


def save_profiles(profiles):
    """Записать профили обратно в конфиг."""
    lines = ["# WellWon Proxy Profiles", "# Format: NAME|PROTOCOL|USER:PASS@HOST:PORT", ""]
    for p in profiles:
        lines.append(f'{p["name"]}|{p["protocol"]}|{p["addr"]}')
    CONF.write_text("\n".join(lines) + "\n")


def parse_profile_creds(profile):
    addr = profile["addr"]
    login = password = proxy_ip = port = ""
    if "@" in addr:
        creds, hostport = addr.split("@", 1)
        if ":" in creds:
            login, password = creds.split(":", 1)
        if ":" in hostport:
            proxy_ip, port = hostport.rsplit(":", 1)
        else:
            proxy_ip = hostport
    else:
        if ":" in addr:
            proxy_ip, port = addr.rsplit(":", 1)
        else:
            proxy_ip = addr
    return {"ip": proxy_ip, "port": port, "login": login, "password": password}


def parse_add_input(raw):
    """Разобрать формат IP:PORT:LOGIN:PASS → name, addr."""
    raw = raw.strip()
    parts = raw.split(":")
    if len(parts) == 4:
        ip, port, login, password = parts
        addr = f"{login}:{password}@{ip}:{port}"
        return addr, ip
    elif len(parts) == 2:
        # IP:PORT без авторизации
        return raw, parts[0]
    return None, None


def get_active_profile():
    if ACTIVE.exists():
        return ACTIVE.read_text().strip()
    return ""


def get_geo(proxy_url=None):
    cmd = ["curl", "-s", "--max-time", "8"]
    if proxy_url:
        cmd += ["-x", proxy_url, "--noproxy", ""]
    else:
        cmd += ["--noproxy", "*"]  # ignore env proxy vars — get REAL direct IP
    cmd.append("http://ip-api.com/json/?fields=status,country,countryCode,regionName,city,isp,org,query")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=12)
        if result.returncode == 0 and result.stdout:
            data = json.loads(result.stdout)
            if data.get("status") == "success":
                return data
    except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception):
        pass
    return None


def test_services(proxy_url=None):
    services = [
        ("GitHub", "https://api.github.com", "git push/pull"),
        ("PyPI", "https://pypi.org/simple/", "pip install"),
        ("Anthropic", "https://api.anthropic.com", "Claude API"),
        ("OpenRouter", "https://openrouter.ai/api/v1", "AI роутер"),
    ]
    results = []
    for name, url, desc in services:
        cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "5"]
        if proxy_url:
            cmd += ["-x", proxy_url, "--noproxy", ""]
        else:
            cmd += ["--noproxy", "*"]
        cmd.append(url)
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            code_str = result.stdout.strip()
            code = int(code_str) if code_str.isdigit() else 0
            if code == 0:
                status = "dead"
            elif code < 400:
                status = "ok"
            elif code < 500:
                status = "reachable"  # сервер отвечает, но нужна авторизация и т.п.
            else:
                status = "error"
            results.append({"name": name, "code": code_str, "status": status, "desc": desc})
        except Exception:
            results.append({"name": name, "code": "err", "status": "dead", "desc": desc})
    return results


def build_proxy_url(profile):
    proto = profile["protocol"]
    addr = profile["addr"]
    if proto == "socks5":
        return f"socks5://{addr}"
    return f"http://{addr}"


def find_active_profile_obj():
    active = get_active_profile()
    if not active:
        return None, None
    for p in get_profiles():
        if p["name"] == active:
            return active, p
    return active, None


def switch_profile(name):
    for p in get_profiles():
        if p["name"] == name:
            ACTIVE.write_text(name)
            return True, p
    return False, None


def switch_off():
    ACTIVE.write_text("")


def delete_profile(name):
    profiles = get_profiles()
    new = [p for p in profiles if p["name"] != name]
    if len(new) == len(profiles):
        return False
    save_profiles(new)
    # Если удалили активный — выключить
    if get_active_profile() == name:
        ACTIVE.write_text("")
    return True


def add_profile(name, protocol, addr):
    profiles = get_profiles()
    # Проверить дубликат
    for p in profiles:
        if p["name"] == name:
            return False, "Профиль с таким именем уже существует"
    host = addr.split("@")[-1] if "@" in addr else addr
    profiles.append({"name": name, "protocol": protocol, "host": host, "addr": addr})
    save_profiles(profiles)
    return True, ""


def get_full_status():
    active_name, active_profile = find_active_profile_obj()
    proxy_url = build_proxy_url(active_profile) if active_profile else None
    geo = get_geo(proxy_url)
    if geo:
        return {
            "connected": True,
            "proxy": bool(active_profile),
            "profile": active_name or "",
            "ip": geo.get("query", ""),
            "country": geo.get("country", ""),
            "countryCode": geo.get("countryCode", ""),
            "city": geo.get("city", ""),
            "region": geo.get("regionName", ""),
            "isp": geo.get("isp", ""),
            "org": geo.get("org", ""),
        }
    return {"connected": False, "proxy": False, "profile": active_name or ""}


def _run_git(args):
    """Run git command in project dir."""
    try:
        r = subprocess.run(["git"] + args, cwd=str(PROJECT_DIR), capture_output=True, text=True, timeout=30)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def git_status():
    code, out, err = _run_git(["status", "--porcelain"])
    if code != 0 and "not a git repository" in err:
        return {"initialized": False}
    _, branch_out, _ = _run_git(["branch", "--show-current"])
    _, remote_out, _ = _run_git(["remote", "-v"])
    has_remote = "origin" in remote_out
    changed = len([l for l in out.splitlines() if l.strip()]) if out else 0
    return {"initialized": True, "branch": branch_out, "hasRemote": has_remote, "changed": changed}


def git_commit_push(message):
    # Add all tracked + new files (except gitignored)
    code, _, err = _run_git(["add", "-A"])
    if code != 0:
        return {"ok": False, "error": f"git add: {err}"}
    code, out, err = _run_git(["status", "--porcelain"])
    if not out.strip():
        return {"ok": False, "error": "Нет изменений для коммита"}
    code, _, err = _run_git(["commit", "-m", message])
    if code != 0:
        return {"ok": False, "error": f"git commit: {err}"}
    code, _, err = _run_git(["push"])
    if code != 0:
        return {"ok": False, "error": f"git push: {err}", "committed": True}
    return {"ok": True, "message": "Commit + push выполнен"}


def git_pull():
    code, out, err = _run_git(["pull"])
    if code != 0:
        return {"ok": False, "error": f"git pull: {err}"}
    # After pull, redeploy files to ~/.proxy
    deploy_to_proxy_dir()
    return {"ok": True, "message": f"Pull выполнен. {out}"}


def deploy_to_proxy_dir():
    """Copy project files to ~/.proxy after pull."""
    import shutil
    dst = PROXY_DIR
    for f in ["bin/proxy-check.sh", "bin/proxy-switch.sh", "bin/proxy-server.py"]:
        src = PROJECT_DIR / f
        if src.exists():
            shutil.copy2(str(src), str(dst / f))
    web_src = PROJECT_DIR / "web" / "index.html"
    if web_src.exists():
        shutil.copy2(str(web_src), str(dst / "web" / "index.html"))
    init_src = PROJECT_DIR / "init.sh"
    if init_src.exists():
        shutil.copy2(str(init_src), str(dst / "init.sh"))
    env_src = PROJECT_DIR / ".env"
    if env_src.exists():
        shutil.copy2(str(env_src), str(dst / ".env"))


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def _require_auth(self):
        """Return True if request should be blocked (not authenticated)."""
        if _check_auth(self):
            return False
        self._json_response({"error": "unauthorized"}, 401)
        return True

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        # Auth check endpoint (no auth required)
        if parsed.path == "/api/auth/check":
            return self._json_response({"authenticated": _check_auth(self)})

        # Login page and static assets don't require auth
        # All /api/ endpoints require auth
        if parsed.path.startswith("/api/") and self._require_auth():
            return

        if parsed.path == "/api/status":
            return self._json_response(get_full_status())

        if parsed.path == "/api/profiles":
            profiles = get_profiles()
            active = get_active_profile()
            result = []
            for p in profiles:
                creds = parse_profile_creds(p)
                cached = get_cached_geo(p["name"])
                result.append({
                    "name": p["name"],
                    "protocol": p["protocol"],
                    "host": p["host"],
                    "active": p["name"] == active,
                    "geo": cached,
                    **creds,
                })
            return self._json_response({"profiles": result})

        if parsed.path.startswith("/api/profile-geo/"):
            name = urllib.parse.unquote(parsed.path.split("/api/profile-geo/")[1])
            # Check cache first
            cached = get_cached_geo(name)
            if cached:
                return self._json_response(cached)
            # Lookup geo
            for p in get_profiles():
                if p["name"] == name:
                    proxy_url = build_proxy_url(p)
                    geo = get_geo(proxy_url)
                    if geo:
                        set_cached_geo(name, geo)
                        return self._json_response(get_cached_geo(name))
                    return self._json_response({"error": "Geo lookup failed"}, 500)
            return self._json_response({"error": "Not found"}, 404)

        if parsed.path == "/api/services":
            _, active_profile = find_active_profile_obj()
            proxy_url = build_proxy_url(active_profile) if active_profile else None
            services = test_services(proxy_url)
            return self._json_response({"services": services})

        if parsed.path.startswith("/api/switch/"):
            name = urllib.parse.unquote(parsed.path.split("/api/switch/")[1])
            ok, profile = switch_profile(name)
            if not ok:
                return self._json_response({"ok": False, "error": f"Профиль '{name}' не найден"}, 404)
            status = get_full_status()
            # Cache geo for this profile
            if status.get("connected"):
                set_cached_geo(name, {"countryCode": status.get("countryCode",""), "country": status.get("country",""), "city": status.get("city",""), "regionName": status.get("region",""), "isp": status.get("isp","")})
            return self._json_response({"ok": True, "profile": name, "status": status})

        if parsed.path == "/api/off":
            switch_off()
            # Get DIRECT geo (no proxy)
            geo = get_geo(None)
            if geo:
                status = {
                    "connected": True, "proxy": False, "profile": "",
                    "ip": geo.get("query",""), "country": geo.get("country",""),
                    "countryCode": geo.get("countryCode",""), "city": geo.get("city",""),
                    "region": geo.get("regionName",""), "isp": geo.get("isp",""), "org": geo.get("org",""),
                }
            else:
                status = {"connected": False, "proxy": False, "profile": ""}
            return self._json_response({"ok": True, "status": status})

        if parsed.path.startswith("/api/delete/"):
            name = urllib.parse.unquote(parsed.path.split("/api/delete/")[1])
            ok = delete_profile(name)
            if ok:
                return self._json_response({"ok": True})
            return self._json_response({"ok": False, "error": "Профиль не найден"}, 404)

        if parsed.path == "/api/git/status":
            return self._json_response(git_status())

        if parsed.path == "/" or parsed.path == "":
            self.path = "/index.html"
        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)

        # Login endpoint (no auth required)
        if parsed.path == "/api/auth/login":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode() if length else ""
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                return self._json_response({"ok": False, "error": "Bad JSON"}, 400)
            pw = data.get("password", "")
            if pw == APP_PASSWORD:
                token = _make_token()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                cookie = http.cookies.SimpleCookie()
                cookie["session"] = token
                cookie["session"]["path"] = "/"
                cookie["session"]["httponly"] = True
                cookie["session"]["samesite"] = "Strict"
                cookie["session"]["max-age"] = str(86400 * 30)  # 30 days
                self.send_header("Set-Cookie", cookie["session"].OutputString())
                resp = json.dumps({"ok": True}).encode()
                self.send_header("Content-Length", str(len(resp)))
                self.end_headers()
                self.wfile.write(resp)
                return
            return self._json_response({"ok": False, "error": "Неверный пароль"}, 403)

        # All other POST endpoints require auth
        if self._require_auth():
            return

        if parsed.path == "/api/add":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode() if length else ""
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                return self._json_response({"ok": False, "error": "Неверный JSON"}, 400)

            raw = data.get("raw", "").strip()
            name = data.get("name", "").strip()
            protocol = data.get("protocol", "http").strip()

            if not raw:
                return self._json_response({"ok": False, "error": "Введите данные прокси"}, 400)

            addr, ip = parse_add_input(raw)
            if not addr:
                return self._json_response({"ok": False, "error": "Неверный формат. Используйте: IP:PORT:LOGIN:PASS"}, 400)

            # Автогенерация имени если не указано
            if not name:
                # Попробовать определить гео по IP
                geo = get_geo(f"http://{addr}" if protocol == "http" else f"socks5://{addr}")
                if geo:
                    cc = geo.get("countryCode", "").lower()
                    city = geo.get("city", "").lower().replace(" ", "-")[:10]
                    name = f"{cc}-{city}" if cc and city else f"proxy-{ip.split('.')[-1]}"
                else:
                    name = f"proxy-{ip.split('.')[-1]}"

            # Санитизация имени
            name = re.sub(r'[^a-zA-Z0-9_-]', '-', name).strip('-')[:30]

            ok, err = add_profile(name, protocol, addr)
            if ok:
                return self._json_response({"ok": True, "name": name})
            return self._json_response({"ok": False, "error": err}, 400)

        if parsed.path == "/api/git/commit":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode() if length else "{}"
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                data = {}
            msg = data.get("message", "Update proxy config")
            return self._json_response(git_commit_push(msg))

        if parsed.path == "/api/git/pull":
            return self._json_response(git_pull())

        return self._json_response({"error": "Not found"}, 404)

    def _json_response(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    print(f"🌐 WellWon Proxy Manager → http://localhost:{PORT}")
    server = http.server.HTTPServer(("127.0.0.1", PORT), ProxyHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n✗ Остановлен")
        server.server_close()


if __name__ == "__main__":
    main()
