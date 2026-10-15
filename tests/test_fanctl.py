import importlib.machinery
import importlib.util
import io
import json
import os
import socket
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class FakeHardware(unittest.TestCase):
    """A fake EC register file and DMI model, wired into fresh module copies."""

    model = "Predator PH315-51"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tmp = Path(self.tmp.name)
        self.ec = tmp / "io"
        self.ec.write_bytes(bytes(256))
        self.dmi = tmp / "product_name"
        self.dmi.write_text(self.model + "\n")
        self.sock = str(tmp / "fanctld.sock")

        self.daemon = load("fanctld", ROOT / "cmd" / "fanctld.py")
        self.daemon.EC_PATH = str(self.ec)
        self.daemon.DMI_PATH = str(self.dmi)
        self.daemon.SOCK_PATH = self.sock
        self.client = load("fanctl", ROOT / "cmd" / "fanctl")
        self.client.SOCK_PATH = self.sock

    def tearDown(self):
        self.tmp.cleanup()

    def register(self, offset):
        return self.ec.read_bytes()[offset]


class ModeTests(FakeHardware):
    def test_blank_ec_reads_as_unknown(self):
        self.assertEqual(self.daemon.read_mode(), "unknown")

    def test_set_mode_writes_registers_and_reads_back(self):
        self.assertEqual(self.daemon.set_mode("full"), "full")
        self.assertEqual((self.register(0x22), self.register(0x21)), (0x58, 0x60))
        self.assertEqual(self.daemon.set_mode("auto"), "auto")
        self.assertEqual((self.register(0x22), self.register(0x21)), (0x54, 0x50))

    def test_status_reflects_ec_after_daemon_restart(self):
        self.daemon.set_mode("full")
        fresh = load("fanctld_again", ROOT / "cmd" / "fanctld.py")
        fresh.EC_PATH = str(self.ec)
        self.assertEqual(fresh.handle_command("status"), {"ok": True, "mode": "full"})

    def test_unknown_command_is_rejected_without_writes(self):
        before = self.ec.read_bytes()
        response = self.daemon.handle_command("rm -rf /")
        self.assertFalse(response["ok"])
        self.assertEqual(self.ec.read_bytes(), before)

    def test_missing_ec_reports_error_instead_of_crashing(self):
        self.ec.unlink()
        response = self.daemon.handle_command("full")
        self.assertFalse(response["ok"])
        self.assertIn("EC access failed", response["error"])

    def test_restore_auto(self):
        self.daemon.set_mode("full")
        with redirect_stderr(io.StringIO()):
            self.daemon.restore_auto()
        self.assertEqual(self.daemon.read_mode(), "auto")


class ModelCheckTests(FakeHardware):
    model = "Nitro AN515-55"

    def test_other_models_are_refused(self):
        with self.assertRaises(self.daemon.FanctlError):
            self.daemon.check_model()

    def test_force_overrides_model_check(self):
        with redirect_stderr(io.StringIO()):
            self.daemon.check_model(force=True)

    def test_reset_refuses_on_other_models(self):
        with redirect_stderr(io.StringIO()):
            self.assertEqual(self.daemon.main(["--reset"]), 1)
        self.assertEqual(self.ec.read_bytes(), bytes(256))


class SocketTests(FakeHardware):
    def setUp(self):
        super().setUp()
        self.server = self.daemon.Server(path=self.sock)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        super().tearDown()

    def run_client(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            code = self.client.main(list(argv))
        return code, json.loads(out.getvalue())

    def test_client_switches_modes(self):
        self.assertEqual(self.run_client("full"), (0, {"ok": True, "mode": "full"}))
        self.assertEqual(self.run_client(), (0, {"ok": True, "mode": "full"}))
        self.assertEqual(self.run_client("auto"), (0, {"ok": True, "mode": "auto"}))

    def test_oversized_command_is_cut_off(self):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(self.sock)
            s.sendall(b"full" * 1000 + b"\n")
            reply = json.loads(s.makefile().readline())
        self.assertFalse(reply["ok"])
        self.assertEqual(self.register(0x22), 0)

    def test_socket_file_is_removed_on_close(self):
        self.server.shutdown()
        self.server.server_close()
        self.assertFalse(os.path.exists(self.sock))
        self.server = self.daemon.Server(path=self.sock)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()


class SocketActivationTests(FakeHardware):
    def test_server_uses_passed_socket_and_leaves_path_to_systemd(self):
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(self.sock)
        listener.listen()
        server = self.daemon.Server(sock=listener)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertEqual(self.client.main(["auto"]), 0)
            self.assertEqual(json.loads(out.getvalue())["mode"], "auto")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        self.assertTrue(os.path.exists(self.sock))


class ClientErrorTests(FakeHardware):
    def test_daemon_not_running(self):
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            code = self.client.main(["status"])
        self.assertEqual(code, self.client.EXIT_UNREACHABLE)
        self.assertFalse(json.loads(out.getvalue())["ok"])

    def test_bad_command_is_a_usage_error(self):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(self.client.main(["turbo"]), self.client.EXIT_USAGE)

    def test_version_flag_exits_cleanly(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(self.client.main(["--version"]), 0)


if __name__ == "__main__":
    unittest.main()
