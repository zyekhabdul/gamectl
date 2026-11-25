# WORK PACKET 41: MULTI-STORE PHASE 4 (AMAZON NILE, UNIFIED AUTH HUB & CROSS-STORE SEARCH)

- **Track**: Multi-Store Phase 4 / Amazon Adapter (`nile`), Unified Auth Hub & Search Aggregation
- **Status**: COMPLETED [4/4 PACKETS]
- **Prasyarat**: WP40 (Optional Epic Adapter via `legendary` — COMPLETED, `76a0630`) & Remediation Work Packet 2 (Steam App-Type SSoT & Engine-Level DLC Guard — COMPLETED, `457001c`)
- **Riwayat Selesai**: WP33..WP40, SIGPIPE/ShellCheck & `0755` Bundle (`d5aaccc..096ef82`), Parallel Lint & TUI Safety Perf (`0137446..3c9299e`), Multi-Store Phase 2 GOG WP39 (`5823b26..cefff4a`), Arch/AUR Cargo Source-Build & Locked `depot-dl` (`52b9883..c83a363`), Multi-Store Phase 3 Epic WP40 (`5c2701a..76a0630`), dan Remediation Work Packet 2 (`dbd262c..457001c`).
- **Basis**: `docs/RFC_MULTISTORE_SUPPORT.md` (v2.0), `docs/REMEDIATION.md` (Work Packet 2), dan `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`.
- **Target Files**: `src/stores/40_store_amazon.sh`, `src/stores/00_store_interface.sh`, `src/stores/10_store_steam.sh`, `src/stores/20_store_gog.sh`, `src/stores/30_store_epic.sh`, `src/steam/20_discovery.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`, `src/main.sh`, `scripts/build.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`, `DEVELOPMENT.md`, `bin/gamectl`

---

## 1. Tujuan & Invarian Phase 4

1. **Optional External CLI Invariant**:
   - `nile` berstatus **opsional penuh** (`optdepends`). Mesin tanpa `nile` harus tetap lulus 100% test suite standalone dan menjalankan seluruh alur Steam/GOG/Epic/Standalone tanpa warning palsu.
2. **Zero Plaintext Credential Storage**:
   - `gamectl` dilarang menyimpan token atau kredensial Amazon sendiri; autentikasi didelegasikan ke CLI native (`nile auth`, `gogdl auth`/`lgogdownloader --login`, `legendary auth`, `login_luatools`) via `gamectl auth`. Status sesi dibaca secara offline-safe dari direktori konfigurasi tool terkait tanpa mencetak isi secret.
3. **Canonical App-Type Taxonomy & Input Sanitization**:
   - Pencarian lintas store mewarisi kosakata token tipe kanonik tertutup dari `src/steam/31_manifests.sh` (`GAME`, `DLC`, `DEMO`, `MOD`, `SOUNDTRACK`, `TOOL`, `APP`). Seluruh field metadata (`app_id`, `title`, `platforms`, `install_path`, `executable`) wajib menolak `[\t\r\n]` di `jq` dan lolos `validate_tui_fields`; payload JSON cacat ditolak langsung.
4. **Zero Key Collision & Deduplikasi**:
   - `Tab` dan `Alt-S` pada `library_menu` memperluas siklus filter (`ALL -> STEAM -> GOG -> EPIC -> AMAZON -> STANDALONE -> ALL`), menjaga `Ctrl-S` tetap eksklusif untuk Unified Remote Sync Palette. Game Amazon di dalam `~/Games/` tidak boleh terduplikasi sebagai `STANDALONE`.
5. **Pre-Commit Hook Hygiene**:
   - Jaga `src/stores/40_store_amazon.sh` <= 145 baris; pecah commit implementasi (`41A`, `41B`, `41C`), `bin/gamectl`, `tests/test_remediation.sh`, dan docs agar tiap commit source <= 150 baris diff dan edit tes terpisah dari source code.

---

## 2. Rencana Eksekusi Detail (Packet 41A - 41D)

### [x] Packet 41A: Amazon Prime Gaming Adapter (`src/stores/40_store_amazon.sh`) & Registry
- **Target Files**: `src/stores/40_store_amazon.sh`, `src/stores/00_store_interface.sh`, `scripts/build.sh`
- **Langkah Teknis**:
  1. Buat `src/stores/40_store_amazon.sh` (<= 145 LOC) yang mengimplementasikan kontrak `store_amazon_*`:
     - `_amazon_config_dir()`: resolve `${NILE_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/nile}`.
     - `_amazon_resolve_cli()` & `store_amazon_available()`: probe `command -v nile >/dev/null 2>&1`.
     - `store_amazon_status()`: laporkan `store=amazon`, status CLI (`ready`/`missing`), dan keberadaan `user.json` di `_amazon_config_dir()` secara offline-safe (`always exit 0`, zero network).
     - `store_amazon_search <query>`: tolak query kosong & CLI absen; query `nile library list --json` (atau fallback `nile list-games --json`), filter case-insensitive pada `product.id`/`product.title` di `jq` sambil menolak `[\t\r\n]`, sanitasi via `validate_tui_fields`, tandai `INSTALLED`/`AVAILABLE` dari `scan_installed_games --store AMAZON`, dan cetak TSV `AMAZON\t<APP_ID>\t<TITLE>\t<PLATFORMS>\t<STATUS>`.
     - `store_amazon_list_installed()`: delegasi ke `scan_installed_games --store AMAZON "$@"`.
     - `store_amazon_download <app_id> [target_dir] [opts...]`: validasi `app_id` (`^[0-9A-Za-z._-]+$`, tolak `..`), default `target_dir="${GAMECTL_LIBRARY_DIR:-$HOME/Games}/$app_id"`, delegasi ke `nile install "$app_id" --path "$target_dir" "$@"`, lalu `invalidate_scan_cache`.
     - `store_amazon_sync <app_id> <game_dir> [opts...]`: validasi argumen & direktori, jalankan `backup_save "$game_dir" true || return $?` sebelum operasi verifikasi/repair (`nile verify "$app_id" --path "$game_dir"` atau laporan terstruktur bila CLI tidak mendukung).
     - `amazon_cli <status|auth|search|download|sync|--help>`: delegasi `status/search/download/sync` ke `store_dispatch amazon` dan `auth` ke `nile auth "$@"`.
  2. Daftarkan `"amazon"` di `store_list_registered()` dan `40_store_amazon.sh` di sibling auto-loader `src/stores/00_store_interface.sh`.
  3. Tambahkan `"$REPO_ROOT/src/stores/40_store_amazon.sh"` ke `MODULES=(...)` di `scripts/build.sh` tepat setelah `30_store_epic.sh`.
- **Definition of Done (DoD)**:
  - `store_list_registered` mengembalikan `steam`, `gog`, `epic`, `amazon`; `store_dispatch amazon ...` bekerja bersih dengan mock `nile` dan gagal terstruktur ke `stderr` saat `nile` absen.

### [x] Packet 41B: Amazon Discovery, `gamectl amazon`, TUI Filter & Optional Doctor Probe
- **Target Files**: `src/steam/20_discovery.sh`, `src/main.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`, `completions/gamectl.bash`
- **Langkah Teknis**:
  1. Di `src/steam/20_discovery.sh`:
     - Tambahkan pengecekan mtime `$(_amazon_config_dir)/installed.json` pada validasi cache `scan_installed_games()`.
     - Pindai `installed.json` milik `nile` **sebelum** loop `custom_search_dirs` agar `seen_dirs` mencatat path kanonis game Amazon dan folder di `~/Games/` tidak terduplikasi sebagai `STANDALONE`. Tolak entry korup / berkarakter `[\t\r\n]` ke `stderr` (`[ERROR]`) tanpa menggagalkan entry valid; set `STATUS=AMAZON` (bila `STANDALONE`) dan Kolom 6 `STORE=AMAZON`.
     - Tambahkan badge `*AMAZON*)` pada mode `--formatted` sambil mempertahankan header `# gamectl scanner v3`.
  2. Di `src/main.sh` & `completions/gamectl.bash`: tambahkan subcommand `gamectl amazon <status|auth|search|download|sync>` + `--help` dan completion `amazon`.
  3. Di `src/tui/70_dashboard.sh`: perluas siklus `Tab` pada `library_menu()` menjadi `ALL -> STEAM -> GOG -> EPIC -> AMAZON -> STANDALONE -> ALL` dan tambahkan `AMAZON\tAmazon Games Library (Nile)` di `Alt-S` tanpa menyentuh `Ctrl-S`.
  4. Di `src/diagnostics/60_doctor.sh`: tambahkan probe opsional `[OPT]`/`[READY]` untuk `nile` pada Layer 6 tepat setelah `Epic Store CLI` tanpa menambah `warn_cnt`/`miss_cnt` saat absen.
- **Definition of Done (DoD)**:
  - `gamectl doctor` tetap pass tanpa `nile`; `installed.json` Amazon terindeks sebagai `STORE=AMAZON` tanpa duplikasi di `STANDALONE`; `Tab`/`Alt-S` memfilter `AMAZON` dengan nol bentrokan `Ctrl-S`.

### [x] Packet 41C: Unified Auth Hub (`gamectl auth`) & Cross-Store Search (`search_stores`)
- **Target Files**: `src/stores/00_store_interface.sh`, `src/stores/10_store_steam.sh`, `src/stores/20_store_gog.sh`, `src/stores/30_store_epic.sh`, `src/stores/40_store_amazon.sh`, `src/main.sh`, `src/tui/70_dashboard.sh`, `completions/gamectl.bash`
- **Langkah Teknis**:
  1. Tambahkan `auth_hub_cli <status|gog|epic|amazon|luatools>` di `src/stores/00_store_interface.sh` dan wire ke `gamectl auth` di `src/main.sh` + `completions/gamectl.bash`:
     - `status`: merangkum status offline seluruh store (`steam/luatools`, `gog`, `epic`, `amazon`) tanpa mencetak secret.
     - `<store>`: mendelegasikan login ke `gog_cli auth`, `epic_cli auth`, `amazon_cli auth`, atau `login_luatools` / `login_luatools_interactive`.
  2. Tambahkan `store_search_all <query> [--store <all|steam|gog|epic|amazon>]` di `src/stores/00_store_interface.sh` (dan alias CLI `gamectl search-stores <query>` / `search_stores`):
     - Mengagregasi adapter yang `available` (atau store spesifik yang diminta) dengan tetap menjaga kontrak 5-kolom existing `store_<name>_search` (`STORE\tAPP_ID\tTITLE\tPLATFORMS\tSTATUS`).
     - Memperkaya output gabungan menjadi TSV 7-kolom tervalidasi `STORE\tAPP_ID\tTITLE\tPLATFORMS\tSTATUS\tITEM_TYPE\tPARENT_APPID`: baris `STEAM` diklasifikasikan batch via `classify_steam_app_types` (fallback `APP` saat offline), sedangkan `GOG`/`EPIC`/`AMAZON` dipetakan ke token kanonik `GAME` (tanpa duplikasi parser).
  3. Di `src/tui/70_dashboard.sh`: hubungkan opsi switcher/pencarian lintas store opsional agar item non-Steam dari `search_stores` dapat diarahkan ke `store_dispatch <store> download`, sementara item `STEAM` tetap memakai `download_game` (beserta engine-level DLC guard).
- **Definition of Done (DoD)**:
  - `gamectl auth status` bekerja 100% offline tanpa store CLI eksternal; `gamectl search-stores <query>` mengembalikan TSV 7-kolom tervalidasi dengan klasifikasi kanonik lintas store tanpa merusak test 5-kolom `store_<name>_search` yang sudah ada.

### [x] Packet 41D: Contract Tests, Docs, Rebuild & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `DEVELOPMENT.md`, `PLAN.md`, `bin/gamectl`
- **Langkah Teknis**:
  1. Perbarui Test 32 di `tests/test_remediation.sh` (`if idx < 5:` dan cek `[Store: AMAZON]`) serta tambahkan Tests 39–40:
     - **Test 39 (41A/41B)**: kontrak `store_dispatch amazon`, `store_amazon_status` offline-safe, error saat `nile` absen, `doctor_audit` `[OPT]`, mock `nile` (`library list --json`, penolakan `\t`/`\n`, `install`, `verify` dengan `backup_save`), `installed.json` discovery (`$6 == "AMAZON"`), deduplikasi `~/Games/`, dan `Tab`/`Alt-S` (`AMAZON`).
     - **Test 40 (41C)**: `gamectl auth status` offline-safe + delegasi `auth`, serta `store_search_all` / `gamectl search-stores` 7-kolom lintas store dengan klasifikasi `GAME`/`DLC` Steam dan `GAME` store lain.
  2. Perbarui peta modul `src/stores/40_store_amazon.sh` di `DEVELOPMENT.md` dan tandai WP41 selesai di `PLAN.md`.
  3. Kompilasi ulang `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`) dan jalankan full gate (`STRICT_LINT=1 make lint`, `make test`, dan bersihkan `.deb`).
- **Definition of Done (DoD)**:
  - Seluruh lint, bundle check, suite Bash (`test_cli.sh`, `test_remediation.sh`, `test_tui_ergonomics.sh`, `test_depot_filter.sh`, `test_hubcap.sh`), dan Python safety tests lulus Exit Code `0` tanpa ketergantungan CLI eksternal nyata.
