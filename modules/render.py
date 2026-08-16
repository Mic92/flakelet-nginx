"""Render nginx server blocks from flakelet http/v1 exports."""

import filecmp
import json
import shutil
import subprocess
import tempfile
import textwrap
from pathlib import Path
from typing import Any

EXPORTS_DIR = Path("@exportsDir@")
OUT_DIR = Path("/run/flakelet-nginx")
CERTIFICATE = "@certificate@"
KEY = "@key@"
TLS = bool(CERTIFICATE)
# The host's nginx may bind specific addresses; a wildcard listen would
# create a separate socket group that never receives those connections.
LISTEN_ADDRESSES: list[str] = json.loads("""@listenAddresses@""")


def indent(text: str, depth: int) -> str:
    return textwrap.indent(textwrap.dedent(text).strip(), "  " * depth)


def listen(port: int, extra: str = "") -> list[str]:
    return [f"  listen {addr}:{port}{extra};" for addr in LISTEN_ADDRESSES]


def listen_block(host: str) -> str:
    if TLS:
        return "\n".join(
            listen(443, " ssl")
            + [
                "  http2 on;",
                f"  ssl_certificate {CERTIFICATE.replace('@host@', host)};",
                f"  ssl_certificate_key {KEY.replace('@host@', host)};",
            ]
        )
    return "\n".join(listen(80))


def server(entry: dict[str, Any]) -> str:
    host = entry["host"]
    lines = [
        "server {",
        f"  server_name {host};",
        listen_block(host),
        f"  client_max_body_size {entry.get('maxBodySize', '1m')};",
        f"  proxy_read_timeout {entry.get('readTimeout', '60s')};",
        f"  proxy_buffering {'on' if entry.get('buffering', True) else 'off'};",
        "  proxy_set_header Host $host;",
        "  proxy_set_header X-Real-IP $remote_addr;",
        "  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
        "  proxy_set_header X-Forwarded-Proto $scheme;",
    ]
    if entry.get("websockets"):
        lines += [
            "  proxy_http_version 1.1;",
            "  proxy_set_header Upgrade $http_upgrade;",
            '  proxy_set_header Connection "upgrade";',
        ]
    if extra := entry.get("extra", {}).get("nginx"):
        lines.append(indent(extra, 1))
    for path in entry.get("paths", ["/"]):
        lines += [
            f"  location {path} {{",
            f"    proxy_pass http://{entry['upstream']};",
            "  }",
        ]
    lines.append("}")
    if TLS:
        lines += (
            ["server {", f"  server_name {host};"]
            + listen(80)
            + ["  return 301 https://$host$request_uri;", "}"]
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        staged = Path(tmp)
        for f in sorted(EXPORTS_DIR.glob("*.json")) if EXPORTS_DIR.is_dir() else []:
            exports = json.loads(f.read_text())
            conf = "".join(server(e) for e in exports.get("http", {}).values())
            if conf:
                (staged / f"{f.stem}.conf").write_text(conf)

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        cmp = filecmp.dircmp(staged, OUT_DIR)
        if not (cmp.left_only or cmp.right_only or cmp.diff_files):
            return
        for old in OUT_DIR.glob("*.conf"):
            old.unlink()
        for new in staged.glob("*.conf"):
            shutil.copy(new, OUT_DIR / new.name)
        nginx_active = subprocess.run(
            ["systemctl", "is-active", "--quiet", "nginx.service"], check=False
        )
        if nginx_active.returncode == 0:
            # --no-block: the render unit is Before=nginx.service, so a
            # synchronous reload would deadlock on job ordering.
            subprocess.run(
                ["systemctl", "reload", "--no-block", "nginx.service"], check=True
            )


if __name__ == "__main__":
    main()
