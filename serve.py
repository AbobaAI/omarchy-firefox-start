#!/usr/bin/env python3
"""Local start-page server: injects live Omafox palette (no FOUC) and serves theme.json live."""
from __future__ import annotations

import json
import mimetypes
import re
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent
OMAFOX_THEME = Path.home() / ".local/state/omafox/theme.json"
FALLBACK_THEME = ROOT / "theme.json"
HOST, PORT = "::", 8765  # dual-stack localhost (firefox.localhost -> ::1)

DEFAULT_PALETTE = {
    "background": "#05010C",
    "foreground": "#FFFFFF",
    "muted": "#757379",
    "accent": "#BB9AF7",
    "lighter_background": "#1E1A24",
    "selection": "#322746",
}

ROOT_BLOCK_RE = re.compile(
    r"(:root\s*\{)(.*?)(\n\s*--font:)",
    re.DOTALL,
)


def load_palette() -> dict:
    for src in (OMAFOX_THEME, FALLBACK_THEME):
        try:
            if not src.is_file():
                continue
            data = json.loads(src.read_text(encoding="utf-8"))
            pal = data.get("palette") or data
            if isinstance(pal, dict) and pal.get("background"):
                return {**DEFAULT_PALETTE, **{k: v for k, v in pal.items() if isinstance(v, str)}}
        except Exception:
            continue
    return dict(DEFAULT_PALETTE)


def load_theme_bytes() -> bytes:
    for src in (OMAFOX_THEME, FALLBACK_THEME):
        try:
            if src.is_file():
                # Normalize to always include palette key for the page
                data = json.loads(src.read_text(encoding="utf-8"))
                if "palette" not in data and "background" in data:
                    data = {"palette": data}
                elif "palette" not in data:
                    data = {"palette": load_palette()}
                return (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode()
        except Exception:
            continue
    return (json.dumps({"palette": DEFAULT_PALETTE}, indent=2) + "\n").encode()


def inject_palette(html: str, pal: dict) -> str:
    # Update the main stylesheet :root first (before critical style exists)
    def repl(m: re.Match) -> str:
        return (
            m.group(1)
            + f"\n    --bg: {pal['background']};\n"
            + f"    --fg: {pal['foreground']};\n"
            + f"    --muted: {pal['muted']};\n"
            + f"    --accent: {pal['accent']};\n"
            + f"    --panel: {pal['lighter_background']};\n"
            + f"    --border: {pal['selection']};"
            + m.group(3)
        )

    html = ROOT_BLOCK_RE.sub(repl, html, count=1)
    # Critical style first in <head> so the very first paint already matches the theme
    critical = (
        '<style id="theme-critical">'
        f"html,body{{background:{pal['background']};color:{pal['foreground']}}}"
        f":root{{--bg:{pal['background']};--fg:{pal['foreground']};--muted:{pal['muted']};"
        f"--accent:{pal['accent']};--panel:{pal['lighter_background']};--border:{pal['selection']}}}"
        "</style>"
    )
    if "<head>" in html:
        html = html.replace("<head>", "<head>\n" + critical, 1)
    return html


class Handler(BaseHTTPRequestHandler):
    server_version = "OmarchyStart/1.0"

    def log_message(self, fmt: str, *args) -> None:
        # Quiet: avoid journal spam
        return

    def _send(self, code: int, body: bytes, content_type: str, cache: str = "no-store") -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = unquote(urlparse(self.path).path)
        if path in ("/", "/index.html"):
            raw = (ROOT / "index.html").read_text(encoding="utf-8")
            body = inject_palette(raw, load_palette()).encode("utf-8")
            self._send(200, body, "text/html; charset=utf-8")
            return
        if path == "/theme.json":
            self._send(200, load_theme_bytes(), "application/json; charset=utf-8")
            return

        # static files under ROOT only
        rel = path.lstrip("/")
        if not rel or ".." in rel.split("/"):
            self._send(404, b"not found\n", "text/plain; charset=utf-8")
            return
        fp = (ROOT / rel).resolve()
        if not str(fp).startswith(str(ROOT.resolve())) or not fp.is_file():
            self._send(404, b"not found\n", "text/plain; charset=utf-8")
            return
        ctype = mimetypes.guess_type(str(fp))[0] or "application/octet-stream"
        data = fp.read_bytes()
        cache = "no-cache" if fp.suffix in {".html", ".json", ".css", ".js"} else "public, max-age=3600"
        self._send(200, data, ctype, cache=cache)


class DualStackServer(ThreadingHTTPServer):
    address_family = socket.AF_INET6

    def server_bind(self) -> None:
        # Accept both ::1 and 127.0.0.1 on the same port
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


def main() -> None:
    # Keep a mirror copy for hooks / fallbacks
    try:
        FALLBACK_THEME.write_bytes(load_theme_bytes())
    except Exception:
        pass
    httpd = DualStackServer((HOST, PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
