#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/data}"
DOMAINS_FILE="${DOMAINS_FILE:-/opt/openreg/assets/domains.txt}"
DOMAINS_API_URL="${DOMAINS_API_URL:-https://gpt-up.icoa.pp.ua/v0/management/domains}"
DEFAULT_CONFIG_FILE="${DEFAULT_CONFIG_FILE:-/opt/openreg/defaults/config.json}"
DEFAULT_WEB_CONFIG_FILE="${DEFAULT_WEB_CONFIG_FILE:-/opt/openreg/defaults/web_config.json}"
BINARY_SOURCE="${BINARY_SOURCE:-/usr/local/bin/dan-web}"
STATUS_PROXY_SOURCE="${STATUS_PROXY_SOURCE:-/opt/openreg/status_proxy.py}"

CPA_BASE_URL="${CPA_BASE_URL:-https://cpa.cpapi.app/}"
CPA_TOKEN="${CPA_TOKEN:-admin123}"
UPLOAD_API_URL="${UPLOAD_API_URL:-https://cpa.cpapi.app/v0/management/auth-files}"
UPLOAD_API_TOKEN="${UPLOAD_API_TOKEN:-admin123}"
MAIL_API_URL="${MAIL_API_URL:-https://gpt-mail.icoa.pp.ua/}"
MAIL_API_KEY="${MAIL_API_KEY:-linuxdo}"
THREADS="${THREADS:-40}"
TARGET_MIN_TOKENS="${TARGET_MIN_TOKENS:-15000}"
OTP_RETRY_COUNT="${OTP_RETRY_COUNT:-12}"
OTP_RETRY_INTERVAL_SECONDS="${OTP_RETRY_INTERVAL_SECONDS:-5}"
WEB_TOKEN="${WEB_TOKEN:-linuxdo}"
CLIENT_API_TOKEN="${CLIENT_API_TOKEN:-linuxdo}"
PORT="${PORT:-25666}"
UPSTREAM_PORT="${UPSTREAM_PORT:-25667}"
DEFAULT_PROXY="${DEFAULT_PROXY:-}"
USE_REGISTRATION_PROXY="${USE_REGISTRATION_PROXY:-false}"

mkdir -p "${INSTALL_DIR}/config" "${INSTALL_DIR}/codex_tokens"
touch "${INSTALL_DIR}/ak.txt" "${INSTALL_DIR}/rk.txt" "${INSTALL_DIR}/registered_accounts.txt" "${INSTALL_DIR}/dan-web.log"
install -Dm755 "${BINARY_SOURCE}" "${INSTALL_DIR}/dan-web"
install -Dm755 "${STATUS_PROXY_SOURCE}" "${INSTALL_DIR}/status_proxy.py"

write_config() {
python3 - "$INSTALL_DIR" "$DOMAINS_FILE" "$DOMAINS_API_URL" "$DEFAULT_CONFIG_FILE" "$DEFAULT_WEB_CONFIG_FILE" "$UPLOAD_API_URL" "$UPLOAD_API_TOKEN" "$CPA_BASE_URL" "$CPA_TOKEN" "$MAIL_API_URL" "$MAIL_API_KEY" "$THREADS" "$TARGET_MIN_TOKENS" "$OTP_RETRY_COUNT" "$OTP_RETRY_INTERVAL_SECONDS" "$WEB_TOKEN" "$CLIENT_API_TOKEN" "$UPSTREAM_PORT" "$DEFAULT_PROXY" "$USE_REGISTRATION_PROXY" <<'PY'
import json
import sys
import urllib.request
from pathlib import Path

(
    install_dir,
    domains_file,
    domains_api_url,
    default_config_file,
    default_web_config_file,
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
    default_proxy,
    use_registration_proxy,
) = sys.argv[1:]

base = Path(install_dir)
config_path = base / "config.json"
web_config_path = base / "config" / "web_config.json"
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

def load_default(path: str):
    p = Path(path)
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {}

config = load_default(default_config_file)
config.update({
    "ak_file": "ak.txt",
    "rk_file": "rk.txt",
    "token_json_dir": "codex_tokens",
    "upload_api_url": upload_api_url,
    "upload_api_token": upload_api_token,
    "oauth_issuer": config.get("oauth_issuer", "https://auth.openai.com"),
    "oauth_client_id": config.get("oauth_client_id", "app_EMoamEEZ73f0CkXaXp7hrann"),
    "oauth_redirect_uri": config.get("oauth_redirect_uri", "http://localhost:1455/auth/callback"),
    "enable_oauth": True,
    "oauth_required": True,
})

web_config = load_default(default_web_config_file)
web_config.update({
    "target_min_tokens": int(target_min_tokens),
    "auto_fill_start_gap": int(web_config.get("auto_fill_start_gap", 1)),
    "check_interval_minutes": int(web_config.get("check_interval_minutes", 1)),
    "manual_default_threads": int(threads),
    "manual_register_retries": int(web_config.get("manual_register_retries", 3)),
    "otp_retry_count": int(otp_retry_count),
    "otp_retry_interval_seconds": int(otp_retry_interval_seconds),
    "web_token": web_token,
    "client_api_token": client_api_token,
    "enabled_email_domains": domains,
    "mail_domain_options": domains,
    "default_proxy": default_proxy,
    "use_registration_proxy": str(use_registration_proxy).lower() == "true",
    "cpa_base_url": cpa_base_url.rstrip("/"),
    "cpa_token": cpa_token,
    "mail_api_url": mail_api_url,
    "mail_api_key": mail_api_key,
    "port": int(port),
})

config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
web_config_path.write_text(json.dumps(web_config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

write_config

bootstrap_log="${INSTALL_DIR}/dan-web.log"
"${INSTALL_DIR}/dan-web" >>"${bootstrap_log}" 2>&1 &
bootstrap_pid=$!
sleep 4 || true
kill "${bootstrap_pid}" 2>/dev/null || true
wait "${bootstrap_pid}" 2>/dev/null || true

write_config

cd "${INSTALL_DIR}"
echo "[openreg] config seeded to ${INSTALL_DIR}"
echo "[openreg] mail_api_url=${MAIL_API_URL} domains_api_url=${DOMAINS_API_URL} cpa_base_url=${CPA_BASE_URL} threads=${THREADS} target=${TARGET_MIN_TOKENS} otp_retry_count=${OTP_RETRY_COUNT} otp_retry_interval_seconds=${OTP_RETRY_INTERVAL_SECONDS}"

"${INSTALL_DIR}/dan-web" >>"${bootstrap_log}" 2>&1 &
dan_pid=$!

python3 "${INSTALL_DIR}/status_proxy.py" \
  --listen-host 0.0.0.0 \
  --listen-port "${PORT}" \
  --upstream-port "${UPSTREAM_PORT}" \
  --cpa-base-url "${CPA_BASE_URL}" \
  --cpa-token "${CPA_TOKEN}" >>"${bootstrap_log}" 2>&1 &
proxy_pid=$!

cleanup() {
  kill "${proxy_pid}" 2>/dev/null || true
  kill "${dan_pid}" 2>/dev/null || true
  wait "${proxy_pid}" 2>/dev/null || true
  wait "${dan_pid}" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

wait -n "${dan_pid}" "${proxy_pid}"
exit $?
