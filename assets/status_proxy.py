#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "proxy-connection",
}


def normalize_management_url(base_url: str) -> str:
    base = (base_url or "").strip().rstrip("/")
    if not base:
        return ""
    if base.endswith("/v0/management/auth-files"):
        return base
    if base.endswith("/v0/management"):
        return f"{base}/auth-files"
    return f"{base}/v0/management/auth-files"


def build_forward_headers(source_headers):
    headers = {}
    for key, value in source_headers.items():
        if key.lower() in HOP_BY_HOP_HEADERS or key.lower() == "host":
            continue
        headers[key] = value
    return headers


def fetch_cpa_stats(cpa_url: str, cpa_token: str):
    if not cpa_url or not cpa_token:
        return None
    request = urllib.request.Request(
        cpa_url,
        headers={"Authorization": f"Bearer {cpa_token}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except Exception:
        return None

    files = payload.get("files")
    if not isinstance(files, list):
        return None

    counts = Counter()
    for item in files:
        status = item.get("status", "unknown")
        counts[status] += 1

    return {
        "ok": True,
        "total": len(files),
        "active": counts.get("active", 0),
        "error": counts.get("error", 0),
        "disabled": counts.get("disabled", 0),
        "unavailable": sum(1 for item in files if item.get("unavailable")),
    }


class ProxyHandler(BaseHTTPRequestHandler):
    upstream_port = 25667
    cpa_url = ""
    cpa_token = ""

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_PATCH(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    def do_HEAD(self):
        self._proxy()

    def do_OPTIONS(self):
        self._proxy()

    def _proxy(self):
        body = b""
        content_length = self.headers.get("Content-Length")
        if content_length:
            body = self.rfile.read(int(content_length))

        upstream_url = f"http://127.0.0.1:{self.upstream_port}{self.path}"
        headers = build_forward_headers(self.headers)
        request = urllib.request.Request(
            upstream_url,
            data=body if body else None,
            headers=headers,
            method=self.command,
        )

        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                response_body = response.read()
                response_headers = response.headers
                status_code = response.status
        except urllib.error.HTTPError as error:
            response_body = error.read()
            response_headers = error.headers
            status_code = error.code
        except Exception as error:
            payload = json.dumps({"error": str(error)}).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)
            return

        if self.command == "GET" and self.path.startswith("/api/status"):
            try:
                payload = json.loads(response_body.decode("utf-8"))
                stats = fetch_cpa_stats(self.cpa_url, self.cpa_token)
                if stats:
                    payload["cpa"] = {**payload.get("cpa", {}), **stats}
                response_body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                response_headers["Content-Type"] = "application/json; charset=utf-8"
            except Exception:
                pass

        self.send_response(status_code)
        for key, value in response_headers.items():
            lower = key.lower()
            if lower in HOP_BY_HOP_HEADERS or lower == "content-length":
                continue
            if lower == "location":
                upstream_origin = f"http://127.0.0.1:{self.upstream_port}"
                if value.startswith(upstream_origin):
                    scheme = self.headers.get("X-Forwarded-Proto", "http")
                    host = self.headers.get("Host", f"127.0.0.1:{self.server.server_port}")
                    value = f"{scheme}://{host}{value[len(upstream_origin):]}"
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(response_body)

    def log_message(self, format, *args):
        sys.stdout.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), format % args))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen-host", default="0.0.0.0")
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--upstream-port", type=int, required=True)
    parser.add_argument("--cpa-base-url", default="")
    parser.add_argument("--cpa-token", default="")
    args = parser.parse_args()

    ProxyHandler.upstream_port = args.upstream_port
    ProxyHandler.cpa_url = normalize_management_url(args.cpa_base_url)
    ProxyHandler.cpa_token = args.cpa_token

    server = ThreadingHTTPServer((args.listen_host, args.listen_port), ProxyHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
