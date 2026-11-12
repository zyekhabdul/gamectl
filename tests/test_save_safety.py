#!/usr/bin/env python3
"""Save failure paths on real temporary trees; only failing I/O is substituted."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SaveSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gamectl-save-review-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.game = self.base / "Player's 測試 game"
        self.snapshots = self.game / ".save_snapshots"
        self.snapshots.mkdir(parents=True)
        self.put(self.game / "saves", "active")
        for slot in range(1, 4):
            self.put(self.snapshots / f"slot{slot}", f"snapshot{slot}")
        self.env = dict(os.environ, GAMECTL_TEST_ROOT=str(ROOT),
                        GAMECTL_TEST_GAME=str(self.game), HOME=str(self.base),
                        XDG_RUNTIME_DIR=str(self.base / "runtime"))

    def put(self, directory, content):
        directory.mkdir(exist_ok=True)
        (directory / "save.dat").write_text(content)

    def run_shell(self, script):
        return subprocess.run(["bash", "-c", '''
source "$GAMECTL_TEST_ROOT/src/core/00_header.sh"
source "$GAMECTL_TEST_ROOT/src/core/10_utils.sh"
''' + script], env=self.env, capture_output=True, text=True, timeout=12)

    def assert_original_slots(self):
        for slot in range(1, 4):
            self.assertEqual((self.snapshots / f"slot{slot}/save.dat").read_text(),
                             f"snapshot{slot}")

    def test_backup_reports_each_rename_failure_and_restores_slots(self):
        for step in range(1, 5):
            with self.subTest(rename=step):
                result = self.run_shell('''
count=0
mv() {
    count=$((count + 1))
    [ "$count" -ne ''' + str(step) + ''' ] || return 73
    command mv "$@"
}
backup_save "$GAMECTL_TEST_GAME" true
''')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assert_original_slots()
                self.assertEqual((self.game / "saves/save.dat").read_text(), "active")

    def test_backup_copy_failure_preserves_all_slots(self):
        result = self.run_shell('''
cp() { return 74; }
backup_save "$GAMECTL_TEST_GAME" true
''')
        self.assertNotEqual(result.returncode, 0)
        self.assert_original_slots()
        self.assertFalse((self.snapshots / ".lock").exists())

    def test_save_operations_preserve_callers_signal_traps(self):
        for action in ('backup_save "$GAMECTL_TEST_GAME" true',
                       'restore_save "$GAMECTL_TEST_GAME" 1 true'):
            with self.subTest(action=action):
                result = self.run_shell('''
trap ':' INT TERM
before=$(trap -p INT TERM)
''' + action + ''' || exit 1
[ "$before" = "$(trap -p INT TERM)" ]
''')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_restore_failure_keeps_active_save_and_previous_stash(self):
        self.put(self.snapshots / ".pre_restore_stash", "previous recovery")
        for step in range(1, 4):
            with self.subTest(rename=step):
                result = self.run_shell('''
count=0
mv() {
    count=$((count + 1))
    [ "$count" -ne ''' + str(step) + ''' ] || return 73
    command mv "$@"
}
restore_save "$GAMECTL_TEST_GAME" 1 true
''')
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((self.game / "saves/save.dat").read_text(), "active")
                self.assertEqual((self.snapshots / ".pre_restore_stash/save.dat").read_text(),
                                 "previous recovery")
                self.assert_original_slots()

    def test_restore_copy_failure_keeps_active_save(self):
        result = self.run_shell('''
cp() { return 74; }
restore_save "$GAMECTL_TEST_GAME" 1 true
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.game / "saves/save.dat").read_text(), "active")
        self.assert_original_slots()

    def test_recovery_does_not_mutate_under_another_owners_lock(self):
        (self.game / "saves/save.dat").unlink()
        (self.game / "saves").rmdir()
        self.put(self.snapshots / ".pre_restore_stash", "recovery")
        lock = self.snapshots / ".lock"
        lock.mkdir()
        (lock / "pid").write_text(str(os.getpid()))
        result = self.run_shell('restore_save "$GAMECTL_TEST_GAME" 1 true')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.game / "saves").exists())
        self.assertEqual((self.snapshots / ".pre_restore_stash/save.dat").read_text(), "recovery")

    def test_termination_does_not_commit_or_overwrite_parent_traps(self):
        result = self.run_shell('''
cp() { command cp "$@" || return; kill -TERM "$BASHPID"; }
backup_save "$GAMECTL_TEST_GAME" true
''')
        self.assertNotEqual(result.returncode, 0)
        self.assert_original_slots()
        self.assertFalse((self.snapshots / ".lock").exists())

    def test_two_real_writers_keep_exclusive_lock_with_actual_owner_pid(self):
        script = '''
source "$GAMECTL_TEST_ROOT/src/core/00_header.sh"
source "$GAMECTL_TEST_ROOT/src/core/10_utils.sh"
cp() {
    echo "$BASHPID" > "$GAMECTL_TEST_GAME/ready"
    while [ ! -e "$GAMECTL_TEST_GAME/release" ]; do sleep 0.05; done
    command cp "$@"
}
backup_save "$GAMECTL_TEST_GAME" true
'''
        with subprocess.Popen(["bash", "-c", script], env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as writer:
            try:
                deadline = time.monotonic() + 4
                while not (self.game / "ready").exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue((self.game / "ready").exists())
                owner = (self.game / "ready").read_text().strip()
                self.assertEqual((self.snapshots / ".lock/pid").read_text().strip(), owner)
                result = self.run_shell('backup_save "$GAMECTL_TEST_GAME" true')
                self.assertNotEqual(result.returncode, 0)
                self.assert_original_slots()
                self.assertEqual((self.snapshots / ".lock/pid").read_text().strip(), owner)
            finally:
                (self.game / "release").touch()
                stdout, stderr = writer.communicate(timeout=6)
            self.assertEqual(writer.returncode, 0, stdout + stderr)
        self.assertFalse((self.snapshots / ".lock").exists())

    def test_restore_rollback_preserves_symlink_and_external_save(self):
        external = self.base / "external"
        self.put(external, "external save")
        (self.game / "saves/save.dat").unlink()
        (self.game / "saves").rmdir()
        (self.game / "saves").symlink_to(external, target_is_directory=True)
        result = self.run_shell('''
count=0
mv() {
    count=$((count + 1))
    [ "$count" -ne 2 ] || return 73
    command mv "$@"
}
restore_save "$GAMECTL_TEST_GAME" 1 true
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.game / "saves").is_symlink())
        self.assertEqual((external / "save.dat").read_text(), "external save")

    def test_failed_rollback_retains_every_save_and_blocks_next_writer(self):
        for action in ('backup_save "$GAMECTL_TEST_GAME" true',
                       'restore_save "$GAMECTL_TEST_GAME" 1 true'):
            with self.subTest(action=action):
                # Each action uses a fresh tree, including a previous restore stash.
                self.put(self.snapshots / ".pre_restore_stash", "previous recovery")
                result = self.run_shell('''
count=0
mv() {
    count=$((count + 1))
    [ "$count" -lt ''' + ("4" if action.startswith("backup") else "3") + ''' ] || return 73
    command mv "$@"
}
''' + action)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("rollback incomplete", result.stderr)
                self.assertTrue((self.snapshots / ".lock").is_dir())
                retained = {path.read_text() for path in self.game.rglob("save.dat")}
                self.assertTrue({"active", "snapshot1", "snapshot2", "snapshot3",
                                 "previous recovery"}.issubset(retained))
                blocked = self.run_shell('backup_save "$GAMECTL_TEST_GAME" true')
                self.assertNotEqual(blocked.returncode, 0)
                # Restore this test's fixture before the next action.
                shutil.rmtree(self.game)
                self.snapshots.mkdir(parents=True)
                self.put(self.game / "saves", "active")
                for slot in range(1, 4):
                    self.put(self.snapshots / f"slot{slot}", f"snapshot{slot}")


if __name__ == "__main__":
    unittest.main()
