#!/usr/bin/env python3
"""Allowlist HTTP(S) proxy for the mock exam browser.

Only the documentation sites allowed during the real CKA exam are reachable;
every other host gets "403 Blocked". HTTPS is tunnelled with CONNECT, so the
filter works on host names (paths are not visible to the proxy).

Usage: doc-proxy.py <port> <allowed-domain> [<allowed-domain> ...]
A domain also allows its subdomains (kubernetes.io -> www.kubernetes.io).
"""

import select
import socket
import socketserver
import sys
from urllib.parse import urlsplit

PORT = int(sys.argv[1])
ALLOWED = [d.lower().lstrip(".") for d in sys.argv[2:]]

BLOCKED_PAGE = (
    b"<html><body style='font-family:sans-serif;margin:3em'>"
    b"<h2>Blocked during the exam</h2>"
    b"<p>Only the Kubernetes documentation sites are allowed:</p><ul>"
    + b"".join(b"<li>" + d.encode() + b"</li>" for d in ALLOWED)
    + b"</ul></body></html>"
)


def allowed(host):
    host = host.lower().rstrip(".")
    return any(host == d or host.endswith("." + d) for d in ALLOWED)


def log(verdict, host):
    print(f"{verdict} {host}", flush=True)


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        request_line = self.rfile.readline(65537).decode("latin-1")
        if not request_line:
            return
        while True:
            line = self.rfile.readline(65537)
            if line in (b"\r\n", b"\n", b""):
                break

        try:
            method, target, _ = request_line.split()
        except ValueError:
            return

        if method == "CONNECT":
            host, _, port = target.rpartition(":")
            port = int(port or 443)
        else:
            parts = urlsplit(target)
            host, port = parts.hostname or "", parts.port or 80

        if not allowed(host):
            log("BLOCK", host)
            self.wfile.write(
                b"HTTP/1.1 403 Blocked\r\nContent-Type: text/html\r\n"
                b"Content-Length: " + str(len(BLOCKED_PAGE)).encode() + b"\r\n"
                b"Connection: close\r\n\r\n" + BLOCKED_PAGE
            )
            return
        log("ALLOW", host)

        if method != "CONNECT":
            # All allowed sites are HTTPS-only; upgrade plain HTTP requests.
            location = "https://" + target.split("://", 1)[-1]
            self.wfile.write(
                f"HTTP/1.1 301 Moved Permanently\r\nLocation: {location}\r\n"
                "Content-Length: 0\r\nConnection: close\r\n\r\n".encode("latin-1")
            )
            return

        try:
            upstream = socket.create_connection((host, port), timeout=15)
        except OSError:
            self.wfile.write(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
            return
        upstream.settimeout(None)
        self.wfile.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        self.pipe(self.connection, upstream)

    @staticmethod
    def pipe(client, upstream):
        sockets = [client, upstream]
        try:
            while True:
                readable, _, broken = select.select(sockets, [], sockets, 120)
                if broken or not readable:
                    return
                for s in readable:
                    data = s.recv(65536)
                    if not data:
                        return
                    (upstream if s is client else client).sendall(data)
        except OSError:
            return
        finally:
            upstream.close()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Handler) as server:
        server.serve_forever()
