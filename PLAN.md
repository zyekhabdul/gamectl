# WORK PACKET 37: MODULAR RUNNERS & TUI SPLIT (PRASYARAT WP38)

- **Track**: Long-Term Maintainability / Domain Modularization (`runners/` & `tui/`)
- **Status**: COMPLETED [4/4 PACKETS]
- **Riwayat Selesai**: WP33..WP36 (`9a1be91..15e95bc`), CI/Dual-License/Hygiene (`5ea7948..a678046`), Modular Core & Steam Split (`a73bfc5..085327b`), RFC Multi-Store v2.0 (`2af9c4c`), CLI Alias/CI Gates & Clean Debian 13 `depot-dl` (`75c168a..8f10dbe`) — seluruhnya COMPLETED & terverifikasi.
- **Basis**: `docs/SOVEREIGN_ORIGINAL_PURPOSE.md` dan pola sibling loader `a73bfc5` (`GAMECTL_BUNDLED`).
- **Target Files**: `src/runners/{40_wrappers,41_proton_prefix,42_graphics_isolation}.sh`, `src/runners/{50_launcher,51_remote_sync,52_inject_runtime}.sh`, `src/tui/{70_dashboard,71_previews}.sh`, `scripts/build.sh`, `tests/test_cli.sh`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Tujuan & Batasan WP37

1. **Zero Behavior Change**: Pemecahan murni struktural untuk menyeimbangkan ukuran modul `runners/` dan `tui/` agar setara dengan `core/` & `steam/` sebelum `70_dashboard.sh` dimodifikasi pada WP38D.
2. **Backward-Compatible `source`**: Setiap file induk (`40_wrappers.sh`, `50_launcher.sh`, `70_dashboard.sh`) menyertakan sibling auto-loader `[ -z "${GAMECTL_BUNDLED:-}" ]` sehingga pemanggil test eksisting tetap bekerja tanpa perubahan signature.

---

## 2. Rencana Eksekusi Detail (Packet 37A - 37D)

### [x] Packet 37A: Split `src/runners/40_wrappers.sh` (2.072 LOC -> 3 Modul)
- **Target Files**: `src/runners/40_wrappers.sh`, `src/runners/41_proton_prefix.sh`, `src/runners/42_graphics_isolation.sh`, `scripts/build.sh`
- **Langkah Teknis**:
  1. Pertahankan di `40_wrappers.sh` (~722 LOC): `load_wrapper_config`, `resolve_dev_profiler_env`, `configure_dev_profile`, `build_wrapper_command`, `configure_wrappers`, `configure_global`, ditambah sibling auto-loader (`41_proton_prefix.sh`, `42_graphics_isolation.sh`).
  2. Pindahkan ke `41_proton_prefix.sh` (~981 LOC): `detect_dll_overrides`, `list_runner_dirs`, `find_runner`, `get_wineserver_bin`, `get_compat_dir`, `proton_list`, `proton_install`, `proton_remove`, `prepare_windows_runner_env`, `manage_prefix`.
  3. Pindahkan ke `42_graphics_isolation.sh` (~380 LOC): `is_haswell_gpu`, `detect_vulkan_capability`, `resolve_graphics_renderer`, `get_native_resolution`, `get_default_gamescope_args`, `check_systemd_scope_support`, `detect_dgpu_vendor`, `build_sandbox_command`.
  4. Daftarkan `41_proton_prefix.sh` dan `42_graphics_isolation.sh` di `MODULES=(...)` `scripts/build.sh` tepat setelah `40_wrappers.sh`.
- **Definition of Done (DoD)**:
  - `source src/runners/40_wrappers.sh` memuat seluruh fungsi runner, prefix, dan isolasi tanpa error; `./scripts/build.sh` lulus `bash -n`.

### [x] Packet 37B: Split `src/runners/50_launcher.sh` (1.572 LOC -> 3 Modul)
- **Target Files**: `src/runners/50_launcher.sh`, `src/runners/51_remote_sync.sh`, `src/runners/52_inject_runtime.sh`, `scripts/build.sh`
- **Langkah Teknis**:
  1. Pertahankan di `50_launcher.sh` (~794 LOC): `preview_process_log`, `game_controller_hud`, `launch_game`, `cli_launch`, ditambah sibling auto-loader (`51_remote_sync.sh`, `52_inject_runtime.sh`).
  2. Pindahkan ke `51_remote_sync.sh` (~423 LOC): `probe_ssh_remote_home`, `resolve_ssh_remote_base`, `resolve_rclone_remote_saves`, `sync_save_remote`, `pull_save_remote`, `sync_to_companion`, `sync_to_tuf`, `pull_from_companion`, `pull_from_tuf`.
  3. Pindahkan ke `52_inject_runtime.sh` (~366 LOC): `setup_onlinefix`, `inject_game`.
  4. Daftarkan `51_remote_sync.sh` dan `52_inject_runtime.sh` di `MODULES=(...)` `scripts/build.sh` tepat setelah `50_launcher.sh`.
- **Definition of Done (DoD)**:
  - `source src/runners/50_launcher.sh` memuat seluruh fungsi sync & inject secara transparan; `./scripts/build.sh` lulus `bash -n`.

### [x] Packet 37C: Split `src/tui/70_dashboard.sh` (1.728 LOC -> 2 Modul)
- **Target Files**: `src/tui/70_dashboard.sh`, `src/tui/71_previews.sh`, `scripts/build.sh`
- **Langkah Teknis**:
  1. Pertahankan di `70_dashboard.sh` (~865 LOC): `view_logs_interactive`, `manage_active_processes_interactive`, `dashboard_menu`, `remote_sync_interactive`, `library_menu`, `search_steam`, ditambah sibling auto-loader (`71_previews.sh`).
  2. Pindahkan ke `71_previews.sh` (~874 LOC): `preview_game`, `preview_dashboard`, `preview_search_game`, `preview_log_entry` (renderer preview read-only, zero side-effect).
  3. Daftarkan `71_previews.sh` di `MODULES=(...)` `scripts/build.sh` tepat setelah `70_dashboard.sh`.
- **Definition of Done (DoD)**:
  - `source src/tui/70_dashboard.sh` memuat seluruh preview renderer; seluruh `--expect` dan `download_game.*--os` tetap utuh di `70_dashboard.sh`.

### [x] Packet 37D: Update Static Test Paths, Rebuild & Full Verification di `serv`
- **Target Files**: `tests/test_cli.sh`, `tests/test_remediation.sh`, `bin/gamectl`
- **Langkah Teknis**:
  1. Perbarui path assertions statis yang mereferensikan lokasi fungsi yang dipindah:
     - `tests/test_cli.sh`: `manage_prefix()` -> `src/runners/41_proton_prefix.sh`; `pull_save_remote()` -> `src/runners/51_remote_sync.sh`.
     - `tests/test_remediation.sh`: audit `/run/user/` mencakup `41_proton_prefix.sh` & `42_graphics_isolation.sh`; `Bridge (Opt)` -> `src/tui/71_previews.sh`.
  2. Kompilasi ulang `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`).
  3. Sync ke `serv:~/Projects/gamectl-build/` dan jalankan full verification gate (`STRICT_LINT=1 make lint`, `make test`, `cargo test --manifest-path crates/depot-dl/Cargo.toml`).
- **Definition of Done (DoD)**:
  - `STRICT_LINT=1 make lint` Exit `0`, `./scripts/build.sh --check` `[PASS]`, `make test` (`test_cli.sh` 147/147, `test_remediation.sh` 31/31, `test_tui_ergonomics.sh`, `test_depot_filter.sh`) dan `cargo test` 40/40 lulus Exit `0` tanpa regresi.

---

# WORK PACKET 38: MULTI-STORE PHASE 1 (STORE INTERFACE, STEAM ADAPTER, SCANNER V3 & FILTER)

- **Track**: Multi-Store Architecture / Discovery Schema v3 / TUI Filter
- **Status**: PENDING [0/4 PACKETS]
- **Prasyarat**: WP37 (Modular Runners & TUI Split)
- **Riwayat Selesai**: WP33..WP36 (`9a1be91..15e95bc`), CI/Dual-License/Hygiene (`5ea7948..a678046`), Modular Core & Steam Split (`a73bfc5..085327b`), RFC Multi-Store v2.0 (`2af9c4c`), CLI Alias/CI Gates & Clean Debian 13 `depot-dl` (`75c168a..8f10dbe`).
- **Basis**: `docs/RFC_MULTISTORE_SUPPORT.md` (v2.0) dan `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`.
- **Target Files**: `src/stores/00_store_interface.sh`, `src/stores/10_store_steam.sh`, `src/steam/20_discovery.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `scripts/build.sh`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Tujuan & Batasan Phase 1

1. **Unified Store Abstraction (`src/stores/`)**:
   - Menyediakan layer registry dan dispatch (`store_list_registered`, `store_list_available`, `store_dispatch`) agar adapter store eksternal berikutnya (`gog`, `epic`, `amazon`) dapat dipasang tanpa menyentuh core launcher atau merusak alur standalone Steam.
2. **Backward-Compatible Scanner v3 (`src/steam/20_discovery.sh`)**:
   - Menambahkan Kolom 6 (`STORE`: `STEAM|STANDALONE`, siap ekstensi ke `GOG|EPIC|AMAZON`) dengan header cache `# gamectl scanner v3`, sambil mempertahankan Kolom 1–5 (`APP_ID\tTITLE\tSTATUS\tGAME_DIR\tGAME_BIN`) agar seluruh consumer dan test eksisting tetap utuh.
3. **Zero Key Collision Store Filter (`src/tui/70_dashboard.sh`)**:
   - Menambahkan filter store via `Tab` dan `Alt-S` pada `library_menu` (`ALL | STEAM | STANDALONE`), menjaga `Ctrl-S` tetap eksklusif untuk Unified Remote Sync Palette.

---

## 2. Rencana Eksekusi Detail (Packet 38A - 38D)

### [ ] Packet 38A: Unified Store Interface (`src/stores/00_store_interface.sh`)
- **Target Files**: `src/stores/00_store_interface.sh`, `scripts/build.sh`
- **Langkah Teknis**:
  1. Buat `src/stores/00_store_interface.sh`:
     - `store_list_registered()`: mencetak daftar adapter store terdaftar (`steam`, diperluas saat WP39+).
     - `store_list_available()`: mengecek `store_<name>_available` dan melaporkan store yang siap secara offline.
     - `store_dispatch <store> <op> [args...]`: memvalidasi nama store/operasi (`available|status|search|list_installed|download|sync`) dan meneruskan ke `store_<store>_<op>`, mengembalikan error terstruktur ke `stderr` bila tidak didukung.
     - Loader sibling standalone saat di-`source` langsung di luar `bin/gamectl` (`[ -z "${GAMECTL_BUNDLED:-}" ]`).
  2. Daftarkan `src/stores/00_store_interface.sh` dan `src/stores/10_store_steam.sh` ke `MODULES=(...)` di `scripts/build.sh`.
- **Definition of Done (DoD)**:
  - `store_dispatch` menolak store/op invalid dengan exit non-zero dan pesan `stderr`.
  - `./scripts/build.sh` dan `STRICT_LINT=1 make lint` lulus.

### [ ] Packet 38B: Built-in Steam Store Adapter (`src/stores/10_store_steam.sh`)
- **Target Files**: `src/stores/10_store_steam.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Implementasikan adapter tipis yang membungkus `src/steam/{30_downloader,31_manifests}.sh`:
     - `store_steam_available`: cek ketersediaan `gamectl-depot-dl` atau provider manifest dasar.
     - `store_steam_status`: laporkan status `gamectl-depot-dl`, GBE templates, dan LuaTools session secara offline-safe.
     - `store_steam_search <query>`: query Steam Store API tervalidasi `validate_tui_fields` -> format TSV `<STORE>\t<APP_ID>\t<TITLE>\t<PLATFORMS>\t<STATUS>`.
     - `store_steam_list_installed`: pindai entri Steam/Standalone dari `scan_installed_games`.
     - `store_steam_download <app_id> <target_dir> [opts]`: delegasi ke `download_game`.
     - `store_steam_sync <app_id> <game_dir>`: sinkronisasi manifest/DLC offline (`fetch_dlc`), tanpa mengaktifkan Steam Client kecuali diminta eksplisit.
  2. Ekspor helper store dan tambahkan subcommand CLI `gamectl stores [list|status]` di `src/main.sh`.
- **Definition of Done (DoD)**:
  - Zero regresi pada perintah standalone (`download`, `inject`, `search`, `sync-steam`).
  - Seluruh output katalog lolos `validate_tui_fields`.

### [ ] Packet 38C: Backward-Compatible Scanner v3 (`src/steam/20_discovery.sh`)
- **Target Files**: `src/steam/20_discovery.sh`
- **Langkah Teknis**:
  1. Naikkan header cache dari `# gamectl scanner v2` -> `# gamectl scanner v3` agar cache v2 lama otomatis ter-refresh.
  2. Tambahkan Kolom 6 `STORE` (`STEAM` untuk game dari Steam `appmanifest_*.acf`, `STANDALONE` untuk game dari `~/Games/` atau library kustom non-ACF; siap menerima adapter `GOG`/`EPIC`/`AMAZON`).
  3. Pertahankan format 5 kolom terdepan (`APP_ID\tTITLE\tSTATUS\tGAME_DIR\tGAME_BIN`) serta mode `--formatted` dan raw TSV tanpa memutus `cut -f1..5`, `awk`, `preview_game`, maupun `cli_launch`.
- **Definition of Done (DoD)**:
  - Cache `# gamectl scanner v2` ditolak/di-refresh ke v3.
  - Seluruh consumer 5 kolom dan test discovery eksisting tetap 100% PASS.

### [ ] Packet 38D: TUI Store Switcher, Regression Contracts & Full Verification
- **Target Files**: `src/tui/70_dashboard.sh`, `tests/test_remediation.sh`, `bin/gamectl`
- **Langkah Teknis**:
  1. Tambahkan state filter store aktif di `library_menu()` (`ALL` -> `STEAM` -> `STANDALONE`) yang di-cycle lewat `Tab` dan dipilih langsung lewat `Alt-S` (tanpa menyentuh `Ctrl-S` Remote Sync).
  2. Tambahkan Tests 31–32 di `tests/test_remediation.sh`:
     - **Test 31 (38A/38B)**: kontrak `store_list_registered`, `store_dispatch`, `store_steam_*`, dan sanitasi `validate_tui_fields`.
     - **Test 32 (38C/38D)**: kontrak scanner v3 6-kolom (`STEAM` vs `STANDALONE`), invalidasi cache v2, kompatibilitas consumer 5-kolom, dan `gamectl stores`.
  3. Kompilasi ulang `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`) dan jalankan full gate (`STRICT_LINT=1 make lint`, `test_depot_filter.sh`, `test_remediation.sh`, Python safety 42/42, `test_cli.sh` 147/147, `test_tui_ergonomics.sh`).
- **Definition of Done (DoD)**:
  - Seluruh suite lint, Bash, Rust, dan Python lulus Exit Code `0` tanpa regresi.
