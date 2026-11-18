#!/usr/bin/env python3
"""Serve metrics/integration fixtures so `mbgl-render-test-runner --online`
can record them into metrics/cache-style.db.

The runner rewrites local://tiles/a.png to http://tiles/a.png, so the host
name is the first folder under metrics/integration. Map each host to
127.0.0.1 in /etc/hosts (container only) and run this on port 80:

    python3 scripts/terrain-evidence/fixture_server.py metrics/integration

Every request is logged; a 404 means a fixture is missing.
"""
import http.server
import os
import sys
import urllib.parse

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "metrics/integration")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path).lstrip("/")
        full = os.path.normpath(os.path.join(ROOT, host, path))
        if not full.startswith(ROOT + os.sep) or not os.path.isfile(full):
            self.send_response(404)
            self.end_headers()
            sys.stderr.write(f"MISS {host}/{path}\n")
            return
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=315360000")
        self.end_headers()
        self.wfile.write(data)
        sys.stderr.write(f"HIT {host}/{path}\n")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", 80), Handler).serve_forever()
