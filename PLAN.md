# WORK PACKET 39: MULTI-STORE PHASE 2 (GOG ADAPTER, DISCOVERY, CLI & OPTIONAL PROBE)

- **Track**: Multi-Store Phase 2 / DRM-Free GOG Adapter (`gogdl` / `lgogdownloader`)
- **Status**: COMPLETED [4/4 PACKETS]
- **Prasyarat**: WP38 (Unified Store Interface, Steam Adapter, Scanner v3 & TUI Filter) — COMPLETED
- **Riwayat Selesai**: WP33..WP36 (`9a1be91..15e95bc`), CI/Dual-License/Hygiene (`5ea7948..804675e`), Modular Core/Steam/Runners/TUI Split WP37 (`2655748..505b758`), Multi-Store Phase 1 WP38 (`a4caa1d..1c93ff5`), Nix `buildRustPackage` & `export -f` Pruning (`afe0af4..0188408`), serta SIGPIPE/ShellCheck Hardening (working tree terverifikasi).
- **Basis**: `docs/RFC_MULTISTORE_SUPPORT.md` (v2.0) dan `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`.
- **Target Files**: `src/stores/20_store_gog.sh`, `src/stores/00_store_interface.sh`, `src/steam/20_discovery.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`, `src/main.sh`, `scripts/build.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`, `DEVELOPMENT.md`, `bin/gamectl`

---

## 1. Tujuan & Invarian Phase 2

1. **Optional External CLI Invariant**:
   - `gogdl` (prioritas utama) dan `lgogdownloader` (fallback) berstatus **opsional penuh** (`optdepends`). Mesin tanpa `gogdl`/`lgogdownloader` harus tetap lulus 100% test suite dan menjalankan seluruh alur Steam/Standalone tanpa warning palsu.
2. **Zero Plaintext Credential Storage**:
   - `gamectl` dilarang menyimpan kredensial atau token GOG sendiri; autentikasi didelegasikan ke `gogdl auth` / `lgogdownloader --login` dan status dibaca dari file sesi milik tool terkait secara offline-safe.
3. **Offline Resilience & Sanitization**:
   - Seluruh output metadata/pencarian wajib melewati `validate_tui_fields` (menolak TAB/CR/LF) sebelum masuk ke `scancache.tab` atau `fzf`. Kegagalan jaringan/CLI dilaporkan terstruktur ke `stderr` dengan exit non-zero.
4. **Zero Key Collision**:
   - `Tab` dan `Alt-S` pada `library_menu` memperluas siklus filter (`ALL -> STEAM -> GOG -> STANDALONE`), menjaga `Ctrl-S` eksklusif untuk Unified Remote Sync Palette.

---

## 2. Rencana Eksekusi Detail (Packet 39A - 39D)

### [x] Packet 39A: GOG Store Adapter (`src/stores/20_store_gog.sh`) & Registry
- **Target Files**: `src/stores/20_store_gog.sh`, `src/stores/00_store_interface.sh`, `scripts/build.sh`
- **Langkah Teknis**:
  1. Buat `src/stores/20_store_gog.sh` yang mengimplementasikan kontrak `store_gog_*`:
     - `_gog_resolve_cli()`: probe `gogdl` terlebih dahulu, lalu `lgogdownloader`; kembalikan `1` bila keduanya absen.
     - `store_gog_available()`: offline-safe probe via `_gog_resolve_cli >/dev/null 2>&1`.
     - `store_gog_status()`: tampilkan CLI aktif (`gogdl` / `lgogdownloader` / `missing`) dan status sesi auth lokal tanpa panggilan jaringan (`always exit 0`).
     - `store_gog_search <query>`: tolak query kosong; jalankan pencarian katalog GOG (`gogdl` / GOG catalog API / `lgogdownloader --list-details`) atau gagal bersih jika offline/tidak terinstal; sanitasi via `validate_tui_fields` dan cetak TSV `GOG\t<PRODUCT_ID>\t<TITLE>\t<PLATFORMS>\t<STATUS>`.
     - `store_gog_list_installed()`: delegasi ke `scan_installed_games --store GOG "$@"`.
     - `store_gog_download <product_id> [target_dir] [opts...]`: validasi `<product_id>` dan delegasi ke `gogdl download` / `lgogdownloader --download` langsung ke direktori target; laporkan error jelas bila CLI tidak tersedia.
     - `store_gog_sync <product_id> <game_dir>`: sinkronisasi cloud save GOG via `gogdl save-sync` (jika tersedia), dengan `backup_save` snapshot 3-slot sebelum mutasi lokal.
  2. Daftarkan `"gog"` di `store_list_registered()` serta `20_store_gog.sh` di sibling auto-loader `src/stores/00_store_interface.sh`.
  3. Tambahkan `"$REPO_ROOT/src/stores/20_store_gog.sh"` ke `MODULES=(...)` di `scripts/build.sh` tepat setelah `10_store_steam.sh`.
- **Definition of Done (DoD)**:
  - `store_list_registered` mengembalikan `steam` dan `gog`; `store_dispatch gog ...` berjalan bersih saat `gogdl`/`lgogdownloader` tersedia (mocked atau nyata) dan gagal terstruktur ke `stderr` saat absen.

### [x] Packet 39B: GOG Local Installation Discovery (`src/steam/20_discovery.sh`)
- **Target Files**: `src/steam/20_discovery.sh`
- **Langkah Teknis**:
  1. Perluas `scan_installed_games()` pada pemindaian direktori kustom (`~/Games/`, `~/GOG Games/`, `~/.config/gamectl/libraries`, `GAMECTL_LIBRARY_DIRS`) untuk mendeteksi metadata instalasi GOG (`goggame-*.info` atau `.gog_id` + `gameinfo`):
     - Ekstrak `gameId` (Kolom 1 `APP_ID`), `name` (Kolom 2 `TITLE`, divalidasi `validate_tui_fields`), `STATUS` (`GOG` atau status DRM lokal), `GAME_DIR`, `GAME_BIN`, dan Kolom 6 `STORE=GOG`.
     - Pastikan game non-GOG di direktori yang sama tetap berlabel `STORE=STANDALONE` dan game Steam ACF tetap `STORE=STEAM`.
  2. Terapkan dukungan `--store GOG` tanpa mengubah format 6-kolom atau cache `# gamectl scanner v3`.
- **Definition of Done (DoD)**:
  - Direktori berisi `goggame-*.info` valid terindeks sebagai `STORE=GOG` pada `scan_installed_games`; nama berkarakter `\t`/`\n` tetap ditolak oleh `validate_tui_fields`.

### [x] Packet 39C: CLI `gamectl gog`, TUI Filter & Optional Doctor Probe
- **Target Files**: `src/main.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`, `completions/gamectl.bash`
- **Langkah Teknis**:
  1. Tambahkan subcommand `gamectl gog <status|auth|search|download|sync> [args...]` dan `--help` di `src/main.sh` serta completion `gog` di `completions/gamectl.bash`.
  2. Perluas siklus filter `library_menu()` di `src/tui/70_dashboard.sh`:
     - `Tab`: `ALL -> STEAM -> GOG -> STANDALONE -> ALL`.
     - `Alt-S`: tambahkan opsi `GOG\tGOG Library (DRM-Free)` ke picker `tui_action_palette`.
  3. Tambahkan probe opsional `[OPT]` pada `doctor_audit()` di `src/diagnostics/60_doctor.sh` untuk mendeteksi `gogdl` / `lgogdownloader` tanpa menurunkan skor kesiapan atau memberi peringatan wajib bila tidak terpasang.
- **Definition of Done (DoD)**:
  - `gamectl doctor` tetap pass pada host tanpa `gogdl`/`lgogdownloader`; `library_menu` `Tab`/`Alt-S` memfilter `GOG` dengan nol bentrokan `Ctrl-S`.

### [x] Packet 39D: Contract Tests, Docs, Rebuild & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `DEVELOPMENT.md`, `PLAN.md`, `bin/gamectl`
- **Langkah Teknis**:
  1. Tambahkan Tests 33–34 di `tests/test_remediation.sh`:
     - **Test 33 (39A/39C)**: kontrak `store_dispatch gog`, `store_gog_available`, `store_gog_status` (offline-safe & bebas plain credential), `store_gog_search` (mock `gogdl` + penolakan separator `validate_tui_fields`), fallback pesan error saat `gogdl`/`lgogdownloader` absen, serta `gamectl gog` CLI.
     - **Test 34 (39B/39C)**: deteksi `goggame-*.info` pada `scan_installed_games` (`$6 == "GOG"`), filter `--store GOG`, serta siklus `Tab` (`ALL -> STEAM -> GOG -> STANDALONE`) pada `library_menu`.
  2. Perbarui peta modul `src/stores/20_store_gog.sh` di `DEVELOPMENT.md` dan tandai WP39 selesai di `PLAN.md`.
  3. Kompilasi ulang `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`) dan jalankan full gate (`bash -n`, `shellcheck` per-file, `make test` termasuk 42 Python tests, `test_cli.sh` 147/147, `test_remediation.sh` 35/35).
- **Definition of Done (DoD)**:
  - Seluruh suite Bash, Python, dan lint lulus Exit Code `0` tanpa regresi pada alur Steam/Standalone maupun tanpa dependensi `gogdl` nyata di CI.
