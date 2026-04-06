#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
ASSETS_DIR="${SCRIPT_DIR}/assets"
REMOTE_ASSETS_BASE="${REMOTE_ASSETS_BASE:-https://raw.githubusercontent.com/WenJiazhi/openreg/main/assets}"
BOOTSTRAP_TMP=""

INSTALL_DIR="${HOME}/dan-runtime"
CPA_BASE_URL="${CPA_BASE_URL:-https://cpa.cpapi.app/}"
CPA_TOKEN="${CPA_TOKEN:-admin123}"
UPLOAD_API_URL="${UPLOAD_API_URL:-https://cpa.cpapi.app/v0/management/auth-files}"
UPLOAD_API_TOKEN="${UPLOAD_API_TOKEN:-admin123}"
MAIL_API_URL="${MAIL_API_URL:-http://140.245.126.24:9000/}"
MAIL_API_KEY="${MAIL_API_KEY:-linuxdo}"
THREADS="${THREADS:-40}"
TARGET_MIN_TOKENS="${TARGET_MIN_TOKENS:-15000}"
WEB_TOKEN="${WEB_TOKEN:-linuxdo}"
CLIENT_API_TOKEN="${CLIENT_API_TOKEN:-linuxdo}"
PORT="${PORT:-25666}"
DOMAINS_FILE="${DOMAINS_FILE:-${ASSETS_DIR}/domains.txt}"
BIN_SOURCE="${BIN_SOURCE:-${ASSETS_DIR}/dan-web-linux-amd64}"
SHA256_FILE="${SHA256_FILE:-${ASSETS_DIR}/SHA256SUMS.txt}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$BIN_SOURCE" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "missing binary: $BIN_SOURCE" >&2
    exit 1
  fi
  BOOTSTRAP_TMP="$(mktemp -d)"
  ASSETS_DIR="$BOOTSTRAP_TMP/assets"
  mkdir -p "$ASSETS_DIR"
  curl -fsSL "${REMOTE_ASSETS_BASE}/dan-web-linux-amd64" -o "${ASSETS_DIR}/dan-web-linux-amd64"
  curl -fsSL "${REMOTE_ASSETS_BASE}/domains.txt" -o "${ASSETS_DIR}/domains.txt"
  curl -fsSL "${REMOTE_ASSETS_BASE}/SHA256SUMS.txt" -o "${ASSETS_DIR}/SHA256SUMS.txt"
  BIN_SOURCE="${ASSETS_DIR}/dan-web-linux-amd64"
  DOMAINS_FILE="${ASSETS_DIR}/domains.txt"
  SHA256_FILE="${ASSETS_DIR}/SHA256SUMS.txt"
fi

if [[ ! -f "$DOMAINS_FILE" ]]; then
  echo "missing domains file: $DOMAINS_FILE" >&2
  exit 1
fi

if [[ -f "$SHA256_FILE" ]] && command -v sha256sum >/dev/null 2>&1; then
  (cd "$ASSETS_DIR" && sha256sum -c "$(basename "$SHA256_FILE")")
fi

mkdir -p "$INSTALL_DIR/config" "$INSTALL_DIR/codex_tokens"
install -Dm755 "$BIN_SOURCE" "$INSTALL_DIR/dan-web"
touch "$INSTALL_DIR/ak.txt" "$INSTALL_DIR/rk.txt" "$INSTALL_DIR/registered_accounts.txt" "$INSTALL_DIR/dan-web.log"

python3 - "$INSTALL_DIR" "$DOMAINS_FILE" "$UPLOAD_API_URL" "$UPLOAD_API_TOKEN" "$CPA_BASE_URL" "$CPA_TOKEN" "$MAIL_API_URL" "$MAIL_API_KEY" "$THREADS" "$TARGET_MIN_TOKENS" "$WEB_TOKEN" "$CLIENT_API_TOKEN" "$PORT" <<'PY'
import json
import sys
from pathlib import Path

(
    install_dir,
    domains_file,
    upload_api_url,
    upload_api_token,
    cpa_base_url,
    cpa_token,
    mail_api_url,
    mail_api_key,
    threads,
    target_min_tokens,
    web_token,
    client_api_token,
    port,
) = sys.argv[1:]

install = Path(install_dir)
domains = [
    line.strip()
    for line in Path(domains_file).read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]

config = {
    "ak_file": "ak.txt",
    "rk_file": "rk.txt",
    "token_json_dir": "codex_tokens",
    "server_config_url": "",
    "server_api_token": "",
    "domain_report_url": "",
    "upload_api_url": upload_api_url,
    "upload_api_token": upload_api_token,
    "oauth_issuer": "https://auth.openai.com",
    "oauth_client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
    "oauth_redirect_uri": "http://localhost:1455/auth/callback",
    "enable_oauth": True,
    "oauth_required": True,
}

web_config = {
    "target_min_tokens": int(target_min_tokens),
    "auto_fill_start_gap": 1,
    "check_interval_minutes": 1,
    "manual_default_threads": int(threads),
    "manual_register_retries": 3,
    "web_token": web_token,
    "client_api_token": client_api_token,
    "client_notice": "",
    "minimum_client_version": "",
    "enabled_email_domains": domains,
    "mail_domain_options": domains,
    "default_proxy": "",
    "use_registration_proxy": False,
    "cpa_base_url": cpa_base_url.rstrip("/"),
    "cpa_token": cpa_token,
    "mail_api_url": mail_api_url,
    "mail_api_key": mail_api_key,
    "port": int(port),
}

(install / "config.json").write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(install / "config" / "web_config.json").write_text(json.dumps(web_config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

cat >"${INSTALL_DIR}/start.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PORT="$(python3 - "$INSTALL_DIR" <<'PY'
import json
from pathlib import Path
import sys
web = json.loads((Path(sys.argv[1]) / "config" / "web_config.json").read_text(encoding="utf-8"))
print(web.get("port", 25666))
PY
)"
if [[ -f "${INSTALL_DIR}/dan-web.pid" ]] && kill -0 "$(cat "${INSTALL_DIR}/dan-web.pid")" 2>/dev/null; then
  echo "already running: $(cat "${INSTALL_DIR}/dan-web.pid")"
  exit 0
fi
if command -v ss >/dev/null 2>&1 && ss -ltn | awk '{print $4}' | grep -Eq "[:.]${PORT}$"; then
  echo "port already in use: ${PORT}" >&2
  exit 1
fi
nohup "${INSTALL_DIR}/dan-web" >>"${INSTALL_DIR}/dan-web.log" 2>&1 &
echo $! > "${INSTALL_DIR}/dan-web.pid"
sleep 3
echo "started pid=$(cat "${INSTALL_DIR}/dan-web.pid") port=${PORT}"
SH
chmod +x "${INSTALL_DIR}/start.sh"

cat >"${INSTALL_DIR}/stop.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${INSTALL_DIR}/dan-web.pid" ]] && kill -0 "$(cat "${INSTALL_DIR}/dan-web.pid")" 2>/dev/null; then
  kill "$(cat "${INSTALL_DIR}/dan-web.pid")" 2>/dev/null || true
  sleep 2
fi
pkill -u "$(id -u)" -f "${INSTALL_DIR}/dan-web" 2>/dev/null || true
rm -f "${INSTALL_DIR}/dan-web.pid"
echo "stopped"
SH
chmod +x "${INSTALL_DIR}/stop.sh"

cat >"${INSTALL_DIR}/status.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$INSTALL_DIR" <<'PY'
import json
from pathlib import Path
import sys
import urllib.request

base = Path(sys.argv[1])
web = json.loads((base / "config" / "web_config.json").read_text(encoding="utf-8"))
port = web.get("port", 25666)
token = web.get("web_token", "linuxdo")
pid_file = base / "dan-web.pid"
if pid_file.exists():
    print("pid =", pid_file.read_text(encoding="utf-8").strip())
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/api/status",
    headers={"Authorization": f"Bearer {token}"},
)
with urllib.request.urlopen(req, timeout=30) as resp:
    obj = json.load(resp)
print("cpa.total =", obj.get("cpa", {}).get("total"))
print("cpa.active =", obj.get("cpa", {}).get("active"))
print("running =", obj.get("state", {}).get("running"))
print("current_job =", obj.get("state", {}).get("current_job"))
PY
SH
chmod +x "${INSTALL_DIR}/status.sh"

"${INSTALL_DIR}/stop.sh" >/dev/null 2>&1 || true
"${INSTALL_DIR}/start.sh"

echo "=== config ==="
python3 - "$INSTALL_DIR" <<'PY'
import json
import sys
from pathlib import Path

base = Path(sys.argv[1])
cfg = json.loads((base / "config.json").read_text(encoding="utf-8"))
web = json.loads((base / "config" / "web_config.json").read_text(encoding="utf-8"))
print("upload_api_url =", cfg.get("upload_api_url"))
print("upload_api_token =", cfg.get("upload_api_token"))
print("cpa_base_url =", web.get("cpa_base_url"))
print("cpa_token =", web.get("cpa_token"))
print("mail_api_url =", web.get("mail_api_url"))
print("mail_api_key =", web.get("mail_api_key"))
print("manual_default_threads =", web.get("manual_default_threads"))
print("target_min_tokens =", web.get("target_min_tokens"))
print("domains_count =", len(web.get("enabled_email_domains", [])))
PY

echo "=== status ==="
"${INSTALL_DIR}/status.sh"

if [[ -n "$BOOTSTRAP_TMP" ]]; then
  rm -rf "$BOOTSTRAP_TMP"
fi
