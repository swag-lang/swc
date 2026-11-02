#!/usr/bin/env python3
"""Run a command against isolated loopback HTTP/HTTPS fixtures with temporary test roots.

Example (from the repository root):
  python3 bin/std/modules/net/src/tests/http.linux.fixture.py -- \
    python3 tools/linux-tests.py std --compiler /path/to/swc.dm --module net \
    --test-file http.linux.integration.test.swg --test-tag integration.network.http

--proxy selects a loopback HTTP or HTTPS proxy for the proxy-tagged tests. No Internet listener
or request is used. The child receives SSL_CERT_FILE and fixture-port environment values;
the parent environment and its trust store are untouched. OpenSSL creates temporary keys.
"""
from __future__ import annotations

import argparse
import http.server
import os
from pathlib import Path
import select
import socket
import ssl
import subprocess
import tempfile
import threading
import time


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def send_body(self, data: bytes, status=200, headers=()):
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def do_GET(self):
        try:
            if self.path.startswith("http://"):
                self.send_body(("proxy|" + self.path).encode())
            elif self.path == "/redirect":
                self.send_body(b"", 302, (("Location", "/redirect-target"),))
            elif self.path == "/redirect-target":
                self.send_body(b"redirect was followed")
            elif self.path == "/headers":
                self.send_body((self.headers.get("X-Empty", "missing") + "|" +
                                self.headers.get("X-Test", "missing") + "|" +
                                self.headers.get("User-Agent", "missing")).encode())
            elif self.path == "/chunked":
                self.wfile.write(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
                                 b"3\r\nabc\r\n3\r\ndef\r\n0\r\nLocation: /trailer\r\n\r\n")
                self.close_connection = True
            elif self.path == "/header-overflow":
                self.send_body(b"", headers=(("X-Large", "a" * 70000),))
            elif self.path == "/location-overflow":
                self.send_body(b"", 302, (("Location", "/" + "a" * 4096),))
            elif self.path in ("/folded-location", "/folded-location-overflow"):
                tail = b"/second" if self.path == "/folded-location" else b"a" * 4090
                self.wfile.write(b"HTTP/1.1 302 Found\r\nLocation: /first\r\n " + tail +
                                 b"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                self.close_connection = True
            elif self.path == "/location-limit":
                self.send_body(b"", 302, (("Location", "/" + "a" * 4095),))
            elif self.path == "/partial":
                self.wfile.write(b"HTTP/1.1 200 OK\r\nContent-Length: 20\r\nConnection: close\r\n\r\nshort")
                self.close_connection = True
            elif self.path == "/informational":
                self.wfile.write(b"HTTP/1.1 103 Early Hints\r\nLocation: /interim\r\n\r\n")
                self.send_body(b"final")
            elif self.path == "/slow":
                time.sleep(1)
                self.send_body(b"late")
            elif self.path == "/empty":
                self.send_body(b"")
            elif self.path == "/missing":
                self.send_body(b"missing", 404)
            elif self.path == "/body":
                self.send_body(b"hello")
            else:
                self.send_body(self.path.encode())
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            self.close_connection = True

    def do_CONNECT(self):
        # Only this fixture's TLS listener can be reached through the test proxy.
        expected = f"proxy-target.invalid:{self.server.target_port}"
        if self.path != expected:
            self.send_error(403)
            return
        with socket.create_connection(("127.0.0.1", self.server.target_port), timeout=3) as upstream:
            self.send_response(200, "Connection established")
            self.end_headers()
            self.wfile.flush()
            until = time.monotonic() + 5
            while time.monotonic() < until:
                readable, _, _ = select.select([self.connection, upstream], [], [], 0.1)
                for source in readable:
                    data = source.recv(65536)
                    if not data:
                        self.close_connection = True
                        return
                    (upstream if source is self.connection else self.connection).sendall(data)
        self.close_connection = True


def make_certificate(directory: Path, stem: str):
    key, cert = directory / f"{stem}.key", directory / f"{stem}.pem"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", str(key), "-out", str(cert), "-days", "2", "-sha256",
                    "-subj", "/CN=Swag loopback test",
                    "-addext", "subjectAltName=DNS:localhost,DNS:proxy-target.invalid",
                    "-addext", "basicConstraints=critical,CA:TRUE"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    return cert, key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy", choices=("http", "https", "untrusted"))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a child command is required after --")
    with tempfile.TemporaryDirectory(prefix="swag-http-fixture-") as directory:
        root = Path(directory)
        trusted, trusted_key = make_certificate(root, "trusted")
        untrusted, untrusted_key = make_certificate(root, "untrusted")
        servers, workers = [], []
        try:
            for certificate, key in ((None, None), (trusted, trusted_key), (untrusted, untrusted_key),
                                     (trusted, trusted_key), (untrusted, untrusted_key)):
                server = Server(("127.0.0.1", 0), Handler)
                if certificate:
                    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                    context.load_cert_chain(certificate, key)
                    server.socket = context.wrap_socket(server.socket, server_side=True)
                servers.append(server)
                worker = threading.Thread(target=server.serve_forever, daemon=True)
                worker.start()
                workers.append(worker)
            for index in (0, 3, 4):
                servers[index].target_port = servers[1].server_port
            environment = os.environ.copy()
            # Only the child bypasses its configured proxies for these loopback fixtures.
            for name in ("NO_PROXY", "no_proxy"):
                previous = environment.get(name, "")
                environment[name] = previous + ("," if previous else "") + "localhost,127.0.0.1"
            environment.update(SSL_CERT_FILE=str(trusted),
                               SWAG_TEST_HTTP_PORT=str(servers[0].server_port),
                               SWAG_TEST_HTTPS_PORT=str(servers[1].server_port),
                               SWAG_TEST_UNTRUSTED_HTTPS_PORT=str(servers[2].server_port))
            if args.proxy:
                index = {"http": 0, "https": 3, "untrusted": 4}[args.proxy]
                scheme = "http" if args.proxy == "http" else "https"
                proxy = f"{scheme}://localhost:{servers[index].server_port}"
                environment.update(http_proxy=proxy, https_proxy=proxy)
            return subprocess.run(command, env=environment, timeout=180).returncode
        finally:
            for server in servers:
                server.shutdown()
                server.server_close()
            for worker in workers:
                worker.join(timeout=2)


if __name__ == "__main__":
    raise SystemExit(main())
