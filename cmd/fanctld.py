#!/usr/bin/env python3
"""Root daemon that owns direct embedded-controller writes for fan control.

Exposes a Unix socket restricted to one local user via filesystem
permissions, so that user never needs passwordless sudo to switch fan
modes. Must run as root (systemd unit handles this).
"""

import json
import os
import socketserver

EC_PATH = "/sys/kernel/debug/ec/ec0/io"
SOCK_PATH = "/run/fanctld.sock"
SOCK_MODE = 0o660

# Owner of the socket: the desktop user allowed to talk to this daemon.
# Override via the systemd unit's Environment= if your UID/GID differ.
SOCK_UID = int(os.environ.get("FANCTLD_UID", 1000))
SOCK_GID = int(os.environ.get("FANCTLD_GID", 1000))

# EC register offsets and values for the fan controller on the Acer
# Predator PH315-51 embedded controller. Reverse-engineered for this
# specific model by observing register state across the vendor's own
# fan profiles; do not assume these apply to other Predator models.
REGISTERS = {
    "full": [(0x22, 0x58), (0x21, 0x60)],  # CPU turbo, GPU turbo
    "auto": [(0x22, 0x54), (0x21, 0x50)],  # CPU auto, GPU auto
}

state = {"mode": "auto"}


def set_mode(mode):
    with open(EC_PATH, "rb+") as f:
        for offset, value in REGISTERS[mode]:
            f.seek(offset)
            f.write(bytes([value]))
    state["mode"] = mode


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        line = self.rfile.readline().decode().strip().lower()
        try:
            if line == "status":
                resp = {"ok": True, "mode": state["mode"]}
            elif line in REGISTERS:
                set_mode(line)
                resp = {"ok": True, "mode": state["mode"]}
            else:
                resp = {"ok": False, "error": f"unknown command {line!r}"}
        except Exception as e:
            resp = {"ok": False, "error": str(e)}
        self.wfile.write((json.dumps(resp) + "\n").encode())


class Server(socketserver.UnixStreamServer):
    allow_reuse_address = True


def main():
    if os.path.exists(SOCK_PATH):
        os.remove(SOCK_PATH)
    server = Server(SOCK_PATH, Handler)
    os.chmod(SOCK_PATH, SOCK_MODE)
    os.chown(SOCK_PATH, SOCK_UID, SOCK_GID)
    try:
        server.serve_forever()
    finally:
        if os.path.exists(SOCK_PATH):
            os.remove(SOCK_PATH)


if __name__ == "__main__":
    main()
