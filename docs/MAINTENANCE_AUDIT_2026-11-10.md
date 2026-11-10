# Maintenance audit — 2026-11-10

## Scope and objective

Audited upstream `bbd4e18` with the existing uncommitted maintenance changes
preserved. The project aims to provide a lightweight Linux game library,
launcher, isolated runners, portable save recovery, and companion-device sync.
The highest-value work is making those operations reliable under failure before
adding more commands or optimizing startup. This audit adds documentation only;
the runtime findings below remain open.

## Verification results

| Check | Result | Limits |
| --- | --- | --- |
| `make lint` | PASS | Uses the local per-file lint fix; syntax validation, not ShellCheck. |
| `scripts/build.sh --check` | PASS | Bash bundle matches sources. |
| `scripts/build-depot-dl.sh --check` | PASS | Checks only presence and executable bit, not source provenance or freshness. |
| CLI regression suite | **122/122 PASS** | Isolated HOME/XDG paths; network access enabled for public artwork/catalog tests. |
| CLI suite without external network | 120/122 PASS | Artwork and fix catalog tests require live services. |
| Python sdist and wheel build | PASS | `python -m build --no-isolation` using a temporary virtualenv. |
| Installed wheel `--version` / `--help` | PASS | Linux x86-64 host only. |
| Debian packaging | PASS in CLI suite | Successfully builds and validates package metadata; not an installation test. |
| Dashboard PTY smoke test | PASS | Esc exits 0; DEC alternate-screen enter and exit both observed. No visual/hardware gameplay certification. |
| Rust test / Clippy / rustfmt | BLOCKED | All three attempted; `cargo` is absent. Rust build and execution from source remain unverified. |
| ShellCheck / mutation / CVE scan | NOT RUN | Tools are not available; do not interpret the passing suite as security certification. |
| Real games, GPU/Proton, Steam Deck, real remote sync | NOT RUN | No representative devices, game fixtures, or authorized remote target used. |

Tooling was isolated in `/tmp`: Python build tooling/PyYAML in a virtualenv,
and `zip`/`dpkg-deb` extracted from distro packages without system installation.
The existing suite rebuilds generated artifacts as part of packaging tests.

## Confirmed findings, ordered by impact

### P1 — Save restore destroys live data before verifying copies

Location: `src/core/10_utils.sh:476-489` (`restore_save`).

Both stash and snapshot copy errors are swallowed with `|| true`. Live save files
are removed before the snapshot copy is known to succeed. A local fixture that
overrides `cp` to return 1 produced `restore_rc=0`, with neither the original nor
the restored file present. No real game files were touched.

Action: stage the selected snapshot and validate the copy before replacing live
saves; stop if the safety backup fails; preserve old saves until commit; propagate
errors and provide rollback. Test failed staging, failed backup, failed rename,
hidden files, symlinked paths, and insufficient storage.

### P1 — Background watchdog waits for a process it does not own

Location: `src/runners/50_launcher.sh:576-591`.

The game is launched by the parent shell, but a separate watchdog subshell calls
`wait "$game_pid"`. Bash cannot wait for a sibling process. A minimal fixture
returned `watchdog_wait_rc=127` while `kill -0` confirmed the game was alive.
Cleanup can therefore run too soon, remove active-game metadata, and attempt to
stop a scope while the game is still running.

Action: use one supervisor shell that launches and waits for its own child,
propagates exit status, owns cleanup, and runs cleanup exactly once. Verify
long-running native fixtures, early launch failure, nonzero exit, and signals.

### P1 — Remote sync reports success after transfer failure

Location: `src/runners/50_launcher.sh:665-670,726-742`.

With local mocks `ssh() { return 0; }` and `rsync() { return 23; }`, push and pull
both returned 0 and printed `[VERIFIED]`. Pull also ignores backup failure.

Action: check remote-directory creation, backup, and transfer exit status. Abort
pull before overwriting data if backup fails. Emit success only after successful
transfer. Add partial-transfer, unreachable-host, remote mkdir, and backup-failure
tests; surface the actual status to the TUI.

### P2 — Quoted remote tilde prevents normal home-directory resolution

Location: `src/runners/50_launcher.sh:662,719`.

Remote commands contain `mkdir -p "~/..."` and `[ -d "~/.../saves" ]`.
Inside quotes the tilde is literal. A local shell fixture showed the quoted path
check failing while the actual directory existed. Existing success mocks do not
execute or validate the remote shell command.

Action: pass remote paths with deliberate argument escaping and remote HOME
resolution. Test spaces and quotes in game titles against a local fake remote
shell, rather than only asserting the SSH command succeeds.

### P2 — Pull dry-run creates a local directory

Location: `src/runners/50_launcher.sh:729`.

`mkdir -p "$sdir"` runs even with `--dry-run`. A temporary game directory without
`saves/` acquired that directory after a mocked dry-run, despite the message
claiming no local files changed.

Action: perform local directory creation only for real transfers. Assert directory
tree equality before/after dry-run, including the initially missing saves case.

### P2 — Distribution architecture claims conflict with packaged payload

Locations: `packaging/debian/build-deb.sh:7,26,47-49`,
`packaging/arch/PKGBUILD`, `pyproject.toml`, and `MANIFEST.in`.

The built wheel is named `gamectl-1.4.0-py3-none-any.whl`, with
`Root-Is-Purelib: true`, but contains an ELF x86-64 `gamectl-depot-dl` executable.
The built Debian package declares `Architecture: all` while also including that
native binary. The Arch recipe declares `arch=('any')` and conditionally packages
the same binary. These artifacts can be selected for incompatible machines.
The Debian `Depends` also omits `zip`, which the installer requires.

Action: either split the native helper into an architecture-specific package or
produce correctly tagged platform artifacts; declare runtime dependencies
consistently. Inspect package contents and run installed entrypoints in the
release matrix, including a non-x86 target where supported.

### P2 — TUI success notices do not depend on backend success

Location: `src/tui/70_dashboard.sh:579-593`.

Injection, sync, and backup hotkeys call backend functions then unconditionally
display success notices. Backend stdout/stderr is also written directly between
fzf screens. This can hide a failure and overwrite useful execution logs on the
next redraw. The upstream TUI analysis document describes the same gap;
`tui_exec_action` is not implemented.

Action: introduce a common action wrapper that captures output, preserves the
backend exit code, shows a result review, and returns to the menu after dismissal.
Test failed actions and signal cleanup with PTYs. The current Esc smoke test
only verifies the normal dashboard exit path.

## Maintenance sequence and acceptance gates

1. **Save integrity:** transactional restore and checked backup; fault-injection
   tests must prove current saves survive every pre-commit failure.
2. **Process supervision:** supervisor owns the child and cleanup; active metadata
   persists while a fixture game is alive; no premature scope stop.
3. **Remote sync:** correct remote paths, propagated failure, backup gating, and
   no writes during dry-run; test remote-shell behavior, not just SSH mocks.
4. **TUI results:** captured action output and accurate success/failure review;
   retain terminal state and logs across success, failure, and interruption.
5. **Distribution:** platform-correct native artifacts, consistent dependencies,
   installed-package smoke checks, and source-locked Rust builds.
6. **Test architecture:** retain fast mocked contracts; move live HTTP tests into
   an explicit integration lane; add failure-path tests above, Rust checks,
   ShellCheck and dependency scanning once the tools are provisioned.

Passing the 122 existing assertions does not establish data safety: those tests
miss the copy-failure, sibling-wait, failed-transfer, remote-quoting, and dry-run
cases reproduced in this audit. Treat these findings as release blockers before
claiming reliable save recovery and multi-device synchronization.
