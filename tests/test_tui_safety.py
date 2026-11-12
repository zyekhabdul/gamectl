#!/usr/bin/env python3
"""Exercise real menu previews and failing fzf processes through a terminal."""
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import subprocess
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
                        XDG_RUNTIME_DIR=str(self.base / "runtime"),
                        TEST_ROOT=str(ROOT), TEST_GAME=str(self.game))

    def run_shell(self, script):
        return subprocess.run(["bash", "-c", 'source "$TEST_ROOT/bin/gamectl"\n' + script],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def scripted_fzf(self, responses):
        stub_dir = self.base / "stubs"
        stub_dir.mkdir(exist_ok=True)
        script = stub_dir / "fzf"
        script.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
base = pathlib.Path(os.environ["HOME"])
counter = base / "fzf-counter"
index = int(counter.read_text()) if counter.exists() else 0
counter.write_text(str(index + 1))
steps = json.loads(os.environ["TEST_FZF_STEPS"])
code, output = steps[index] if index < len(steps) else (130, "")
(base / "fzf-input").write_text(sys.stdin.read())
sys.stdout.write(output)
sys.exit(code)
''')
        script.chmod(0o755)
        (self.base / "fzf-counter").unlink(missing_ok=True)
        self.env["PATH"] = str(stub_dir) + os.pathsep + os.environ["PATH"]
        self.env["TEST_FZF_STEPS"] = json.dumps(responses)

    def test_scanner_rejects_row_separators_and_preserves_literal_backslashes(self):
        library = self.base / "library"
        valid = library / "Player's 測試 \\t game"
        for directory in (valid, library / "bad\ttab", library / "bad\nline"):
            directory.mkdir(parents=True)
            (directory / "game.exe").touch()
        self.env["GAMECTL_LIBRARY_DIR"] = str(library)
        result = self.run_shell('scan_installed_games --formatted --refresh')
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = result.stdout.splitlines()
        self.assertEqual(len(rows), 1, result.stdout)
        fields = rows[0].split("\t")
        self.assertEqual(len(fields), 5, fields)
        self.assertEqual(fields[3], str(valid))
        self.assertIn("\\t", fields[1])
        self.assertIn("[ERROR]", result.stderr)

    def test_scanner_rejects_multiline_titles_executables_and_legacy_cache(self):
        library = self.base / "library"
        for name in ("Metadata", "Executable"):
            (library / name).mkdir(parents=True)
        (library / "Metadata/game.exe").touch()
        (library / "Metadata/.gamectl_title").write_text("bad\nmetadata\n")
        executable = library / "Executable/game.exe\n"
        executable.touch()
        executable.chmod(0o755)
        self.env["GAMECTL_LIBRARY_DIR"] = str(library)
        runtime = Path(self.env["XDG_RUNTIME_DIR"])
        runtime.mkdir()
        (runtime / "scancache.tab").write_text("1\tForged\tSTANDALONE\t/wrong/path\tgame.exe\n")
        result = self.run_shell('scan_installed_games --formatted')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("[ERROR]", result.stderr)
        self.assertNotIn("/wrong/path", (runtime / "scancache.tab").read_text())

    def test_nested_fzf_failure_reaches_dashboard(self):
        self.scripted_fzf([(0, "\n5\tSettings\n"), (2, "")])
        rc, output = self.run_pty([ROOT / "bin/gamectl"])
        self.assertEqual(rc, 2, output.decode(errors="replace")[-2000:])

    def test_all_nested_selection_failures_preserve_error_status(self):
        self.game.joinpath(".save_snapshots/slot1").mkdir(parents=True)
        self.game.joinpath(".save_snapshots/slot2").mkdir()
        row = f"105600\tTest\tSTANDALONE\t{self.game}\tgame.exe\n"
        self.env["TEST_INSTALLED_ROW"] = row
        steamapps = self.base / "steamapps"
        steamapps.mkdir()
        acf = steamapps / "appmanifest_105600.acf"
        acf.write_text('"appid" "105600"\n"name" "Test"\n"StateFlags" "1024"\n')
        self.env["TEST_STEAMAPPS"] = str(steamapps)
        log = self.base / "process's log"
        log.write_text("Test process log\n")
        self.env["TEST_LOG"] = str(log)
        (self.base / "cache/gamectl/luatools_fixes_105600.json").write_text(json.dumps({
            "fixes": [{"id": 51, "title": "Fix", "fixFilename": "fix.zip", "hasFix": True}]}))
        setup = '''
source "$TEST_ROOT/bin/gamectl"
clean_stale_locks() { :; }
scan_installed_games() { :; }
fetch_cached_json() { printf '%s' '{"105600":{"data":{"name":"Test"}}}'; }
curl() { printf '%s' '{"items":[{"id":105600,"name":"Test"}]}'; }
resolve_target_library_dir() { printf '%s' "$HOME/library"; }
detect_app_platform_os() { echo linux; }
doctor_audit() { echo diagnostics; }
get_steam_primary_apps() { printf '%s' "$TEST_STEAMAPPS"; }
'''
        hud = '''sleep 30 & test_pid=$!
trap 'rc=$?; kill "$test_pid"; wait "$test_pid" 2>/dev/null; exit "$rc"' EXIT
game_controller_hud "$test_pid" Test "$TEST_LOG" "$TEST_GAME" game.exe "$TEST_GAME/info" native'''
        cases = [
            ('configure_global', []),
            ('configure_global', ["1\tPersona\n"]),
            ('configure_global', ["1\tPersona\n", "Name\n"]),
            ('configure_global', ["2\tWrappers\n"]),
            ('configure_global', ["3\tLibraries\n"]),
            ('configure_global', ["3\tLibraries\n", "add\tAdd\n"]),
            ('configure_global', ["4\tRemote\n"]),
            ('configure_wrappers "$TEST_GAME"', []),
            ('set_id_interactive "$TEST_GAME"', []),
            ('set_id_interactive "$TEST_GAME"', ["Name\n"]),
            ('set_id_interactive "$TEST_GAME"', ["Name\n", "76561198000000001\n"]),
            ('set_id_interactive "$TEST_GAME"', ["Name\n", "76561198000000001\n", "\n"]),
            ('search_steam Test', ["\n105600\tTest\t[NOT INSTALLED]\n"]),
            ('scan_installed_games() { printf "%s" "$TEST_INSTALLED_ROW"; }; search_steam Test',
             ["\n105600\tTest\t[INSTALLED]\n"]),
            ('unlock_interactive', ["105600\n"]),
            ('library_menu', ["ctrl-r\n" + row]),
            ('dashboard_menu', ["\n6\tDiagnostics\n"]),
            ('manage_game_fixes_interactive 105600 Test "$TEST_GAME"', ["[RESTORE]\tRestore\n"]),
            ('manage_game_fixes_interactive 105600 Test "$TEST_GAME"', ["51\tFix\t[READY]\tfix.zip\n"]),
            ('manage_prefix "$TEST_GAME"', []),
            ('tui_modal_notice Test Message', []),
            ('list_downloads_interactive', [f"\n105600\tSteam\t[DOWNLOADING]\t0%\tTest\t{acf}\n"]),
            (hud, []),
            (hud, ["3\tLogs\n"]),
        ]
        cases += [('dashboard_menu', [f"\n{number}\tMenu\n"]) for number in (1, 2, 3, 4, 5, 7)]
        for code in (2, 127):
            for command, choices in cases:
                with self.subTest(code=code, command=command, depth=len(choices)):
                    self.scripted_fzf([(0, text) for text in choices] + [(code, "")])
                    rc, output = self.run_pty(["bash", "-c", setup + command])
                    self.assertEqual(rc, code, output.decode(errors="replace")[-2000:])
                    self.assertIn(b"[ERROR]", output)
                    self.assertEqual(int((self.base / "fzf-counter").read_text()), len(choices) + 1)
                    self.assertFalse((self.game / "steam_settings/configs.user.ini").exists())

    def test_catalog_separators_are_rejected_before_selection(self):
        setup = '''source "$TEST_ROOT/bin/gamectl"
curl() { printf '%s' "$TEST_CATALOG"; }
'''
        for separator in ("\t", "\n", "\r"):
            self.env["TEST_CATALOG"] = json.dumps({"items": [{"id": 1, "name": "bad" + separator + "title"}]})
            for command, steps in (("search_steam Test", []), ("unlock_interactive", [(0, "Test\n")])):
                with self.subTest(separator=repr(separator), command=command):
                    self.scripted_fzf(steps)
                    rc, output = self.run_pty(["bash", "-c", setup + command])
                    self.assertEqual(rc, 1, output.decode(errors="replace"))
                    self.assertIn(b"[ERROR]", output)
                    count = self.base / "fzf-counter"
                    self.assertEqual(int(count.read_text()) if count.exists() else 0, len(steps))

    def test_acf_parser_remains_standalone_and_rejects_separators(self):
        acf = self.base / "game's manifest.acf"
        self.env["TEST_ACF"] = str(acf)
        for title in ("Test \\t literal", "bad\ttitle", "bad\rtitle"):
            acf.write_text(f'"appid" "105600"\n"name" "{title}"\n"StateFlags" "4"\n')
            result = subprocess.run(["bash", "-c", '''
source "$TEST_ROOT/src/steam/30_downloader.sh"
parse_acf_download_state "$TEST_ACF"
'''], env=self.env, capture_output=True, text=True, timeout=5)
            if "\\t" in title:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.split("\t")[1], title)
            else:
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("[ERROR]", result.stderr)

    def test_fix_catalog_preserves_backslashes_and_rejects_separators(self):
        cache = self.base / "cache/gamectl/luatools_fixes_105600.json"
        for title in ("Fix \\t literal", "bad\ttitle", "bad\ntitle"):
            cache.write_text(json.dumps({"fixes": [{"id": 51, "title": title,
                                                    "fixFilename": "fix.zip", "hasFix": True}]}))
            self.scripted_fzf([(130, "")])
            rc, output = self.run_pty([ROOT / "bin/gamectl", "fixes", "105600", "Test", self.game])
            if "\\t" in title:
                self.assertEqual(rc, 0, output.decode(errors="replace"))
                self.assertIn("51\t" + title + "\t", (self.base / "fzf-input").read_text())
            else:
                self.assertEqual(rc, 1, output.decode(errors="replace"))
                self.assertIn(b"[ERROR]", output)
                self.assertFalse((self.base / "fzf-counter").exists())

    def test_no_match_and_cancel_remain_normal_menu_results(self):
        for command in ('dashboard_menu', 'library_menu', 'configure_global'):
            self.scripted_fzf([(1, ""), (130, "")])
            rc, output = self.run_pty(["bash", "-c", 'source "$TEST_ROOT/bin/gamectl"\n' + command])
            self.assertEqual(rc, 0, output.decode(errors="replace"))
            self.assertEqual((self.base / "fzf-counter").read_text(), "2")

    def test_real_prefix_and_hud_previews_preserve_shell_characters(self):
        log = self.base / "worker's $HOME log"
        log.write_text("HudLogPreviewReached\n")
        self.env["TEST_LOG"] = str(log)
        setup = 'source "$TEST_ROOT/bin/gamectl"\n'
        rc, output = self.run_pty(["bash", "-c", setup + 'manage_prefix "$TEST_GAME"'],
                                  b"WINE PREFIX OVERVIEW")
        self.assertEqual(rc, 0, output.decode(errors="replace")[-1000:])
        hud = '''sleep 30 & test_pid=$!
trap 'rc=$?; kill "$test_pid"; wait "$test_pid" 2>/dev/null; exit "$rc"' EXIT
game_controller_hud "$test_pid" "Player's 測試 $HOME" "$TEST_LOG" "$TEST_GAME" game.exe "$TEST_GAME/info" native'''
        rc, output = self.run_pty(["bash", "-c", setup + hud], b"HudLogPreviewReached")
        self.assertEqual(rc, 0, output.decode(errors="replace")[-1000:])
        self.assertFalse(self.marker.exists())

    def test_missing_fzf_and_non_terminal_entrypoints_fail_promptly(self):
        commands = ('configure_global', 'configure_wrappers "$TEST_GAME"',
                    'set_id_interactive "$TEST_GAME"', 'manage_prefix "$TEST_GAME"')
        for command in commands:
            result = self.run_shell(command)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("TTY", result.stderr)
        path = self.base / "without-fzf"
        path.mkdir()
        for executable in ("bash", "readlink"):
            (path / executable).symlink_to(shutil.which(executable))
        self.env["PATH"] = str(path)
        for command in (*commands, "dashboard_menu", "library_menu", "search_steam Test", "unlock_interactive"):
            rc, output = self.run_pty(["bash", "-c", 'source "$TEST_ROOT/bin/gamectl"\n' + command])
            self.assertEqual(rc, 127, output.decode(errors="replace"))
            self.assertIn(b"[ERROR]", output)

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
