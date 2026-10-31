"""Deliberately leaky demo app.

Allocates CHUNK_MIB of real (touched) memory every INTERVAL_SECONDS until the
container exceeds its Kubernetes memory limit and the kernel OOM-kills it.
It only ever grows inside the container's cgroup, so it cannot exhaust the node.

With the defaults (1 MiB every 2 s) and a 64Mi limit the process crosses the
limit after roughly 1.5-2 minutes.
"""

import os
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

CHUNK_MIB = int(os.environ.get("CHUNK_MIB", "1"))
INTERVAL_SECONDS = float(os.environ.get("INTERVAL_SECONDS", "2"))
PORT = int(os.environ.get("PORT", "8080"))

leaked = []  # keeping references is what makes this a "leak"


def rss_mib() -> float:
    """Resident set size from /proc (Linux only, which is all we run on)."""
    with open("/proc/self/statm", encoding="utf-8") as f:
        pages = int(f.read().split()[1])
    return pages * os.sysconf("SC_PAGE_SIZE") / (1024 * 1024)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 (stdlib naming)
        body = f"ok leaked={len(leaked) * CHUNK_MIB}MiB rss={rss_mib():.1f}MiB\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):  # keep stdout for the allocation log only
        pass


def serve() -> None:
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


def main() -> None:
    threading.Thread(target=serve, daemon=True).start()
    print(f"memory-leak-demo started: +{CHUNK_MIB}MiB every {INTERVAL_SECONDS}s", flush=True)
    while True:
        # Multiplying a non-zero byte forces the pages to be written, so they
        # count as resident memory (zero-filled allocations may stay lazy).
        leaked.append(bytearray(b"x") * (CHUNK_MIB * 1024 * 1024))
        print(f"allocated total={len(leaked) * CHUNK_MIB}MiB rss={rss_mib():.1f}MiB", flush=True)
        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
