#!/usr/bin/env python3
"""Minimal read-only smart-HTTP git server for the bootstrap e2e.

Serves a single bare repository (the rendered workspace) so Flux inside the
test cluster can sync it. Only the fetch side of the smart protocol is
implemented: ref advertisement plus git-upload-pack.

Usage: git-server.py <bare-repo> <port>
"""

import gzip
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = sys.argv[1]
PORT = int(sys.argv[2])


class GitHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _git_env(self) -> dict[str, str]:
        env = os.environ | {"GIT_HTTP_EXPORT_ALL": "1"}
        if proto := self.headers.get("Git-Protocol"):
            env["GIT_PROTOCOL"] = proto
        return env

    def _respond(self, content_type: str, body: bytes) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if not self.path.endswith("/info/refs?service=git-upload-pack"):
            self.send_error(404)
            return
        refs = subprocess.run(
            ["git", "upload-pack", "--stateless-rpc", "--advertise-refs", REPO],
            capture_output=True,
            check=True,
            env=self._git_env(),
        ).stdout
        body = b"001e# service=git-upload-pack\n0000" + refs
        self._respond("application/x-git-upload-pack-advertisement", body)

    def do_POST(self) -> None:
        if not self.path.endswith("/git-upload-pack"):
            self.send_error(404)
            return
        request = self.rfile.read(int(self.headers["Content-Length"]))
        if self.headers.get("Content-Encoding") == "gzip":
            request = gzip.decompress(request)
        result = subprocess.run(
            ["git", "upload-pack", "--stateless-rpc", REPO],
            input=request,
            capture_output=True,
            check=True,
            env=self._git_env(),
        ).stdout
        self._respond("application/x-git-upload-pack-result", result)


ThreadingHTTPServer(("0.0.0.0", PORT), GitHandler).serve_forever()
