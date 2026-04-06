#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/data}"
DOMAINS_FILE="${DOMAINS_FILE:-/opt/openreg/assets/domains.txt}"

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
DEFAULT_PROXY="${DEFAULT_PROXY:-}"
USE_REGISTRATION_PROXY="${USE_REGISTRATION_PROXY:-false}"

mkdir -p "${INSTALL_DIR}/config" "${INSTALL_DIR}/codex_tokens"
touch "${INSTALL_DIR}/ak.txt" "${INSTALL_DIR}/rk.txt" "${INSTALL_DIR}/registered_accounts.txt" "${INSTALL_DIR}/dan-web.log"

python3 - "$INSTALL_DIR" "$DOMAINS_FILE" "$UPLOAD_API_URL" "$UPLOAD_API_TOKEN" "$CPA_BASE_URL" "$CPA_TOKEN" "$MAIL_API_URL" "$MAIL_API_KEY" "$THREADS" "$TARGET_MIN_TOKENS" "$WEB_TOKEN" "$CLIENT_API_TOKEN" "$PORT" "$DEFAULT_PROXY" "$USE_REGISTRATION_PROXY" <<'PY'
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
    default_proxy,
    use_registration_proxy,
) = sys.argv[1:]

base = Path(install_dir)
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
    "default_proxy": default_proxy,
    "use_registration_proxy": str(use_registration_proxy).lower() == "true",
    "cpa_base_url": cpa_base_url.rstrip("/"),
    "cpa_token": cpa_token,
    "mail_api_url": mail_api_url,
    "mail_api_key": mail_api_key,
    "port": int(port),
}

(base / "config.json").write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(base / "config" / "web_config.json").write_text(json.dumps(web_config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

cd "${INSTALL_DIR}"
exec /usr/local/bin/dan-web
