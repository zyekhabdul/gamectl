# WORK PACKET 11: GLOBAL ECOSYSTEM REMEDIATION & MULTI-DRIVE HARDENING [ACTIVE]

## 1. Objective & Technical Scope
Eliminate systemic assumptions tied to local $HOME directories, provide unified embedded wineserver resolution for Proton-only Linux gaming distributions, negotiate dual-OS (Linux/Windows) game depot downloads dynamically, guard Steam client runtime state, normalize cross-drive savegame sync paths, and introduce an ephemeral caching tier for Steam Store and ProtonDB API requests.

Scope of Work:
1. **Unified Wineserver Resolution (`src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`)**: Replace bare `wineserver` calls with dynamic path resolution from active Proton runtimes to harden DEFECT-02 across minimal distros (SteamOS, Bazzite, ChimeraOS).
2. **Dual-OS DepotDownloader Negotiation & Target Library Routing (`src/steam/30_downloader.sh`, `src/tui/70_dashboard.sh`)**: Dynamically negotiate `-os linux` vs `-os windows` based on store metadata and route downloads to libraries with maximum available capacity.
3. **Steam Runtime Guardrail (`src/steam/20_discovery.sh`, `src/steam/30_downloader.sh`)**: Warn when Steam client process is active to prevent clobbering of `shortcuts.vdf` and `appmanifest_*.acf`.
4. **Savegame Path Normalization (`src/runners/50_launcher.sh`)**: Clean directory sanitization for non-$HOME mounts (`/mnt/`, `/media/`) during remote companion synchronization.
5. **Ephemeral Store & ProtonDB Cache Tier (`src/core/10_utils.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`)**: 3600-second TTL disk cache in `$XDG_CACHE_HOME/gamectl/` for zero-stutter TUI browsing and offline resilience.
6. **Machine Verification & Regression Suite (`tests/test_cli.sh`, `./scripts/build.sh`)**: Automated assertions for cache hits, wineserver resolution, library routing, and path normalization with Exit Code 0.

---

## 2. Granular Technical Execution Plan (Work Packet 11)

### Chunk 1: Unified Wineserver Lifecycle Resolution (DEFECT-02 Hardening) [DONE]
- Target Files: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- Runtutan Eksekusi Teknis:
  1. Buat fungsi helper `get_wineserver_bin "$runner_bin"` di `src/runners/40_wrappers.sh` yang memeriksa:
     - Jika `$runner_bin` mengandung `proton`: cari executable `files/bin/wineserver`, `dist/bin/wineserver`, atau `bin/wineserver` di direktori Proton.
     - Jika tidak ada: periksa `command -v wineserver`.
     - Fallback: cari wineserver dari direktori GE-Proton lokal tertinggi.
  2. Ekspor `get_wineserver_bin` di `src/main.sh`.
  3. Perbarui `src/runners/50_launcher.sh` pada 4 titik pemanggilan wineserver (lines 68, 83, 261, 385) agar menggunakan binari wineserver yang teresolusi (`"$ws_bin" -w` dan `"$ws_bin" -k`) dan abaikan pemanggilan jika tidak ditemukan binari yang valid.
  4. Perbarui `manage_prefix` di `src/runners/40_wrappers.sh` agar menggunakan `get_wineserver_bin` secara konsisten.
- DoD: Pemanggilan flush (`-w`) dan terminate (`-k`) berjalan sukses pada environment tanpa `/usr/bin/wineserver` host.

### Chunk 2: Dual-OS DepotDownloader Negotiation & Target Library Selection [PENDING]
- Target Files: `src/steam/30_downloader.sh`, `src/tui/70_dashboard.sh`
- Runtutan Eksekusi Teknis:
  1. Tambahkan fungsi `resolve_target_library_dir "$safe_title"` di `src/steam/30_downloader.sh`:
     - Pindai custom libraries dari `~/.config/gamectl/libraries` dan fallback ke `$HOME/Games`.
     - Gunakan `df -PB 1M "$dir"` untuk memilih direktori dengan ruang bebas terbesar.
     - Kembalikan path lengkap direktori game target.
  2. Perbarui `download_game` di `src/steam/30_downloader.sh` untuk menerima flag `--os <linux|windows|all>` (default: `linux`).
  3. Ganti hardcoded `-os linux` pada DepotDownloader dengan nilai flag `--os` yang dinegosiasikan.
  4. Di `search_steam` (`src/tui/70_dashboard.sh`):
     - Evaluasi metadata `platforms.linux` dan `platforms.windows`.
     - Jika `platforms.linux == false` dan `platforms.windows == true`, tetapkan opsi download dengan `--os windows`.
     - Ganti hardcoded `$HOME/Games/$sel_name` dengan hasil `resolve_target_library_dir`.
- DoD: Game ber-platform Windows PE diunduh dengan `-os windows`, dan file masuk ke partisi library yang memiliki kapasitas memadai.

### Chunk 3: Steam Runtime Active Guardrail [PENDING]
- Target Files: `src/steam/20_discovery.sh`, `src/steam/30_downloader.sh`
- Runtutan Eksekusi Teknis:
  1. Buat helper `check_steam_active` di `src/steam/20_discovery.sh`:
     - Periksa apakah proses `steam` sedang aktif via `pgrep -x steam`.
     - Jika aktif, cetak pesan `[WARN]` informatif ke stderr bahwa Steam sedang memegang lock memori pada shortcuts dan manifest.
  2. Pasang `check_steam_active` pada:
     - `sync_steam` sebelum menulis `appmanifest_${appid}.acf`.
     - `add_steam_shortcut` sebelum membaca/menulis `shortcuts.vdf`.
- DoD: User mendapatkan notifikasi pencegahan inkonsistensi cache saat Steam client sedang berjalan tanpa crash atau aborting script.

### Chunk 4: Savegame Remote Sync Path Normalization [PENDING]
- Target Files: `src/runners/50_launcher.sh`
- Runtutan Eksekusi Teknis:
  1. Perbarui fungsi `sync_save_remote` di `src/runners/50_launcher.sh`:
     - Evaluasi path direktori game target `$gdir`.
     - Jika `$gdir` berada di dalam `$HOME`, gunakan `rel_path="${gdir#$HOME/}"`.
     - Jika `$gdir` berada di luar `$HOME` (misal `/mnt/games/Title` atau `/data/games/Title`), gunakan `rel_path="Games/$(basename "$gdir")"`.
     - Bersihkan target destination remote agar tidak menghasilkan path corrupt seperti `~//mnt/...`.
- DoD: Eksekusi rsync pada direktori game non-$HOME tersinkronisasi rapi ke host remote di direktori `~/Games/<Title>/saves/`.

### Chunk 5: Ephemeral Store & ProtonDB Cache Tier [PENDING]
- Target Files: `src/core/10_utils.sh`, `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`
- Runtutan Eksekusi Teknis:
  1. Implementasikan fungsi `fetch_cached_json "$url" "$cache_key" [ttl_seconds]` di `src/core/10_utils.sh`:
     - Lokasi cache: `${XDG_CACHE_HOME:-$HOME/.cache}/gamectl`.
     - TTL default: 3600 detik (1 jam).
     - Jika cache valid dan belum kedaluwarsa, baca langsung dari disk.
     - Jika expired atau belum ada, fetch via curl dengan timeout 2-3s, tulis atomic via `.tmp.$$`, lalu atomik `mv`.
     - Jika fetch gagal atau offline, fallback ke stale cache jika ada.
  2. Integrasikan `fetch_cached_json` ke preview pane `search_steam` di `src/tui/70_dashboard.sh` untuk metadata Steam Store dan ProtonDB summary.
  3. Integrasikan `fetch_cached_json` ke `query_protondb` di `src/diagnostics/60_doctor.sh`.
- DoD: Navigasi preview store katalog instan (<10ms) untuk item ter-cache dan tidak freeze saat offline.

### Chunk 6: Machine Verification & Automated Regression Suite [PENDING]
- Target Files: `tests/test_cli.sh`, `scripts/build.sh`, `README.md`, `DEVELOPMENT.md`
- Runtutan Eksekusi Teknis:
  1. Tambahkan 5 test assertions baru di `tests/test_cli.sh`:
     - Assertion 1: `get_wineserver_bin` mengembalikan path executable Proton wineserver.
     - Assertion 2: `download_game` menerima dan meneruskan parameter `--os windows` dan `--os linux`.
     - Assertion 3: `resolve_target_library_dir` merutekan folder ke library berkapasitas terbesar.
     - Assertion 4: `sync_save_remote` menormalisasi path non-$HOME dengan benar.
     - Assertion 5: `fetch_cached_json` membaca cache lokal pada pemanggilan kedua dalam jendela TTL.
  2. Jalankan `./scripts/build.sh` dan `./scripts/build.sh --check`.
  3. Jalankan regression suite `./tests/test_cli.sh` dan pastikan seluruh test assertions (49/49) lulus dengan Exit Code 0.
- DoD: Seluruh rangkaian tes deterministik lulus 100% tanpa regresi.

---

## 3. Matriks Milestone Selesai (Work Packet 10.5 & History)
- [x] WP 10.5 Chunk 1: TUI Modal Action Palette & Query Input Refactor (`07501fd`) [DONE]
- [x] WP 10.5 Chunk 2: Entitlement Engine Nomenclature & ACF Semantics Overhaul (`efce9fd`) [DONE]
- [x] WP 10.5 Chunk 3: Catalog Direct Action Shortcuts & Ergonomic Hotkeys (`4412c5f`) [DONE]
- [x] WP 10.5 Chunk 4: Machine Verification & Automated Regression Suite (`c2fb6b7`) [DONE]
- [x] Checkpoint Verifikasi: 44/44 tests passing with Exit 0. [DONE]
