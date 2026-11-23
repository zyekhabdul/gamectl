# WORK PACKET 31: SSoT GENERALIZATION, RUNNER HARDENING & HYGIENE

- **Track**: Cross-Distro Hardware Generalization / SSoT Unification / Environment & Detection Hygiene
- **Status**: IN PROGRESS [1/4 PACKETS]
- **Basis**: Forensic audit codebase `src/` pasca-WP30 (`c1dc31b`) — deteksi `llvmpipe`, drift AppID & runner env, tabrakan nama log, duplikasi parser `.wrappers`, magic-size GBE heuristic, dan polusi `export -f`.
- **Target Files**: `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/steam/20_discovery.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/diagnostics/60_doctor.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `Makefile`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Rencana Eksekusi Detail (Packet 31A - 31D)

### [x] Packet 31A: True Hardware & Multilib Generalization (`Vulkan` + `32-bit ABI`)
- **Target Files**: `src/runners/40_wrappers.sh`, `src/diagnostics/60_doctor.sh`, `tests/test_remediation.sh`
- **Langkah Teknis**:
  1. Refactor `detect_vulkan_capability()` (`src/runners/40_wrappers.sh:805-885`) agar mem-parsing output `vulkaninfo --summary` **per-device block** (`GPU0`, `GPU1`, ...):
     - Abaikan `PHYSICAL_DEVICE_TYPE_CPU` (`llvmpipe`/`swiftshader`) dan `VIRTUAL_GPU` saat menghitung `max_ver` supaya rasterizer CPU Vulkan `1.3+` tidak pernah meracuni capability GPU hardware.
     - Tangkap stderr `vulkaninfo` (`incomplete`) sebagai sinyal eksplisit `VULKAN_LEGACY`.
  2. Perkuat `is_haswell_gpu()` (`src/runners/40_wrappers.sh:789-801`) agar fallback `/sys/bus/pci/devices/*/uevent` benar-benar mencocokkan PCI ID (`8086:04*`, `8086:0a*`, `8086:0d*`) tanpa bergantung pada keberadaan binary `lspci`, serta generalisasikan hint driver legacy.
  3. Upgrade audit 32-bit multilib pada `doctor_audit()` (`src/diagnostics/60_doctor.sh:240-254`) agar memeriksa `ldconfig -p` terlebih dahulu untuk mencari `libGL.so.1` dengan ABI 32-bit (lintas distro: Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE, Gentoo, Void) sebelum fallback ke pengecekan path filesystem.
- **Definition of Done (DoD)**:
  - Unit test membuktikan kombinasi mock `llvmpipe` (Vulkan 1.3) + GPU fisik (Vulkan 1.2) menghasilkan `VULKAN_LEGACY`, bukan `VULKAN_READY`.
  - `is_haswell_gpu()` berfungsi konsisten via PCI ID uevent maupun output `lspci`.
  - `doctor_audit()` mendeteksi runtime OpenGL 32-bit melalui `ldconfig -p` atau path distro standar.
  - [ VERIFIED ] `test_vulkan_per_device_and_multilib_contract`, `test_cli.sh` (147/147), `test_remediation.sh` (14/14), `test_tui_ergonomics.sh` (3/3), `./scripts/build.sh --check` (12309 lines), dan `make lint` lulus Exit 0.

### [ ] Packet 31B: Core SSoT Unification (`AppID`, `Log Path`, `.wrappers`, `Windows Runner Env`)
- **Target Files**: `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/steam/20_discovery.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/diagnostics/60_doctor.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `tests/test_remediation.sh`
- **Langkah Teknis**:
  1. Tambahkan SSoT `resolve_game_appid "$gdir"` di `src/core/10_utils.sh` (prioritas deterministik: `steam_appid.txt` -> `steam_settings/steam_appid.txt` -> `.gamectl_appid` -> `0`) dan gantikan seluruh parser ad-hoc di `launch_game()`, `manage_prefix()`, `20_discovery.sh`, `30_downloader.sh`, `35_fixes.sh`, `60_doctor.sh`, serta `70_dashboard.sh`.
  2. Tambahkan SSoT `get_game_log_file "$gdir" "$gbin"` di `src/core/10_utils.sh` berbasis slug direktori/AppID (`game_<dir_slug>_<safe_gbin>.log`) agar dua game berbeda yang sama-sama memakai `game.exe` / `Launcher.exe` tidak saling menimpa log, lalu hubungkan ke `launch_game()`, `game_controller_hud()`, dan `preview_game()`.
  3. Ekstrak SSoT `load_wrapper_config "$gdir"` di `src/runners/40_wrappers.sh` untuk menyatukan pembacaan global + per-game `.wrappers`, pemangkasan spasi/quote, serta override env (`GAMECTL_*` / `PROTON_USE_WINED3D`) di `build_wrapper_command()`, `configure_wrappers()`, `preview_game()`, dan `preview_dashboard()`.
  4. Ekstrak `prepare_windows_runner_env()` di `src/runners/40_wrappers.sh` / `50_launcher.sh` agar `manage_prefix()` (`winecfg`/`regedit`/`cmd`) dan `launch_game()` berbagi kontrak `umu-` `GAMEID`, `SteamAppId`, `SteamGameId`, `PROTON_USE_WINED3D`, dan `PROTONFIXES_DISABLE`, serta tidak mencetak log `PROTON_USE_WINED3D` pada cabang `wine`/`wine64` vanilla.
- **Definition of Done (DoD)**:
  - Game standalone yang hanya memiliki `.gamectl_appid` atau `steam_settings/steam_appid.txt` tetap mengekspor AppID yang tepat saat launch.
  - Dua game dengan executable bernama identik (`game.exe`) menghasilkan file log terpisah.
  - `manage_prefix()` menerapkan kontrak env Proton/umu-run dan guard `PROTONFIXES_DISABLE=1` yang identik dengan `launch_game()`.

### [ ] Packet 31C: Detection Integrity, Standalone Runners & Hygiene
- **Target Files**: `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `Makefile`
- **Langkah Teknis**:
  1. Perkeras `resolve_game_drm_status()` (`src/core/10_utils.sh:1127-1140`) agar tidak bergantung semata pada magic size `> 7000000` byte: utamakan penanda struktural (`.orig`, `steam_settings/`, `.gamectl_gbe`, atau string signature GBE pada binary) dan turunkan size heuristic ke sinyal sekunder.
  2. Dukung direktori runner XDG standalone `$HOME/.local/share/gamectl/runners` pada `find_runner()` (`src/runners/40_wrappers.sh:167-183`) sambil menjaga kompatibilitas penuh `compatibilitytools.d`.
  3. Audit dan pangkas daftar `export -f` berlebih di `src/main.sh` (atau bersihkan `BASH_FUNC_*` sebelum `exec` child process game/Proton di `launch_game()`) agar environment runtime game bersih.
  4. Perjelas label integrasi opsional Steam/SLSsteam di TUI utama (`src/tui/70_dashboard.sh`) sebagai `Bridge (Opt)` sesuai `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`, dan pastikan target `make clean` membersihkan artefak build lama (`src/gamectl.egg-info/`, `src/gamectl_runner/bin/`).
- **Definition of Done (DoD)**:
  - DLL GBE hasil strip (<7MB) yang memiliki penanda struktural tetap terdeteksi sebagai `GBE_FORK`.
  - Runner yang ditempatkan di `~/.local/share/gamectl/runners` terdeteksi otomatis oleh `find_runner()`.
  - Subshell child process game bersih dari polusi fungsi `BASH_FUNC_*` yang tidak diperlukan.

### [ ] Packet 31D: Regression Contracts, Bundle Sync & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `bin/gamectl`
- **Langkah Teknis**:
  1. Tambahkan contract tests deterministik di `tests/test_remediation.sh` untuk Packet 31A, 31B, dan 31C.
  2. Kompilasi bundle via `./scripts/build.sh` dan verifikasi `./scripts/build.sh --check`.
  3. Eksekusi gerbang verifikasi penuh: `make lint && make test && python3 -m unittest tests/test_tui_safety.py tests/test_standalone_safety.py tests/test_save_safety.py`.
- **Definition of Done (DoD)**:
  - `make lint` dan `make test` (`test_cli.sh`, `test_remediation.sh`, `test_tui_ergonomics.sh`) lulus Exit Code 0.
  - Seluruh Python safety suites lulus Exit Code 0 (0 failures).
  - `bin/gamectl` sinkron 100% dengan source (`./scripts/build.sh --check` Exit 0).
