#!/usr/bin/env python3
"""Exercise real menu previews and failing fzf processes through a terminal."""
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import termios
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class TuiSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gamectl-tui-review-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.marker = self.base / "INJECTION_TRIGGERED"
        self.game = Path(str(self.base / "Player's 測試 game; touch ") +
                         str(self.marker) + "; echo 'test")
        backup = self.game / ".gamectl_fix_backup"
        (backup / "20261112_100000/backup_files").mkdir(parents=True)
        (backup / "latest.json").write_text(json.dumps({
            "timestamp": "20261112_100000", "appid": "105600",
            "fix_title": "SafeFixPreviewReached", "backed_up_count": 1}))
        cache = self.base / "cache/gamectl"
        cache.mkdir(parents=True)
        (cache / "luatools_fixes_105600.json").write_text('{"fixes": []}')
        self.env = dict(os.environ, HOME=str(self.base), SHELL="/bin/sh",
                        TERM="xterm-256color", XDG_CACHE_HOME=str(self.base / "cache"),
                        XDG_RUNTIME_DIR=str(self.base / "runtime"))

    def run_pty(self, argv, preview_text=None):
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 220, 0, 0))
            os.execvpe(str(argv[0]), [str(arg) for arg in argv], self.env)
        output = bytearray()
        status = None
        dismissed = False
        try:
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if select.select([fd], [], [], 0.05)[0]:
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        chunk = b""
                    output.extend(chunk)
                    if b"\x1b[6n" in chunk:
                        os.write(fd, b"\x1b[1;1R")
                if preview_text and preview_text in output and not dismissed:
                    os.write(fd, b"\x1b")
                    dismissed = True
                done, status_now = os.waitpid(pid, os.WNOHANG)
                if done:
                    status = status_now
                    break
            self.assertIsNotNone(status, bytes(output).decode(errors="replace")[-2000:])
            if preview_text:
                self.assertTrue(dismissed, "Menu exited without rendering the real preview")
            return os.waitstatus_to_exitcode(status), bytes(output)
        finally:
            if status is None:
                os.killpg(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(fd)

    def test_real_fzf_renders_preview_with_shell_characters_and_escaped_binary_path(self):
        self.assertIsNotNone(shutil.which("fzf"), "Real fzf is required for this test")
        binary = self.base / "tool's $HOME; `false`" / "game ctl"
        binary.parent.mkdir()
        shutil.copy2(ROOT / "bin/gamectl", binary)
        rc, output = self.run_pty([binary, "fixes", "105600", "Player's 測試", self.game],
                                  b"SafeFixPreviewReached")
        self.assertEqual(rc, 0, output.decode(errors="replace")[-2000:])
        self.assertFalse(self.marker.exists())

    def test_fzf_errors_leave_menus_with_original_status(self):
        stub_dir = self.base / "stubs"
        stub_dir.mkdir()
        stub = stub_dir / "fzf"
        self.env["PATH"] = str(stub_dir) + os.pathsep + os.environ["PATH"]
        for code in (2, 127):
            stub.write_text(f"#!/bin/sh\nexit {code}\n")
            stub.chmod(0o755)
            for args in (["fixes", "105600", "Test", self.game], ["logs"], ["library"], []):
                with self.subTest(code=code, menu=args[:1]):
                    rc, output = self.run_pty([ROOT / "bin/gamectl", *args])
                    self.assertEqual(rc, code, output.decode(errors="replace")[-2000:])
                    self.assertIn(b"[ERROR]", output)


if __name__ == "__main__":
    unittest.main()
