#!/usr/bin/env bash
set -euo pipefail

SNAP_BASE="/root/system-backups/20260406-070550"
INSTALL_DIR="${HOME}/dan-runtime"
TMP_DIR="/root/system-backups/.reinstall-current-tmp"

INSTALLER="$SNAP_BASE/upstream/evan1s_install.sh"
DOMAINS_FILE="$SNAP_BASE/upstream/evan1s_domains.txt"
BACKUP_TAR="$SNAP_BASE/archives/dan-runtime.tar.gz"

CPA_BASE_URL="https://cpa.cpapi.app/"
CPA_TOKEN="admin123"
UPLOAD_API_URL="https://cpa.cpapi.app/v0/management/auth-files"
UPLOAD_API_TOKEN="admin123"
MAIL_API_URL="http://140.245.126.24:9000/"
MAIL_API_KEY="linuxdo"
THREADS="40"
TARGET_MIN_TOKENS="15000"
WEB_TOKEN="linuxdo"
CLIENT_API_TOKEN="linuxdo"
PORT="25666"

mkdir -p "$TMP_DIR"
rm -rf "$TMP_DIR/extract"
mkdir -p "$TMP_DIR/extract"

test -f "$INSTALLER"
test -f "$DOMAINS_FILE"
test -f "$BACKUP_TAR"

systemctl stop dan-web 2>/dev/null || true
pkill -x dan-web 2>/dev/null || true
rm -f "$INSTALL_DIR/dan-web.pid" 2>/dev/null || true

# 提取当前冻结的 dan-web 二进制，避免上游变更
rm -f "$TMP_DIR/extract/dan-web"
tar -xzf "$BACKUP_TAR" -C "$TMP_DIR/extract" dan-runtime/dan-web
install -Dm755 "$TMP_DIR/extract/dan-runtime/dan-web" "$INSTALL_DIR/dan-web"
mkdir -p "$INSTALL_DIR/config"

# 用冻结 installer 补齐运行目录/默认文件（不依赖远端最新脚本）
bash "$INSTALLER" \
  --install-dir "$INSTALL_DIR" \
  --background \
  --cpa-base-url "$CPA_BASE_URL" \
  --cpa-token "$CPA_TOKEN" \
  --mail-api-url "$MAIL_API_URL" \
  --mail-api-key "$MAIL_API_KEY" \
  --threads "$THREADS" || true

# 强制写回当前稳定配置
python3 - <<'PY'
import json
from pathlib import Path

install = Path('/root/dan-runtime')
config_path = install / 'config.json'
web_path = install / 'config' / 'web_config.json'
domains_file = Path('/root/system-backups/20260406-070550/upstream/evan1s_domains.txt')

def load_json(p):
    if p.exists():
        return json.loads(p.read_text(encoding='utf-8'))
    return {}

cfg = load_json(config_path)
cfg.update({
    'upload_api_url': 'https://cpa.cpapi.app/v0/management/auth-files',
    'upload_api_token': 'admin123',
    'oauth_issuer': cfg.get('oauth_issuer', 'https://auth.openai.com'),
    'oauth_client_id': cfg.get('oauth_client_id', 'app_EMoamEEZ73f0CkXaXp7hrann'),
    'oauth_redirect_uri': cfg.get('oauth_redirect_uri', 'http://localhost:1455/auth/callback'),
    'enable_oauth': True,
    'oauth_required': True,
})
config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

web = load_json(web_path)
domains = []
if domains_file.exists():
    for line in domains_file.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        domains.append(line)
web.update({
    'target_min_tokens': 15000,
    'auto_fill_start_gap': 1,
    'check_interval_minutes': 1,
    'manual_default_threads': 40,
    'manual_register_retries': 3,
    'web_token': 'linuxdo',
    'client_api_token': 'linuxdo',
    'client_notice': web.get('client_notice', ''),
    'minimum_client_version': web.get('minimum_client_version', ''),
    'enabled_email_domains': domains,
    'mail_domain_options': domains,
    'default_proxy': web.get('default_proxy', ''),
    'use_registration_proxy': web.get('use_registration_proxy', False),
    'cpa_base_url': 'https://cpa.cpapi.app',
    'cpa_token': 'admin123',
    'mail_api_url': 'http://140.245.126.24:9000/',
    'mail_api_key': 'linuxdo',
    'port': 25666,
})
web_path.write_text(json.dumps(web, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY

# systemd 服务兜底
cat >/etc/systemd/system/dan-web.service <<'UNIT'
[Unit]
Description=dan-web runtime
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/dan-runtime
ExecStart=/root/dan-runtime/dan-web
Restart=always
RestartSec=5
KillMode=process
StandardOutput=append:/root/dan-runtime/dan-web.log
StandardError=append:/root/dan-runtime/dan-web.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now dan-web
sleep 5

echo "=== dan-web ==="
systemctl is-active dan-web

echo "=== config ==="
python3 - <<'PY'
import json
with open('/root/dan-runtime/config.json','r',encoding='utf-8') as f: cfg=json.load(f)
with open('/root/dan-runtime/config/web_config.json','r',encoding='utf-8') as f: web=json.load(f)
print('upload_api_url=', cfg.get('upload_api_url'))
print('upload_api_token=', cfg.get('upload_api_token'))
print('cpa_base_url=', web.get('cpa_base_url'))
print('cpa_token=', web.get('cpa_token'))
print('mail_api_url=', web.get('mail_api_url'))
print('mail_api_key=', web.get('mail_api_key'))
print('manual_default_threads=', web.get('manual_default_threads'))
print('target_min_tokens=', web.get('target_min_tokens'))
print('domains_count=', len(web.get('enabled_email_domains', [])))
PY

echo "=== status ==="
curl -fsS -H 'Authorization: Bearer linuxdo' http://127.0.0.1:25666/api/status | python3 - <<'PY'
import json,sys
obj=json.load(sys.stdin)
print('cpa.total =', obj.get('cpa',{}).get('total'))
print('cpa.active =', obj.get('cpa',{}).get('active'))
print('running =', obj.get('state',{}).get('running'))
print('current_job =', obj.get('state',{}).get('current_job'))
PY
SH
chmod +x /root/system-backups/reinstall-current-direct.sh
/root/system-backups/reinstall-current-direct.sh >/tmp/reinstall_check.txt 2>&1 || (cat /tmp/reinstall_check.txt; exit 1)
tail -n 30 /tmp/reinstall_check.txt
