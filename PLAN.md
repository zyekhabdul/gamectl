# WORK PACKET 9: GLOBAL GAMER & DEVELOPER ENGINE EXPANSION

## 1. Objective & Scope
Implement high-impact capabilities required by global Linux gamers, modders, and game developers:
1. OnlineFix multiplayer support (dynamic `WINEDLLOVERRIDES` + Spacewar AppID 480 auto-entitlement).
2. Universal modding overrides (Unity BepInEx, Unreal Engine UE4SS, Capcom REFramework).
3. Headless GE-Proton / Wine-GE manager (`proton-list`, `proton-install`, `proton-remove` via GitHub Releases API).
4. Wine Prefix Swiss Army Knife (`gamectl pfx <gdir> [winecfg|regedit|cmd|kill|clean]`).
5. Native ProtonDB compatibility audit CLI (`gamectl protondb <appid>`).
6. Standard Desktop Entry generator (`gamectl make-desktop <gdir>`).

Detailed architectural proposal and background specifications: `docs/PROPOSAL_GLOBAL_FEATURES.md`.

---

## 2. Granular Chunks & Definition of Done (DoD)

### Chunk 1: OnlineFix & DLL Overrides Scanner (`src/runners/40_wrappers.sh`) [PENDING]
- **Target**: `src/runners/40_wrappers.sh`
- **DoD**:
  1. Buat fungsi `detect_dll_overrides <game_dir>` yang memindai:
     - OnlineFix: `OnlineFix64.dll`, `OnlineFix.dll`, `dnet.dll`, `SteamOverlay64.dll`, `winmm.dll`, `version.dll`.
     - BepInEx (Unity): `winhttp.dll`, folder `BepInEx/`.
     - UE4SS (Unreal): `dwmapi.dll`, folder `ue4ss/`.
     - REFramework / ASI: `dinput8.dll`, `dxgi.dll`.
     - Deklaratif per-game: `$game_dir/.dll_overrides`.
  2. Susun format string `WINEDLLOVERRIDES` yang aman dan tanpa redundansi.

### Chunk 2: Launcher Overrides Injection & Spacewar Entitlement (`src/runners/50_launcher.sh`) [PENDING]
- **Target**: `src/runners/50_launcher.sh`, `src/steam/30_downloader.sh`
- **DoD**:
  1. Ekspor `WINEDLLOVERRIDES` yang terdeteksi sebelum eksekusi `umu-run`, `proton`, dan `wine`.
  2. Implementasikan fungsi `setup_onlinefix <game_dir>` yang memvalidasi `OnlineFix.ini` dan memastikan AppID 480 (Spacewar) terdaftar di Steam / SLSsteam via `sync_steam 480 "Spacewar"`.

### Chunk 3: Headless GE-Proton Release Manager (`src/runners/40_wrappers.sh`) [PENDING]
- **Target**: `src/runners/40_wrappers.sh`
- **DoD**:
  1. `proton_list`: Query GitHub API untuk rilis terbaru `GloriousEggroll/proton-ge-custom` dan tampilkan perbandingan dengan rilis lokal di `compatibilitytools.d/`.
  2. `proton_install [latest|<tag>]`: Unduh tarball `x86_64` secara headless tanpa dependensi GUI dan ekstrak langsung ke `~/.local/share/Steam/compatibilitytools.d/`.
  3. `proton_remove <tag>`: Hapus instalasi GE-Proton lama untuk membebaskan ruang disk.

### Chunk 4: Prefix Swiss Army Knife (`src/runners/40_wrappers.sh`) [PENDING]
- **Target**: `src/runners/40_wrappers.sh`
- **DoD**:
  1. Buat handler `manage_prefix <game_dir> <subcommand> [args...]`.
  2. Dukung subcommands: `winecfg`, `regedit`, `cmd`, `shell`, `kill` (`wineserver -k`), `clean` (reset `$gdir/pfx`).

### Chunk 5: ProtonDB CLI & Desktop Entry Generator (`src/diagnostics/60_doctor.sh`, `src/steam/20_discovery.sh`) [PENDING]
- **Target**: `src/diagnostics/60_doctor.sh`, `src/steam/20_discovery.sh`
- **DoD**:
  1. `query_protondb <appid>`: Query `https://www.protondb.com/api/v1/reports/summaries/${appid}.json` dan cetak status tier/confidence dengan ANSI color formatting.
  2. `create_desktop_entry <game_dir> [title]`: Generate file `~/.local/share/applications/gamectl-<safe_name>.desktop` dengan resolusi icon lokal.

### Chunk 6: CLI Top-Level Dispatcher & Build Sync (`src/main.sh`, `scripts/build.sh`) [PENDING]
- **Target**: `src/main.sh`, `bin/gamectl`
- **DoD**:
  1. Daftarkan perintah CLI di `src/main.sh`:
     - `onlinefix <dir>`
     - `proton-list` / `proton-install` / `proton-remove`
     - `pfx <dir> <action>`
     - `protondb <appid>`
     - `make-desktop <dir>`
  2. Eksekusi `./scripts/build.sh` dan pastikan `bash -n bin/gamectl` exit 0.

### Chunk 7: Test Suite Expansion & Contract Verification (`tests/test_cli.sh`) [PENDING]
- **Target**: `tests/test_cli.sh`
- **DoD**:
  1. Tambahkan test case untuk `detect_dll_overrides` (mock OnlineFix dan BepInEx directories).
  2. Tambahkan test case untuk CLI syntax parsing subcommands baru.
  3. Jalankan `tests/test_cli.sh` dan pastikan seluruh test lulus dengan exit 0.

### Chunk 8: Documentation & Checkpoint Commit [PENDING]
- **Target**: `README.md`, `DEVELOPMENT.md`, Obsidian RAG `STATE.md`, local git commit
- **DoD**:
  1. Dokumentasikan perintah baru pada `README.md` dan `DEVELOPMENT.md`.
  2. Perbarui `STATE.md` di Obsidian RAG memory.
  3. Lakukan local commit (zero emoji, format konvensional).
