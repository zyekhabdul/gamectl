# WORK PACKET 40: MULTI-STORE PHASE 3 (EPIC GAMES ADAPTER VIA LEGENDARY)

- **Track**: Multi-Store Phase 3 / Epic Games Store Adapter (`legendary`)
- **Status**: COMPLETED [4/4 PACKETS]
- **Prasyarat**: WP39 (Optional GOG Adapter, Discovery, CLI & Doctor Probe) — COMPLETED (`5823b26..cefff4a`)
- **Riwayat Selesai**: WP33..WP38, SIGPIPE/ShellCheck & `0755` Bundle (`d5aaccc..096ef82`), Parallel Lint & TUI Safety Perf (`0137446..3c9299e`), Multi-Store Phase 2 GOG WP39 (`5823b26..cefff4a`), dan Arch/AUR Cargo Source-Build & Locked `depot-dl` (`52b9883..c83a363`).
- **Basis**: `docs/RFC_MULTISTORE_SUPPORT.md` (v2.0) dan `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`.
- **Target Files**: `src/stores/30_store_epic.sh`, `src/stores/00_store_interface.sh`, `src/steam/20_discovery.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`, `src/main.sh`, `scripts/build.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`, `DEVELOPMENT.md`, `bin/gamectl`

---

## 1. Tujuan & Invarian Phase 3

1. **Optional External CLI Invariant**:
   - `legendary` berstatus **opsional penuh** (`optdepends`). Mesin tanpa `legendary` harus tetap lulus 100% test suite standalone dan menjalankan seluruh alur Steam/GOG/Standalone tanpa warning palsu.
2. **Zero Plaintext Credential Storage**:
   - `gamectl` dilarang menyimpan token atau kredensial Epic sendiri; autentikasi didelegasikan ke `legendary auth`, dan status sesi dibaca secara offline-safe dari keberadaan `${LEGENDARY_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/legendary}/user.json` tanpa mencetak isi secret.
3. **Offline Resilience & Sanitization**:
   - Seluruh output metadata (`installed.json`, `legendary list --json`) wajib menolak `\t`/`\r`/`\n` di `jq` serta melewati `validate_tui_fields` sebelum masuk ke `scancache.tab` atau `fzf`. Payload JSON cacat harus ditolak langsung (tidak boleh jatuh ke cabang TSV).
4. **Zero Key Collision & Deduplikasi**:
   - `Tab` dan `Alt-S` pada `library_menu` memperluas siklus filter (`ALL -> STEAM -> GOG -> EPIC -> STANDALONE -> ALL`), menjaga `Ctrl-S` eksklusif untuk Unified Remote Sync Palette. Game Epic di dalam `~/Games/` tidak boleh terduplikasi sebagai `STANDALONE`.
5. **Pre-Commit Hook Hygiene**:
   - Jaga `src/stores/30_store_epic.sh` <= 145 baris; pecah commit `bin/gamectl` dan `tests/test_remediation.sh` agar tiap commit <= 150 baris diff dan edit tes terpisah dari source code.

---

## 2. Rencana Eksekusi Detail (Packet 40A - 40D)

### [x] Packet 40A: Epic Store Adapter (`src/stores/30_store_epic.sh`) & Registry
- **Target Files**: `src/stores/30_store_epic.sh`, `src/stores/00_store_interface.sh`, `scripts/build.sh`
- **Langkah Teknis**:
  1. Buat `src/stores/30_store_epic.sh` (<= 145 LOC) yang mengimplementasikan kontrak `store_epic_*`:
     - `_epic_config_dir()`: resolve `${LEGENDARY_CONFIG_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/legendary}`.
     - `_epic_resolve_cli()` & `store_epic_available()`: probe `command -v legendary >/dev/null 2>&1`.
     - `store_epic_status()`: laporkan `store=epic`, status CLI (`ready`/`missing`), dan keberadaan `user.json` secara offline-safe (`always exit 0`, zero network).
     - `store_epic_search <query>`: tolak query kosong & CLI absen; query `legendary list --json`, filter case-insensitive pada `app_name`/`app_title` di `jq` sambil menolak `[\t\r\n]`, sanitasi via `validate_tui_fields`, tandai `INSTALLED`/`AVAILABLE` dari `scan_installed_games --store EPIC`, dan cetak TSV `EPIC\t<APP_NAME>\t<TITLE>\t<PLATFORMS>\t<STATUS>`.
     - `store_epic_list_installed()`: delegasi ke `scan_installed_games --store EPIC "$@"`.
     - `store_epic_download <app_name> [target_dir] [opts...]`: validasi `app_name` (`^[0-9A-Za-z._-]+$`), default `target_dir="${GAMECTL_LIBRARY_DIR:-$HOME/Games}/$app_name"`, delegasi ke `legendary install "$app_name" --game-folder "$target_dir" -y "$@"`, lalu `invalidate_scan_cache`.
     - `store_epic_sync <app_name> <game_dir> [opts...]`: validasi argumen & direktori, jalankan `backup_save "$game_dir" true || return $?` (snapshot 3-slot sebelum mutasi lokal), lalu `legendary sync-saves "$app_name" --save-path "$game_dir/saves" "$@"`.
     - `epic_cli <status|auth|search|download|sync|launch|--help>`: delegasi `status/search/download/sync` ke `store_dispatch epic`, `auth` ke `legendary auth "$@"`, dan opsional eksplisit `launch` ke `legendary launch "$@"`.
  2. Daftarkan `"epic"` di `store_list_registered()` dan `30_store_epic.sh` di sibling auto-loader `src/stores/00_store_interface.sh`.
  3. Tambahkan `"$REPO_ROOT/src/stores/30_store_epic.sh"` ke `MODULES=(...)` di `scripts/build.sh` tepat setelah `20_store_gog.sh`.
- **Definition of Done (DoD)**:
  - `store_list_registered` mengembalikan `steam`, `gog`, `epic`; `store_dispatch epic ...` bekerja bersih dengan mock `legendary` dan gagal terstruktur ke `stderr` saat `legendary` absen.

### [x] Packet 40B: Epic Local Installation Discovery (`src/steam/20_discovery.sh`)
- **Target Files**: `src/steam/20_discovery.sh`
- **Langkah Teknis**:
  1. Tambahkan pengecekan mtime `$(_epic_config_dir)/installed.json` pada validasi cache `scan_installed_games()`.
  2. Pindai `installed.json` milik `legendary` **sebelum** loop `custom_search_dirs` agar `seen_dirs` mencatat path kanonis game Epic sehingga folder Epic di `~/Games/` tidak terduplikasi sebagai `STANDALONE`:
     - Iterasi per entry (`to_entries[]`) dengan `jq`: entry yang mengandung `[\t\r\n]` pada `app_name`, `title`, `install_path`, atau `executable` dilaporkan ke `stderr` (`[ERROR]`) dan di-skip tanpa menggagalkan entry valid lain.
     - Validasi `[ -d "$install_path" ]`, resolusi binary (`executable` JSON atau fallback `find_game_binary`), validasi `validate_tui_fields`, set `STATUS=EPIC` (jika `STANDALONE`) dan Kolom 6 `STORE=EPIC`.
  3. Tambahkan badge `*EPIC*)` pada mode `--formatted` sambil mempertahankan header `# gamectl scanner v3`.
- **Definition of Done (DoD)**:
  - Entri `installed.json` valid terindeks sebagai `STORE=EPIC` pada `scan_installed_games`, tidak terduplikasi di `STANDALONE`, dan entri berkarakter `\t`/`\n` ditolak bersih.

### [x] Packet 40C: CLI `gamectl epic`, TUI Filter & Optional Doctor Probe
- **Target Files**: `src/main.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`, `completions/gamectl.bash`
- **Langkah Teknis**:
  1. Tambahkan subcommand `gamectl epic <status|auth|search|download|sync|launch>` + `--help` di `src/main.sh` dan completion `epic` di `completions/gamectl.bash`.
  2. Perluas siklus filter `library_menu()` di `src/tui/70_dashboard.sh`:
     - `Tab`: `ALL -> STEAM -> GOG -> EPIC -> STANDALONE -> ALL`.
     - `Alt-S`: tambahkan `EPIC\tEpic Games Library (Legendary)` ke `tui_action_palette` tanpa menyentuh `Ctrl-S`.
  3. Tambahkan probe opsional `[OPT]`/`[READY]` untuk `legendary` pada Layer 6 di `doctor_audit()` (`src/diagnostics/60_doctor.sh`) tepat setelah `GOG Store CLI` tanpa menambah `warn_cnt`/`miss_cnt` saat absen.
- **Definition of Done (DoD)**:
  - `gamectl doctor` tetap pass tanpa `legendary`; `library_menu` `Tab`/`Alt-S` memfilter `EPIC` dengan nol bentrokan `Ctrl-S`.

### [x] Packet 40D: Contract Tests, Docs, Rebuild & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `DEVELOPMENT.md`, `PLAN.md`, `bin/gamectl`
- **Langkah Teknis**:
  1. Perbarui Test 32 di `tests/test_remediation.sh` (`if idx < 4:` dan cek `[Store: EPIC]`) serta tambahkan Tests 35–36:
     - **Test 35 (40A/40C)**: kontrak `store_dispatch epic`, `store_epic_status` offline-safe tanpa kredensial lokal, pesan error saat `legendary` absen, `doctor_audit` `[OPT]`, mock `legendary` (`list --json`, penolakan `\t`/`\n`, `install`, `sync-saves` dengan `backup_save` snapshot 3-slot), dan `gamectl epic` CLI.
     - **Test 36 (40B/40C)**: deteksi `installed.json` (`$6 == "EPIC"`), deduplikasi terhadap `~/Games/`, penolakan entri rusak tanpa menjatuhkan entri valid, `--store EPIC`, serta siklus `Tab`/`Alt-S` (`EPIC`) dan `Ctrl-S`.
  2. Perbarui peta modul `src/stores/30_store_epic.sh` di `DEVELOPMENT.md` dan tandai WP40 selesai di `PLAN.md`.
  3. Kompilasi ulang `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`) dan jalankan full gate (`STRICT_LINT=1 make lint`, `make test` mencakup `test_cli.sh` 147/147, `test_remediation.sh` 37/37, dan 42 Python tests), lalu bersihkan `.deb`.
- **Definition of Done (DoD)**:
  - Seluruh suite Bash, Python, dan lint lulus Exit Code `0` tanpa regresi maupun ketergantungan `legendary` nyata di CI.
