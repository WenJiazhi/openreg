FROM debian:bookworm-slim

ENV INSTALL_DIR=/data \
    DOMAINS_FILE=/opt/openreg/assets/domains.txt \
    DOMAINS_API_URL=https://gpt-up.icoa.pp.ua/v0/management/domains \
    CPA_BASE_URL=https://cpa.cpapi.app/ \
    CPA_TOKEN=admin123 \
    UPLOAD_API_URL=https://cpa.cpapi.app/v0/management/auth-files \
    UPLOAD_API_TOKEN=admin123 \
    MAIL_API_URL=https://gpt-mail.icoa.pp.ua/ \
    MAIL_API_KEY=linuxdo \
    THREADS=40 \
    TARGET_MIN_TOKENS=15000 \
    OTP_RETRY_COUNT=12 \
    OTP_RETRY_INTERVAL_SECONDS=5 \
    WEB_TOKEN=linuxdo \
    CLIENT_API_TOKEN=linuxdo \
    PORT=25666 \
    DEFAULT_PROXY= \
    USE_REGISTRATION_PROXY=false

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates python3 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/openreg

COPY assets /opt/openreg/assets
COPY defaults /opt/openreg/defaults
COPY entrypoint.sh /entrypoint.sh
COPY assets/status_proxy.py /opt/openreg/status_proxy.py
COPY assets/dan-web-linux-amd64 /usr/local/bin/dan-web

RUN chmod +x /entrypoint.sh /usr/local/bin/dan-web /opt/openreg/status_proxy.py \
    && mkdir -p /data

VOLUME ["/data"]

EXPOSE 25666

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD curl -fsS -H "Authorization: Bearer ${WEB_TOKEN}" "http://127.0.0.1:${PORT}/api/status" >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
