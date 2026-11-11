# WORK PACKET 24: LINUX RUNTIME MATURITY, TELEMETRY, & COMMUNITY FIXES INTEGRATION

**Track**: Linux Runtime Maturity & TUI Parity  
**Status**: COMPLETED [VERIFIED]  
**Branch**: `main`  
**Max Chunks**: 8 Chunks (Active Packet <= 10)  
**Target Files**: `src/tui/70_dashboard.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/runners/50_launcher.sh`, `src/diagnostics/60_doctor.sh`, `src/core/10_utils.sh`, `src/main.sh`, `tests/test_cli.sh`, `bin/gamectl`

---

## 1. Objective & Technical Scope
Menuntaskan seluruh kesenjangan tampilan dan fitur interaktif Linux runtime maturity:
1. **Steam Store Search & ProtonDB Preview Engine (`--preview-search`)**: Mengeliminasi error dash `/bin/sh`, kebocoran teks literal `-e`, dan fake `[NO REPORTS YET]`, menyajikan data genre, platform (Native ELF vs Windows PE), dan ProtonDB tier riil.
2. **Standalone Downloader Telemetry & Real-Time Progress Invariant**: Mengimplementasikan file metadata `status.info`, kalkulasi progres dinamis, serta panel preview live streaming log (`--preview-download`).
3. **Unified CLI Download Status (`list_downloads`)**: Menyatukan pemindaian Steam ACF dan direktori proses unduhan standalone CDN ke dalam output `gamectl download-status`.
4. **Dynamic & Context-Rich Master Dashboard Preview (`preview_dashboard`)**: Merombak preview 7 modul dashboard agar menyajikan metrik sistem, storage, unduhan, dan activity logs secara dinamis.
5. **Enrich Redundant Preview Panes**: Menghilangkan tampilan tautologis di Activity Logs (`preview_log_entry`), Process HUD (`preview_process_log` dengan 7-baris konteks), dan ACF Picker (`preview_adopt_candidate` dengan status auto-discovery).
6. **Expand System Diagnostics (`doctor_audit` Layer 8)**: Menambahkan Layer 8 Security Sandboxing (`bwrap`) dan Process Isolation (`cgroups v2 systemd-run --user`) pada audit health check.
7. **Expose Game Fixes & OnlineFix Harvester in TUI**: Membuka akses katalog fix LuaTools, P2P Spacewar (AppID 480) setup, dan atomic rollback snapshot di `library_menu` (`Ctrl-X`), action palette `search_steam`, dan modal FZF interaktif (`--preview-fix`).
8. **Regression Test Suite Expansion, Rebuild & Machine Gate**: Memperluas kontrak pengujian di `tests/test_cli.sh`, mengompilasi ulang standalone bundle `bin/gamectl`, dan memvalidasi machine gate (130/130 assertions PASS).

---

## 2. Granular Technical Execution Plan (Todolist)

### [x] Chunk 1: Steam Store Search & ProtonDB Preview Engine (`--preview-search`) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `src/main.sh`, `tests/test_cli.sh`
- **DoD**: Game populer menampilkan genre, platform, dan tier ProtonDB riil tanpa kebocoran teks `-e`. Commit: `8b37ca2`.

### [x] Chunk 2: Standalone Downloader Telemetry & Real-Time Progress Invariant [VERIFIED]
- **Target Files**: `src/steam/30_downloader.sh`, `src/main.sh`, `tests/test_cli.sh`
- **DoD**: Unduhan standalone mencatat `status.info`, menghitung persentase aktual, dan menampilkan live streaming log di panel preview. Commit: `12570ba`.

### [x] Chunk 3: Unified CLI Download Status (Standalone Detection) [VERIFIED]
- **Target Files**: `src/steam/30_downloader.sh`, `tests/test_cli.sh`
- **DoD**: Perintah CLI `gamectl download-status` melaporkan unduhan standalone aktif bersama unduhan Steam client. Commit: `d470796`.

### [x] Chunk 4: Dynamic & Context-Rich Master Dashboard Preview (`preview_dashboard`) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `tests/test_cli.sh`
- **DoD**: Seluruh 7 modul di Master Dashboard menampilkan metrik sistem aktual secara dinamis. Commit: `959de51`.

### [x] Chunk 5: Enrich Redundant Preview Panes (Log Viewer, Process HUD, ACF Picker) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `src/steam/30_downloader.sh`, `tests/test_cli.sh`
- **DoD**: Eliminasi duplikasi tampilan; panel preview menyajikan data konteks dan panduan remediasi error. Commit: `394d9ca`.

### [x] Chunk 6: Expand System Diagnostics (`doctor_audit` Layer 8: Security & Isolation) [VERIFIED]
- **Target Files**: `src/diagnostics/60_doctor.sh`, `src/tui/70_dashboard.sh`, `tests/test_cli.sh`
- **DoD**: `gamectl doctor` dan cockpit dashboard mengaudit kesiapan `--sandbox` (`bwrap`) dan `--scope` (`systemd-run --user`). Commit: `7fff866`.

### [x] Chunk 7: Expose Game Fixes & OnlineFix Harvester in TUI [VERIFIED]
- **Target Files**: `src/steam/35_fixes.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `src/core/10_utils.sh`, `tests/test_cli.sh`
- **DoD**: Fitur katalog fix dan OnlineFix dapat diakses langsung dari `library_menu` (`Ctrl-X`) dan `search_steam` dengan safety snapshot restore/dry-run. Commit: `3ced56e`.

### [x] Chunk 8: Regression Test Suite Expansion, Rebuild & Machine Gate [VERIFIED]
- **Target Files**: `tests/test_cli.sh`, `bin/gamectl`, `PLAN.md`
- **DoD**: Exit code 0, 0 test regressions, total pengujian mencapai 130 assertions lulus.

---

## 3. Verification Matrix (Work Packet 24)

| Komponen | Perintah Uji | Kriteria Sukses (DoD) |
| :--- | :--- | :--- |
| **Store Search & ProtonDB** | `./bin/gamectl --preview-search 105600 "Terraria" "[INSTALLED]"` | ANSI card terformat bersih tanpa `-e`, tier ProtonDB valid. |
| **Download Telemetry** | `./bin/gamectl --preview-download 105600 "Terraria" <stage_dir>` | Parsing `status.info`, progres dinamis, live log stream. |
| **CLI Download Status** | `./bin/gamectl download-status` | Mendeteksi unduhan Standalone CDN dan Steam ACF. |
| **Dashboard Modules 1-7** | `./bin/gamectl --preview-dashboard <1..7>` | Metrik storage, store API, logs, dan diagnostics dinamis. |
| **Enriched Previews** | `./bin/gamectl --preview-log`, `--preview-process-log`, `--preview-adopt` | 7-baris context window, error remediation tips, physical detection. |
| **Layer 8 Security** | `./bin/gamectl doctor` | Audit ketersediaan Bubblewrap (`bwrap`) & cgroups v2 scope. |
| **TUI Fix Harvester** | `./bin/gamectl --preview-fix "[RESTORE]" 105600 ...` | ANSI card safety snapshot, Spacewar AppID 480 & DLL overrides. |
| **Deterministic Machine Gate** | `make lint && make test` | 130/130 test assertions lulus dengan Exit Code 0. |
