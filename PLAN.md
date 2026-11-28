# WORK PACKET 43: STRATEGI 4-PILAR (AUTO-PRUNE TUI, GOG IMPORT, LAN-SHARE & EPIC SCREAMAPI)

- **Track**: Maintenance / Sovereign 4-Pillar Strategy
- **Status**: IN PROGRESS [2/4 PACKETS]
- **Prasyarat**: WP42 (`05_cli_help.sh`, `21_gog_installer.sh`, `54_lan_mesh.sh`, `crates/gamectl-core/`) — terverifikasi `make test` & `STRICT_LINT=1 make lint` (Exit 0).
- **Riwayat Selesai**: WP33..WP41 (`597b73f`), WP42 (Pemangkasan LOC `src/main.sh` via `src/core/05_cli_help.sh`, GOG Offline Extractor `src/stores/21_gog_installer.sh`, P2P LAN Mesh `src/runners/54_lan_mesh.sh`, dan MIT Rust Epic Core `crates/gamectl-core/`).
- **Basis**: `docs/SOVEREIGN_ORIGINAL_PURPOSE.md` dan Strategi 4-Pilar Peluang `gamectl` (Steam Utama, Epic Giveaway, GOG DRM-Free, LAN Mesh Jaring Pengaman).
- **Target Files**: `src/tui/72_store_tui.sh`, `src/tui/70_dashboard.sh`, `src/stores/21_gog_installer.sh`, `src/runners/54_lan_mesh.sh`, `src/stores/31_epic_screamapi.sh`, `src/stores/30_store_epic.sh`, `src/stores/00_store_interface.sh`, `src/runners/41_proton_prefix.sh`, `src/core/05_cli_help.sh`, `src/main.sh`, `scripts/build.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`, `DEVELOPMENT.md`, `bin/gamectl`

---

## 1. Tujuan & Pilihan Model Arsitektur

1. **Dynamic Auto-Prune Multi-Store (Model *Installed-or-Authenticated*)**:
   - Menghilangkan store kosong dari siklus `Tab` dan picker `Alt-S` di Library TUI.
   - Aturan visibilitas tab:
     - `ALL`: selalu tampil.
     - `STEAM`: tampil jika ada game `STEAM` terpasang atau direktori Steam library ditemukan.
     - `GOG`: tampil jika ada game `GOG` terpasang atau CLI `gogdl`/`lgogdownloader` memiliki sesi aktif.
     - `EPIC`: tampil jika ada game `EPIC` terpasang atau (`store_epic_available` **dan** `_epic_auth_session_present`), sehingga keberadaan `bin/gamectl-core` tidak memunculkan tab kosong saat belum login.
     - `AMAZON`: tampil jika ada game `AMAZON` terpasang atau (`store_amazon_available` **dan** `user.json` ada).
     - `STANDALONE`: tampil jika ada game `STANDALONE` (atau fallback saat library kosong).
2. **GOG Offline Importer (`gamectl import`)**:
   - Menjadikan [21_gog_installer.sh](file:///home/aomiqaza/Projects/gamectl/src/stores/21_gog_installer.sh) sebagai Single Source of Truth dengan alias CLI `gamectl import <setup.exe|installer.sh>` dan inisialisasi direktori `saves/`.
3. **LAN Mesh `lan-share` (Model A: *Encrypted SSH/rsync Push*)**:
   - Simetris dengan `lan-pull` ([54_lan_mesh.sh](file:///home/aomiqaza/Projects/gamectl/src/runners/54_lan_mesh.sh)): mendorong game terinstal atau manifest ke peer companion (`~/.config/gamectl/peers`) lewat SSH/`rsync` tanpa membuka port HTTP atau daemon tambahan.
4. **Epic ScreamAPI DLC Unlocker (Model *Opt-In Provisioner + Anti-Cheat Hard-Stop*)**:
   - Meniru pola [19_gbe_templates.sh](file:///home/aomiqaza/Projects/gamectl/src/core/19_gbe_templates.sh) dan [52_inject_runtime.sh](file:///home/aomiqaza/Projects/gamectl/src/runners/52_inject_runtime.sh): injeksi eksplisit (`gamectl epic screamapi`), deteksi keras Anti-Cheat (`EasyAntiCheat`/`BattlEye`/`EOSAntiCheat`) untuk melindungi akun, backup `EOSSDK-*.dll.orig_gamectl`, dan dukungan `--revert`.

---

## 2. Rencana Eksekusi Detail (Packet 43A - 43D)

### [x] Packet 43A: Dynamic Auto-Prune Multi-Store (`Tab` & `Alt-S`)
- **Target Files**: `src/tui/72_store_tui.sh`, `src/tui/70_dashboard.sh`, `tests/test_remediation.sh`
- **Langkah Teknis**:
  1. Tambahkan `get_visible_store_filters()`, `get_next_visible_store_filter()`, `build_visible_store_palette()`, dan `validate_visible_store_filter()` di `src/tui/72_store_tui.sh` dengan model *Installed-or-Authenticated*.
  2. Perbarui siklus `tab)` dan picker `alt-s)` di `src/tui/70_dashboard.sh` (disertai `_store_filter_label_row()`).
  3. Tambahkan Test 46 di `tests/test_remediation.sh` dan perbarui fixture 6-store pada Test 32.
- **Definition of Done (DoD)**:
  - `Tab` dan `Alt-S` hanya menampilkan store yang relevan; `STRICT_LINT=1 make lint`, `build.sh --check`, dan seluruh test lulus Exit 0.

### [x] Packet 43B: GOG Importer Ergonomics (`gamectl import`)
- **Target Files**: `src/stores/21_gog_installer.sh`, `src/core/05_cli_help.sh`, `src/main.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`
- **Langkah Teknis**:
  1. Pastikan `install_gog_offline` menginisialisasi direktori `saves/` (`mkdir -p "$target_dir" "$target_dir/saves"`) untuk portabilitas snapshot.
  2. Daftarkan alias CLI `import|gog-import` di `src/main.sh`, dokumentasikan di `src/core/05_cli_help.sh`, dan tambahkan completion di `completions/gamectl.bash`.
  3. Perbarui Test 43 di `tests/test_remediation.sh` untuk memverifikasi `gamectl import` dan keberadaan `$target_dir/saves`.
- **Definition of Done (DoD)**:
  - `gamectl import <setup.exe|installer.sh>` mengekstrak, menyiapkan prefix/saves, dan mendaftarkan game dengan badge `[GOG]`.

### [ ] Packet 43C: P2P LAN Mesh `gamectl lan-share`
- **Target Files**: `src/runners/54_lan_mesh.sh`, `src/core/05_cli_help.sh`, `src/main.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`
- **Langkah Teknis**:
  1. Implementasikan `lan_share <appid|title|dir> [peer] [--manifest-only] [--target <remote_dir>] [--dry-run]` di `src/runners/54_lan_mesh.sh`:
     - Validasi peer via `_lan_validate_peer`, tolak target lokal jika game aktif (`is_game_active_for_dir`), kirim via `rsync -s -e ... -avzP` (mengecualikan `pfx/` dan `.save_snapshots/`).
     - Untuk `--manifest-only`, kirim arsip manifest/lua ke `~/.cache/gamectl/` atau `stplug-in/` pada peer tujuan.
  2. Wire `lan-share|mesh-share` ke `src/main.sh`, `src/core/05_cli_help.sh`, dan `completions/gamectl.bash`.
  3. Perluas Test 44 di `tests/test_remediation.sh` dengan uji `lan-share` dan `lan-share --manifest-only` (mock `ssh`/`rsync`).
- **Definition of Done (DoD)**:
  - `gamectl lan-share` mendukung dry-run, transfer game penuh, dan transfer manifest ke peer LAN dengan sanitasi path penuh.

### [ ] Packet 43D: Epic ScreamAPI DLC Unlocker (`src/stores/31_epic_screamapi.sh`)
- **Target Files**: `src/stores/31_epic_screamapi.sh`, `src/stores/30_store_epic.sh`, `src/stores/00_store_interface.sh`, `src/runners/41_proton_prefix.sh`, `src/core/05_cli_help.sh`, `src/main.sh`, `scripts/build.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`
- **Langkah Teknis**:
  1. Buat `src/stores/31_epic_screamapi.sh` (<= 300 LOC):
     - `setup_screamapi_templates`: unduh/staging template ke `~/.local/share/gamectl/screamapi/` dengan audit zip-slip & SHA-256 (override via `GAMECTL_SCREAMAPI_DIR`).
     - `_epic_detect_anticheat <game_dir>`: deteksi `EasyAntiCheat`, `BattlEye`, atau `EOSAntiCheat` untuk hard-stop default (override hanya dengan `--force`).
     - `epic_screamapi_inject <game_dir> [--revert] [--dry-run] [--force]`: backup `EOSSDK-Win*-Shipping.dll` ke `*.orig_gamectl`, pasang proxy DLL + `ScreamAPI.json`, dan dukung `--revert` atomik.
  2. Tambahkan `WINEDLLOVERRIDES` saat `ScreamAPI.json` / proxy aktif di `detect_dll_overrides()` (`src/runners/41_proton_prefix.sh`).
  3. Wire `gamectl setup-screamapi` dan `gamectl epic screamapi`, daftarkan di `scripts/build.sh` & `DEVELOPMENT.md`, lalu tambahkan contract test di `tests/test_remediation.sh`.
- **Definition of Done (DoD)**:
  - ScreamAPI hanya berjalan secara opt-in, menolak game ber-Anti-Cheat secara default, dan dapat di-revert bersih ke DLL asli.
