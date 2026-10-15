#!/usr/bin/env python3
"""Root daemon that owns direct embedded-controller writes for fan control.

Exposes a Unix socket restricted to members of the ``fanctl`` group, so
those users never need passwordless sudo to switch fan modes. Must run as
root; the shipped systemd units handle that and pass the socket in via
socket activation.
"""

import argparse
import grp
import json
import os
import signal
import socket
import socketserver
import sys

VERSION = "@VERSION@"

EC_PATH = os.environ.get("FANCTLD_EC_PATH", "/sys/kernel/debug/ec/ec0/io")
DMI_PATH = os.environ.get("FANCTLD_DMI_PATH", "/sys/class/dmi/id/product_name")
SOCK_PATH = os.environ.get("FANCTLD_SOCKET", "/run/fanctld.sock")
SOCK_GROUP = "fanctl"
SOCK_MODE = 0o660
SUPPORTED_MODEL = "PH315-51"
MAX_COMMAND = 64

# EC register offsets and values for the fan controller on the Acer
# Predator PH315-51 embedded controller. Reverse-engineered for this
# specific model by observing register state across the vendor's own
# fan profiles; do not assume these apply to other Predator models.
REGISTERS = {
    "full": ((0x22, 0x58), (0x21, 0x60)),  # CPU turbo, GPU turbo
    "auto": ((0x22, 0x54), (0x21, 0x50)),  # CPU auto, GPU auto
}


class FanctlError(Exception):
    """An error with a message meant for the person running the daemon."""


def version():
    return "dev" if VERSION.startswith("@") else VERSION


def log(message):
    print(message, file=sys.stderr, flush=True)


def check_model(force=False):
    try:
        with open(DMI_PATH) as f:
            model = f.read().strip()
    except OSError:
        model = ""
    if SUPPORTED_MODEL in model:
        return
    if force:
        log(f"warning: unsupported model {model!r}, continuing because of --force")
        return
    found = repr(model) if model else "an unknown model"
    raise FanctlError(
        f"refusing to run on {found}: the EC register map "
        f"is only known for the Acer Predator {SUPPORTED_MODEL}. "
        "Set FANCTLD_FORCE=1 to override at your own risk."
    )


def check_ec():
    if not os.path.exists(EC_PATH):
        raise FanctlError(
            f"{EC_PATH} does not exist: load the ec_sys module with "
            "'modprobe ec_sys write_support=1' and make sure debugfs is mounted"
        )
    if not os.access(EC_PATH, os.R_OK | os.W_OK):
        raise FanctlError(
            f"{EC_PATH} is not writable: run as root, load ec_sys with "
            "write_support=1, and note that kernel lockdown (Secure Boot) "
            "blocks EC writes"
        )


def read_mode():
    with open(EC_PATH, "rb", buffering=0) as f:
        values = {}
        for offset, _ in REGISTERS["auto"]:
            f.seek(offset)
            values[offset] = f.read(1)[0]
    for mode, writes in REGISTERS.items():
        if all(values[offset] == value for offset, value in writes):
            return mode
    return "unknown"


def set_mode(mode):
    with open(EC_PATH, "r+b", buffering=0) as f:
        for offset, value in REGISTERS[mode]:
            f.seek(offset)
            f.write(bytes([value]))
    return read_mode()


def handle_command(command):
    try:
        if command == "status":
            return {"ok": True, "mode": read_mode()}
        if command in REGISTERS:
            return {"ok": True, "mode": set_mode(command)}
        return {"ok": False, "error": f"unknown command {command!r}"}
    except OSError as e:
        return {"ok": False, "error": f"EC access failed: {e}"}


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        raw = self.rfile.readline(MAX_COMMAND)
        command = raw.decode(errors="replace").strip().lower()
        response = handle_command(command)
        if command in REGISTERS and response["ok"]:
            log(f"mode set to {response['mode']}")
        self.wfile.write((json.dumps(response) + "\n").encode())


class Server(socketserver.UnixStreamServer):
    def __init__(self, sock=None, path=SOCK_PATH):
        if sock is None:
            super().__init__(path, Handler)
            self.owns_path = True
        else:
            super().__init__(path, Handler, bind_and_activate=False)
            self.socket.close()
            self.socket = sock
            self.owns_path = False

    def server_close(self):
        super().server_close()
        if self.owns_path and os.path.exists(self.server_address):
            os.remove(self.server_address)


def systemd_socket():
    """Return the listening socket passed in by systemd, if any."""
    if os.environ.get("LISTEN_PID") != str(os.getpid()):
        return None
    if int(os.environ.get("LISTEN_FDS", "0")) < 1:
        return None
    return socket.socket(fileno=3)


def standalone_server():
    if os.path.exists(SOCK_PATH):
        os.remove(SOCK_PATH)
    server = Server(path=SOCK_PATH)
    os.chmod(SOCK_PATH, SOCK_MODE)
    try:
        os.chown(SOCK_PATH, 0, grp.getgrnam(SOCK_GROUP).gr_gid)
    except KeyError:
        log(f"warning: group {SOCK_GROUP!r} not found, only root can connect")
    return server


def stop(signum, frame):
    raise KeyboardInterrupt


def serve(force=False):
    check_model(force)
    check_ec()
    sock = systemd_socket()
    server = Server(sock=sock) if sock else standalone_server()
    signal.signal(signal.SIGTERM, stop)
    log(f"fanctld {version()} listening, current mode {read_mode()}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        restore_auto()


def restore_auto():
    """Hand the fans back to the vendor curve so they never stay on full."""
    try:
        set_mode("auto")
        log("fans restored to auto")
    except OSError as e:
        log(f"could not restore auto mode: {e}")


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="fanctld",
        description="Fan control daemon for the Acer Predator PH315-51.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {version()}")
    parser.add_argument(
        "--reset",
        action="store_true",
        help="write the auto fan mode once and exit (used by the systemd unit)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        default=os.environ.get("FANCTLD_FORCE") == "1",
        help="run on models other than the PH315-51 (dangerous)",
    )
    args = parser.parse_args(argv)
    try:
        if args.reset:
            check_model(args.force)
            check_ec()
            restore_auto()
        else:
            serve(args.force)
    except FanctlError as e:
        log(f"fanctld: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
