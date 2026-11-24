# WORK PACKET 38: MULTI-STORE PHASE 1 (STORE INTERFACE, STEAM ADAPTER, SCANNER V3 & FILTER)

- **Track**: Multi-Store Architecture / Discovery Schema v3 / TUI Filter
- **Status**: PENDING [0/4 PACKETS]
- **Riwayat Selesai**: WP33..WP36 (`9a1be91..15e95bc`), CI/Dual-License/Hygiene (`5ea7948..a678046`), Modular Core & Steam Split (`a73bfc5..085327b`), RFC Multi-Store v2.0 (`2af9c4c`) — seluruhnya COMPLETED & terverifikasi.
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
