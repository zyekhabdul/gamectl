#!/usr/bin/env python3
"""Standalone failure paths on temporary files, without Steam or network access."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]


class StandaloneSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gamectl-standalone-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.game = self.base / "Game's directory"
        self.game.mkdir()
        self.original = b"original library fixture"
        self.library = self.game / "libsteam_api.so"
        self.library.write_bytes(self.original)
        self.template = self.base / "template.so"
        self.template.write_bytes(b"replacement library fixture")
        self.script = self.game / "game.sh"
        self.script.write_text("#!/usr/bin/env bash\necho started > ran\nsleep 0.1\n")
        self.script.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GAMECTL_")}
        self.env.update(HOME=str(self.base), XDG_CONFIG_HOME=str(self.base / "config"),
                        XDG_CACHE_HOME=str(self.base / "cache"),
                        XDG_RUNTIME_DIR=str(self.base / "runtime"),
                        TEST_ROOT=str(ROOT), TEST_GAME=str(self.game),
                        TEST_TEMPLATE=str(self.template))

    def run_shell(self, script):
        setup = '''
source "$TEST_ROOT/bin/gamectl"
log_msg() { :; }
invalidate_scan_cache() { :; }
fetch_dlc() { :; }
resolve_active_steamid() { echo 76561198000000000; }
find_game_binary() { echo game.sh; }
get_gbe_template() { printf '%s\\n' "$TEST_TEMPLATE"; }
setup_gbe_templates() { return 1; }
sync_steam() { echo "$*" >> "$HOME/sync.calls"; }
setup_steam_interceptor() { :; }
detect_steamstub_drm() { return 1; }
clean_stale_locks() { :; }
backup_save() { :; }
check_systemd_scope_support() { return 0; }
build_wrapper_command() {
    GAMECTL_WRAPPER_PREFIX=() GAMECTL_REMAINING_ARGS=()
    GAMECTL_ACTIVE_GLTHREAD=0 GAMECTL_ACTIVE_PRIME=0
    GAMECTL_ACTIVE_SYSTEMD_SCOPE="${TEST_SCOPE:-0}" GAMECTL_ACTIVE_SANDBOX=0
}
'''
        process = subprocess.Popen(["bash", "-c", setup + script], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=12)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def test_missing_templates_fail_without_success_or_library_changes(self):
        result = self.run_shell('''
get_gbe_template() { return 1; }
inject_game "$TEST_GAME" 123 --no-sync
''')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("successfully injected", result.stdout)
        self.assertEqual(self.library.read_bytes(), self.original)

    def test_missing_windows_template_fails(self):
        library = self.game / "steam_api64.dll"
        library.write_bytes(self.original)
        result = self.run_shell('''
get_gbe_template() { [ "$1" != windows ] && echo "$TEST_TEMPLATE"; }
inject_game "$TEST_GAME" 123 --no-sync
''')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(library.read_bytes(), self.original)

    def test_metadata_failure_is_not_reported_as_success(self):
        (self.game / "steam_settings").write_text("existing file")
        result = self.run_shell('inject_game "$TEST_GAME" 123')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("successfully injected", result.stdout)

    def test_copy_and_backup_failures_preserve_the_original(self):
        for failure in ("copy", "backup"):
            with self.subTest(failure=failure):
                backup = Path(str(self.library) + ".orig")
                backup.unlink(missing_ok=True)
                self.env["TEST_FAILURE"] = failure
                result = self.run_shell('''
cp() {
    if [ "$TEST_FAILURE" = copy ] && [ "$1" = "$TEST_TEMPLATE" ]; then
        printf partial > "${@: -1}"
        return 74
    fi
    if [ "$TEST_FAILURE" = backup ] && [ "$1" = -a ]; then
        printf partial > "${@: -1}"
        return 74
    fi
    command cp "$@"
}
inject_game "$TEST_GAME" 123 --no-sync
''')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.library.read_bytes(), self.original)
                self.assertNotIn("successfully injected", result.stdout)
                self.assertEqual(list(self.game.glob("*.gamectl.*")), [])
                if failure == "backup":
                    self.assertFalse(backup.exists())

    def test_backup_or_size_alone_does_not_allow_launch(self):
        for state in ("backup", "large"):
            with self.subTest(state=state):
                self.library.write_bytes(self.original)
                backup = Path(str(self.library) + ".orig")
                backup.unlink(missing_ok=True)
                if state == "backup":
                    backup.write_bytes(self.original)
                else:
                    with self.library.open("r+b") as stream:
                        stream.truncate(6000000)
                result = self.run_shell('''
inject_game() { return 23; }
launch_game "$TEST_GAME" game.sh Test < /dev/null
''')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("HARD-STOP", result.stdout + result.stderr)
                self.assertFalse((self.game / "ran").exists())

    def test_default_injection_is_offline_and_all_remains_explicit(self):
        result = self.run_shell('inject_game "$TEST_GAME" 123')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.library.read_bytes(), self.template.read_bytes())
        self.assertEqual(Path(str(self.library) + ".orig").read_bytes(), self.original)
        self.assertFalse((self.base / "sync.calls").exists())
        result = self.run_shell('inject_game "$TEST_GAME" 123 --all')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len((self.base / "sync.calls").read_text().splitlines()), 1)

    def test_matching_template_can_launch_without_an_orig_marker(self):
        self.library.write_bytes(self.template.read_bytes())
        result = self.run_shell('''
inject_game() { return 23; }
launch_game "$TEST_GAME" game.sh Test < /dev/null
''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.game / "ran").exists())

    def test_onlinefix_does_not_register_spacewar_implicitly(self):
        (self.game / "OnlineFix64.dll").touch()
        result = self.run_shell('setup_onlinefix "$TEST_GAME" --yes')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.base / "sync.calls").exists())

    def test_injection_replaces_every_library_and_skips_prefixes(self):
        libraries = [self.library]
        for name in ("bin/libsteam_api.so", "win/steam_api64.dll", "win/steam_api.dll"):
            library = self.game / name
            library.parent.mkdir(exist_ok=True)
            library.write_bytes(self.original)
            libraries.append(library)
        prefix_library = self.game / "pfx/libsteam_api.so"
        prefix_library.parent.mkdir()
        prefix_library.write_bytes(self.original)
        result = self.run_shell('inject_game "$TEST_GAME" 123')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for library in libraries:
            self.assertEqual(library.read_bytes(), self.template.read_bytes(), str(library))
        self.assertEqual(prefix_library.read_bytes(), self.original)

    def test_download_propagates_injection_failure(self):
        with zipfile.ZipFile(self.base / "manifest.zip", "w") as archive:
            archive.writestr("123_1.manifest", bytes.fromhex("d017f671"))
            archive.writestr("123.lua", 'addappid(123, 1, "' + "00" * 32 + '")\n')
        downloader = self.base / "downloader"
        downloader.write_text("#!/usr/bin/env bash\nexit 0\n")
        downloader.chmod(0o755)
        result = self.run_shell('''
fetch_manifest() { echo "$HOME/manifest.zip"; }
harvest_dlc_manifests() { :; }
resolve_depot_dl_bin() { echo "$HOME/downloader"; }
inject_game() { return 23; }
download_game 123 "$TEST_GAME" Test
''')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("provisioning complete", result.stdout)

    def test_tracking_survives_until_the_game_exits(self):
        self.library.unlink()
        self.script.write_text('''#!/usr/bin/env bash
echo $$ > game.pid
while [ ! -f release ]; do sleep 0.02; done
''')
        result = self.run_shell('''
old_path="$PATH"
launch_game "$TEST_GAME" game.sh Test < /dev/null > "$HOME/launch.log" 2>&1
rc=$?
trap 'touch "$TEST_GAME/release"; wait' EXIT
[ "$rc" -eq 0 ] || exit "$rc"
[ "$PATH" = "$old_path" ] || exit 4
for _ in {1..100}; do [ -s "$TEST_GAME/game.pid" ] && break; sleep 0.01; done
pid=$(cat "$TEST_GAME/game.pid")
info="$(get_runtime_dir)/active_games/$pid.info"
sleep 0.1
kill -0 "$pid" || exit 2
[ -f "$info" ] || exit 3
[ ! -f "$HOME/scope.calls" ] || exit 5
touch "$TEST_GAME/release"
wait "$pid"
for _ in {1..100}; do [ ! -f "$info" ] && break; sleep 0.02; done
[ ! -f "$info" ] || exit 6
[ "${TEST_SCOPE:-0}" != 1 ] || [ -s "$HOME/scope.calls" ]
''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_scope_is_stopped_only_after_the_game_exits(self):
        stubs = self.base / "stubs"
        stubs.mkdir()
        (stubs / "systemd-run").write_text('''#!/usr/bin/env bash
while [[ "$1" == --* ]]; do shift; done
exec "$@"
''')
        (stubs / "systemctl").write_text('''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$HOME/scope.calls"
''')
        for stub in stubs.iterdir():
            stub.chmod(0o755)
        self.env.update(TEST_SCOPE="1", PATH=str(stubs) + os.pathsep + self.env["PATH"])
        self.test_tracking_survives_until_the_game_exits()


if __name__ == "__main__":
    unittest.main()
