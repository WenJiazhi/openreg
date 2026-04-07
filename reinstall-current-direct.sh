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
MAIL_API_URL="${MAIL_API_URL:-https://gpt-mail.icoa.pp.ua/}"
MAIL_API_KEY="${MAIL_API_KEY:-linuxdo}"
DOMAINS_API_URL="${DOMAINS_API_URL:-https://gpt-up.icoa.pp.ua/v0/management/domains}"
THREADS="${THREADS:-40}"
TARGET_MIN_TOKENS="${TARGET_MIN_TOKENS:-15000}"
OTP_RETRY_COUNT="${OTP_RETRY_COUNT:-12}"
OTP_RETRY_INTERVAL_SECONDS="${OTP_RETRY_INTERVAL_SECONDS:-5}"
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

if [[ $EUID -ne 0 ]]; then
  echo "please run as root" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR/config" "$INSTALL_DIR/codex_tokens"
install -Dm755 "$BIN_SOURCE" "$INSTALL_DIR/dan-web"
touch "$INSTALL_DIR/ak.txt" "$INSTALL_DIR/rk.txt" "$INSTALL_DIR/registered_accounts.txt" "$INSTALL_DIR/dan-web.log"

python3 - "$INSTALL_DIR" "$DOMAINS_FILE" "$DOMAINS_API_URL" "$UPLOAD_API_URL" "$UPLOAD_API_TOKEN" "$CPA_BASE_URL" "$CPA_TOKEN" "$MAIL_API_URL" "$MAIL_API_KEY" "$THREADS" "$TARGET_MIN_TOKENS" "$OTP_RETRY_COUNT" "$OTP_RETRY_INTERVAL_SECONDS" "$WEB_TOKEN" "$CLIENT_API_TOKEN" "$PORT" <<'PY'
import json
import sys
import urllib.request
from pathlib import Path

(
    install_dir,
    domains_file,
    domains_api_url,
    upload_api_url,
    upload_api_token,
    cpa_base_url,
    cpa_token,
    mail_api_url,
    mail_api_key,
    threads,
    target_min_tokens,
    otp_retry_count,
    otp_retry_interval_seconds,
    web_token,
    client_api_token,
    port,
) = sys.argv[1:]

install = Path(install_dir)
def load_domains(file_path: str, api_url: str):
    if api_url.strip():
        try:
            with urllib.request.urlopen(api_url, timeout=30) as resp:
                payload = json.load(resp)
            domains = payload.get("domains")
            if isinstance(domains, list):
                cleaned = [str(item).strip() for item in domains if str(item).strip()]
                if cleaned:
                    return cleaned
        except Exception:
            pass
    return [
        line.strip()
        for line in Path(file_path).read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]

domains = load_domains(domains_file, domains_api_url)

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
    "otp_retry_count": int(otp_retry_count),
    "otp_retry_interval_seconds": int(otp_retry_interval_seconds),
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

cat >/etc/systemd/system/dan-web.service <<UNIT
[Unit]
Description=dan-web runtime
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/dan-web
Restart=always
RestartSec=5
KillMode=process
StandardOutput=append:${INSTALL_DIR}/dan-web.log
StandardError=append:${INSTALL_DIR}/dan-web.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl stop dan-web 2>/dev/null || true
pkill -x dan-web 2>/dev/null || true
rm -f "${INSTALL_DIR}/dan-web.pid" 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now dan-web
sleep 5

echo "=== dan-web ==="
systemctl is-active dan-web

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
python3 - "$WEB_TOKEN" "$PORT" <<'PY'
import json
import sys
import urllib.request

token, port = sys.argv[1:]
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

if [[ -n "$BOOTSTRAP_TMP" ]]; then
  rm -rf "$BOOTSTRAP_TMP"
fi
