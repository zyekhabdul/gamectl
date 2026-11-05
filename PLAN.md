# WORK PACKET 9: GLOBAL CAPABILITIES & SYSTEMIC REMEDIATION (HYBRID SPRINT)

## 1. Objective & Scope
Implement and harden core capabilities required by global Linux gamers, modders, and game developers, seamlessly integrating high-impact systemic remediations from `remediation.md` (DEFECT-02 Wineserver Lifecycle Guard & DEFECT-03 PipeWire Real-Time Audio Buffer):

1. **OnlineFix & Universal Mod DLL Overrides Engine**: Dynamic `WINEDLLOVERRIDES` + Spacewar AppID 480 auto-entitlement.
2. **PipeWire Real-Time Audio Scheduling (DEFECT-03 Remediation)**: Prevent audio crackling and underruns via quantum buffer tuning (`PIPEWIRE_LATENCY="256/48000"`, `PULSE_LATENCY_MSEC=60`).
3. **Headless GE-Proton / Wine-GE Release Manager**: `proton-list`, `proton-install`, `proton-remove` via GitHub Releases API without GUI dependencies.
4. **Wine Prefix Swiss Army Knife (`pfx`) & Wineserver Lifecycle Guard (DEFECT-02 Remediation)**: `gamectl pfx <gdir> [winecfg|regedit|cmd|shell|kill|clean|winetricks]` with deterministic `wineserver -w` / `wineserver -k` to prevent registry locking and zombie daemons.
5. **Native ProtonDB Quick Audit CLI**: `gamectl protondb <appid|dir>` with direct tier badges and launch parameter recommendations.
6. **XDG Desktop Entry Generator**: `gamectl make-desktop <gdir> [title]` for system launcher and Steam Deck Game Mode integration.

Background specifications: `docs/PROPOSAL_GLOBAL_FEATURES.md` and `remediation.md`.

---

## 2. Granular Chunks & Technical Execution DoD

### Chunk 1: OnlineFix & Mod DLL Overrides Detection Engine [ DONE ]
- **Target File**: `src/runners/40_wrappers.sh`
- **Function Signature**: `detect_dll_overrides <game_dir>` -> outputs clean semicolon-separated `WINEDLLOVERRIDES` string
- **Technical Logic & Rules**:
  1. Scan root `$game_dir` and subfolders (depth 2) for signature files:
     - **OnlineFix**: `OnlineFix64.dll`, `OnlineFix.dll`, `dnet.dll`, `SteamOverlay64.dll`, `winmm.dll`, `version.dll`.
       Token payload: `OnlineFix=n;OnlineFix64=n;SteamOverlay64=n;dnet=n;winmm=n,b;version=n,b;steam_api64=n;steam_api=n`
     - **Unity BepInEx**: Folder `BepInEx/`, `doorstop_config.ini`, or `winhttp.dll`.
       Token payload: `winhttp=n,b`
     - **Unreal Engine UE4SS**: Folder `ue4ss/`, `UE4SS.dll`, or `dwmapi.dll`.
       Token payload: `dwmapi=n,b`
     - **Capcom REFramework / ASI Loaders**: `dinput8.dll`.
       Token payload: `dinput8=n,b`
     - **ReShade / SpecialK**: `ReShade.ini` or ReShade-specific `dxgi.dll`.
       Token payload: `dxgi=n,b`
     - **Per-Game Custom Declarative**: File `$game_dir/.dll_overrides` containing custom key-values or tokens.
  2. Implement string sanitizer & deduplicator:
     - Combine all tokens with existing `WINEDLLOVERRIDES` from environment.
     - Normalize delimiters (`;` and `,`), strip whitespace, lowercase keys, eliminate duplicate keys.
- **DoD**:
  1. `detect_dll_overrides` returns clean, normalized override string with exit code 0.
  2. Returns empty string if no mod/OnlineFix DLLs are present.
  3. Preserves user-defined `WINEDLLOVERRIDES` without duplicate keys.

---

### Chunk 2: Launcher Overrides Injection, Spacewar Entitlement & PipeWire Audio Tuning [ DONE ]
- **Target Files**: `src/runners/50_launcher.sh`, `src/steam/30_downloader.sh`
- **Functions**: `setup_onlinefix <game_dir>`, updates to `launch_game <game_dir> <bin> <title>`
- **Technical Logic & Rules**:
  1. In `launch_game`:
     - Run `local detected_overrides; detected_overrides=$(detect_dll_overrides "$gdir")`.
     - Export combined `WINEDLLOVERRIDES` inside runner execution blocks (`umu-run`, `proton`, `wine`).
     - **DEFECT-03 Remediation (PipeWire Audio Scheduling)**:
       - Export `PIPEWIRE_LATENCY="${GAMECTL_PIPEWIRE_LATENCY:-256/48000}"`.
       - Export `PULSE_LATENCY_MSEC="${GAMECTL_PULSE_LATENCY:-60}"`.
       - Eliminates buffer underrun crackle on heavy CPU loads.
     - Log active DLL overrides: `[INFO] DLL Overrides aktif: $WINEDLLOVERRIDES`.
  2. In `setup_onlinefix`:
     - Check if `$game_dir` contains OnlineFix signatures.
     - Verify if `appmanifest_480.acf` (Spacewar) exists in Steam root (`~/.local/share/Steam/steamapps/`) and SLSsteam.
     - If missing, invoke `sync_steam 480 "Spacewar" "$game_dir"` to register manifest and unlock P2P socket.
     - Audit `OnlineFix.ini` for player name (`PlayerName=...`); offer to sync with `gamectl set-id` active persona.
- **DoD**:
  1. Windows runner subshells execute with verified `WINEDLLOVERRIDES` and real-time audio buffer variables.
  2. `gamectl onlinefix <game_dir>` detects files, validates Spacewar AppID 480 manifest, and syncs Steam/SLSsteam.

---

### Chunk 3: Headless GE-Proton / Wine-GE Release Manager [ DONE ]
- **Target File**: `src/runners/40_wrappers.sh`
- **Functions**: `proton_list`, `proton_install [tag|latest]`, `proton_remove <tag>`
- **Technical Logic & Rules**:
  1. `proton_list`:
     - Scan local directories: `~/.local/share/Steam/compatibilitytools.d/` and `~/.steam/root/compatibilitytools.d/`.
     - Fetch releases from GitHub API with 5-second timeout:
       `curl -s --connect-timeout 5 https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=5`
     - Parse release tags, download URLs, and asset sizes using `jq`.
     - Fallback if GitHub rate-limited (HTTP 403/429): Parse release HTML redirect or report cached local list.
     - Display formatted ANSI table comparing installed local versions with latest upstream releases.
  2. `proton_install`:
     - Resolve target tag (default: latest).
     - Query asset URL for `x86_64.tar.gz`.
     - Determine Steam compatibility directory (`~/.local/share/Steam/compatibilitytools.d/`).
     - Stream download with fail-on-error (`curl -fL`) and unpack directly:
       `curl -# -fL "$asset_url" | tar -xz -C "$compat_dir/"`
     - Validate extraction: check for `compatibilitytool.vdf` and executable `proton`.
  3. `proton_remove`:
     - Verify tag path strictly within `compatibilitytools.d/` to prevent directory traversal.
     - Prompt confirmation before removing directory.
- **DoD**:
  1. `proton-list` accurately lists local installations and queries GitHub releases.
  2. `proton-install latest` downloads, unpacks, and registers valid GE-Proton build.
  3. `proton-remove <tag>` safely deletes selected release folder.

---

### Chunk 4: Wine Prefix Swiss Army Knife (`pfx`) & Wineserver Lifecycle Guard [ DONE ]
- **Target File**: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`
- **Functions**: `manage_prefix <game_dir> <action> [args...]`, updates to `_restore_launch_state`
- **Technical Logic & Rules**:
  1. Resolve prefix path `$game_dir/pfx` and game runner via `find_runner "$game_dir"`.
  2. Environment setup:
     - If runner is Proton:
       `STEAM_COMPAT_CLIENT_INSTALL_PATH=$(get_steam_root) STEAM_COMPAT_DATA_PATH="$game_dir" WINEPREFIX="$game_dir/pfx"`
     - If runner is Wine:
       `WINEPREFIX="$game_dir/pfx"`
  3. Subcommand dispatch:
     - `winecfg`: Launch `"$runner" run winecfg` (Proton) or `wine winecfg` (Wine).
     - `regedit`: Launch `"$runner" run regedit` or `wine regedit`.
     - `cmd`: Launch interactive Windows Command Prompt.
     - `shell`: Spawn interactive local Bash shell with `WINEPREFIX`, `PATH`, and runner vars pre-exported.
     - `kill`: **DEFECT-02 Remediation**: Check prefix wineserver PID and execute `wineserver -k` with `WINEPREFIX="$game_dir/pfx"`.
     - `clean`: Trigger `backup_save "$game_dir"`, prompt confirmation, terminate wineserver, and safely wipe `$game_dir/pfx`.
     - `winetricks`: If `winetricks` binary exists, run `WINEPREFIX="$game_dir/pfx" winetricks "$@"`.
  4. In `src/runners/50_launcher.sh` (`_restore_launch_state` & HUD option 4/5):
     - For Windows games, execute graceful wait `WINEPREFIX="$gdir/pfx" wineserver -w 2>/dev/null || true` before save backup.
     - On force termination (HUD option 5), call `WINEPREFIX="$gdir/pfx" wineserver -k 2>/dev/null || true` to eliminate zombie server locks.
- **DoD**:
  1. Subcommands `winecfg`, `regedit`, `cmd`, `kill`, `clean` execute against isolated prefix without polluting global system.
  2. Clean action strictly triggers save backup before prefix directory wipe.
  3. Wineserver is deterministically cleaned up on game teardown.

---

### Chunk 5: ProtonDB Quick Audit CLI & Desktop Entry Generator [ DONE ]
- **Target Files**: `src/diagnostics/60_doctor.sh`, `src/steam/20_discovery.sh`
- **Functions**: `query_protondb <appid|dir>`, `create_desktop_entry <game_dir> [title]`
- **Technical Logic & Rules**:
  1. `query_protondb`:
     - Resolve AppID from numeric input or parse from `$game_dir/steam_appid.txt`.
     - Query: `curl -s --connect-timeout 5 https://www.protondb.com/api/v1/reports/summaries/${appid}.json`.
     - Parse JSON fields (`tier`, `confidence`, `score`, `total`) via `jq`.
     - Format ANSI card:
       - Cyan for Platinum, Green for Gold, Yellow for Silver, Red for Borked.
     - Print community launch parameter recommendations.
     - Handle offline / 404 / rate-limit gracefully without terminal crash.
  2. `create_desktop_entry`:
     - Resolve game title, binary path, and absolute directory.
     - Search local icon candidates: `icon.png`, `icon.ico`, `logo.png`.
     - Convert `.ico` to `.png` via ImageMagick `convert` if available; fallback to generic gaming icon.
     - Write `~/.local/share/applications/gamectl-<safe_name>.desktop` with `Exec=gamectl launch "<dir>"`.
- **DoD**:
  1. `gamectl protondb <appid>` renders accurate tier badge and metrics.
  2. `gamectl make-desktop <dir>` produces valid XDG `.desktop` file verified by `desktop-file-validate` (if installed).

---

### Chunk 6: CLI Entrypoint Dispatcher & Build Synchronization [ DONE ]
- **Target Files**: `src/main.sh`, `scripts/build.sh`, `bin/gamectl`
- **Technical Logic & Rules**:
  1. In `src/main.sh`:
     - Register exported functions in `export -f`: `detect_dll_overrides`, `setup_onlinefix`, `proton_list`, `proton_install`, `proton_remove`, `manage_prefix`, `query_protondb`, `create_desktop_entry`.
     - Route CLI subcommands:
       - `onlinefix`: `setup_onlinefix "$2"`
       - `proton-list` / `proton`: `proton_list`
       - `proton-install`: `proton_install "${2:-latest}"`
       - `proton-remove`: `proton_remove "$2"`
       - `pfx`: `manage_prefix "$2" "${3:-winecfg}" "${@:4}"`
       - `protondb`: `query_protondb "$2"`
       - `make-desktop`: `create_desktop_entry "$2" "${3:-}"`
     - Update `--help` usage documentation.
  2. Execute `./scripts/build.sh` to compile `bin/gamectl`.
- **DoD**:
  1. `./scripts/build.sh --check` verifies source-to-bundle synchronization.
  2. `bash -n bin/gamectl` returns exit code 0 with zero syntax errors.

---

### Chunk 7: Automated Test Suite Expansion & Contract Verification [ DONE ]
- **Target File**: `tests/test_cli.sh`
- **Technical Logic & Rules**:
  1. Add Test Suite 5: Global Features & Remediation Harness:
     - Test `detect_dll_overrides`: Mock directory with `OnlineFix64.dll` -> assert contains `OnlineFix64=n`.
     - Test `detect_dll_overrides`: Mock directory with `BepInEx/` -> assert contains `winhttp=n,b`.
     - Test `detect_dll_overrides`: Mock directory with `.dll_overrides` -> assert custom token parsed.
     - Test `proton-list`: Assert CLI runs without syntax error.
     - Test `pfx`: Assert error handling on invalid action or non-existent game directory.
     - Test `protondb`: Mock or live query for AppID 105600 -> assert tier parsed.
     - Test `audio_env`: Assert `PIPEWIRE_LATENCY` is exported in launcher subshell.
  2. Run full regression suite: `tests/test_cli.sh`.
- **DoD**:
  1. Test suite executes all tests (>20 test cases).
  2. Zero test failures, zero test skips (`exit code 0`).

---

### Chunk 8: Documentation, Memory Sync & Local Checkpoint Commit [ IN PROGRESS ]
- **Target Files**: `README.md`, `DEVELOPMENT.md`, `remediation.md`, Obsidian RAG `STATE.md`, Git commit
- **Technical Logic & Rules**:
  1. Update `README.md` and `DEVELOPMENT.md` with new subcommands, flags, and architecture documentation.
  2. Mark DEFECT-02 and DEFECT-03 as resolved in `remediation.md`.
  3. Update `STATE.md` in `~/Documents/Obsidian Vault/00-AGY-Memory/gamectl/` with new commit hash.
  4. Execute local git commit with conventional commit message:
     `feat(engine): implement onlinefix overrides, proton manager, prefix swiss army knife, and audio/wineserver hardening`
- **DoD**:
  1. Working tree clean (`git status` 0 uncommitted changes).
  2. Anti-push compliance maintained (local commit only).

---

## 3. Post-Sprint Roadmap (Work Packet 10)
Upon completion and verification of Work Packet 9, remaining system remediations will be executed in **Work Packet 10**:
- **DEFECT-01**: `systemd-run --user --scope` and cgroups v2 process tree isolation (`app-gamectl.slice`).
- **DEFECT-04**: GPU Hybrid PRIME offloading (`--dgpu` / `--prime` with NVIDIA / AMD DRI auto-detection).
- **DEFECT-05**: Bubblewrap (`bwrap`) containerized sandboxing profile.
- **DEFECT-06**: Single-pass batch library scanning for multi-thousand game collections.
