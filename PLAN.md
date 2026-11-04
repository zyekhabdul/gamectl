# WORK PACKET 8: SOURCE-TO-BUNDLE MODULAR ARCHITECTURE TRANSITION

## 1. Objective & Scope
Transition `gamectl` codebase from a monolithic 3,440-line script (`bin/gamectl`) to a clean, maintainable modular structure (`src/`) with a native, zero-dependency bundling engine (`scripts/build.sh`). The output remains a single standalone executable (`bin/gamectl`), preserving 100% backward compatibility, zero-dependency deployment, and instantaneous subshell performance in `fzf`.

---

## 2. Granular Chunks & Definition of Done (DoD)

### Chunk 1: Build Engine & Source Scaffolding [VERIFIED]
- **Target**: `scripts/build.sh`, `src/` directory tree
- **DoD**:
  1. Buat direktori: `src/core`, `src/steam`, `src/runners`, `src/diagnostics`, `src/tui`. [DONE]
  2. Implementasikan `scripts/build.sh` (POSIX/Bash native) yang merangkai modul sesuai urutan deklarasi, menyuntikkan header build stamp, menjalankan `bash -n`, dan menghasilkan `bin/gamectl` executable (`chmod +x`). [DONE]
  3. Pastikan `scripts/build.sh` memiliki mode `--check` untuk memverifikasi apakah `bin/gamectl` sinkron dengan `src/`. [DONE]

### Chunk 2: Extract Core Modul (`src/core/`) [VERIFIED]
- **Target**: `src/core/00_header.sh`, `src/core/10_utils.sh`
- **DoD**:
  1. Pindahkan shebang, constants, theme palette (Tokyo Night ANSI), dan SSoT configs ke `src/core/00_header.sh`. [DONE]
  2. Pindahkan helper functions dasar (`get_gbe_template`, `get_remote_host`, `clean_stale_locks`, `backup_save`, `find_game_binary`) ke `src/core/10_utils.sh`. [DONE]

### Chunk 3: Extract Steam Subsystems (`src/steam/`) [VERIFIED]
- **Target**: `src/steam/20_discovery.sh`, `src/steam/25_identity.sh`, `src/steam/30_downloader.sh`
- **DoD**:
  1. `20_discovery.sh`: `get_steam_root`, `get_steam_primary_apps`, `get_steam_libraries`, `scan_installed_games`, `search_steam`. [DONE]
  2. `25_identity.sh`: `generate_steamid64`, `resolve_active_steamid`, `get_game_persona`, `set_id`, `set_id_interactive`. [DONE]
  3. `30_downloader.sh`: `fetch_dlc`, `ensure_downloader`, `download_game`, `list_downloads`, `list_downloads_interactive`, `sync_steam`, `unlock_game`, `unlock_interactive`. [DONE]

### Chunk 4: Extract Runners & Wrappers (`src/runners/`) [VERIFIED]
- **Target**: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`
- **DoD**:
  1. `40_wrappers.sh`: `find_runner`, `is_haswell_gpu`, `get_native_resolution`, `get_default_gamescope_args`, `build_wrapper_command`, `configure_wrappers`, `configure_global`. [DONE]
  2. `50_launcher.sh`: `launch_game`, `cli_launch`, `inject_game`, `sync_save_remote`, `sync_to_companion`, `sync_to_tuf`. [DONE]

### Chunk 5: Extract Diagnostics & TUI Dashboard (`src/diagnostics/`, `src/tui/`) [VERIFIED]
- **Target**: `src/diagnostics/60_doctor.sh`, `src/tui/70_dashboard.sh`
- **DoD**:
  1. `60_doctor.sh`: `doctor_audit` (7-layer diagnostic health suite). [DONE]
  2. `70_dashboard.sh`: `preview_game`, `preview_dashboard`, `dashboard_menu`, `library_menu`. [DONE]

### Chunk 6: Extract Entrypoint & Dispatcher (`src/main.sh`) [VERIFIED]
- **Target**: `src/main.sh`
- **DoD**:
  1. Pindahkan registrasi `export -f` untuk subshells fzf. [DONE]
  2. Pindahkan CLI command parser & top-level case statement (`case "${1:-}" in ...`). [DONE]

### Chunk 7: Build & Functional Verification Gate [VERIFIED]
- **Target**: `scripts/build.sh`, `bin/gamectl`
- **DoD**:
  1. Eksekusi `scripts/build.sh` menghasilkan `bin/gamectl`. [DONE]
  2. Verifikasi deterministik:
     - `bash -n bin/gamectl` (Exit 0). [DONE]
     - Test CLI output: `bin/gamectl doctor`, `bin/gamectl get-resolution`, `bin/gamectl get-steam-root`. [DONE]
     - Bandingkan fungsionalitas dan pastikan 0% breaking changes. [DONE]

### Chunk 8: Documentation, ADR-011 & Local Commit [VERIFIED]
- **Target**: `DEVELOPMENT.md`, Obsidian RAG `DECISIONS.md`, `STATE.md`, git commit
- **DoD**:
  1. Perbarui `DEVELOPMENT.md` menjelaskan arsitektur baru (`src/` -> `scripts/build.sh` -> `bin/gamectl`). [DONE]
  2. Catat ADR-011 di Obsidian RAG namespace `00-AGY-Memory/gamectl/DECISIONS.md`. [DONE]
  3. Sinkronkan `STATE.md` dan buat local git checkpoint. [DONE]
