#!/usr/bin/env python3
# receiver.py — dummy Fluent Bit HTTP(S) sink. Test use only.
# Managed by Ansible role fb_http_receiver; configured via environment variables.
import gzip, os, ssl, sys, threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

BIND          = os.environ.get("BIND", "0.0.0.0")
PORT          = int(os.environ.get("PORT", "8888"))
URI_PATHS     = {p.strip() for p in os.environ.get("URI_PATHS", "/logs").split(",") if p.strip()}
LOG_DIR       = os.environ.get("LOG_DIR", "/var/log/fb-receiver")
TLS_CERT      = os.environ.get("TLS_CERT")
TLS_KEY       = os.environ.get("TLS_KEY")
TLS_CLIENT_CA = os.environ.get("TLS_CLIENT_CA")

os.makedirs(LOG_DIR, exist_ok=True)
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        path = urlsplit(self.path).path
        if path not in URI_PATHS:
            self.send_error(404, f"unknown path {path}")
            return
        try:
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            if self.headers.get("Content-Encoding") == "gzip":
                body = gzip.decompress(body)
        except Exception as e:
            self.send_error(400, str(e))
            return
        day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        with lock, open(os.path.join(LOG_DIR, f"fluentbit-{day}.log"), "ab") as f:
            f.write(body if body.endswith(b"\n") else body + b"\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if urlsplit(self.path).path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_error(404)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"{self.address_string()} {fmt % args}\n")


httpd = ThreadingHTTPServer((BIND, PORT), Handler)

if TLS_CERT and TLS_KEY:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(TLS_CERT, TLS_KEY)
    if TLS_CLIENT_CA:
        ctx.verify_mode = ssl.CERT_REQUIRED
        ctx.load_verify_locations(TLS_CLIENT_CA)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

mode = ("https+mTLS" if TLS_CLIENT_CA else "https") if TLS_CERT else "http"
print(f"listening {mode} on {BIND}:{PORT} paths={sorted(URI_PATHS)} -> {LOG_DIR}",
      file=sys.stderr, flush=True)
httpd.serve_forever()
