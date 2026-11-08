# WORK PACKET 17: REAL-TIME REACTIVE TAGS & DYNAMIC STATE SYNCHRONIZATION [COMPLETE]

**Track**: Maintenance

## 1. Objective & Technical Scope
Mengeliminasi latensi dan keharusan me-restart `gamectl` untuk melihat perubahan status/tag game (`[INSTALLED]`, `[GBE_FORK]`, `[VALVE_DLL]`, `[VALVE_SO]`, `[STANDALONE]`):
1. **Fungsi Global `invalidate_scan_cache()`**: Utilitas atomik untuk membersihkan `scancache.tab` yang dipanggil pada setiap mutasi filesystem (injeksi GBE, unduhan, unlock/entitlement, auto-injeksi launcher).
2. **Perbaikan Reload FZF di `library_menu()`**: Mendukung flag `--refresh` / `-r` pada `list-formatted` dan memasang `reload($SELF_BIN list-formatted --refresh)` pada binding FZF.
3. **Dynamic Live Inspection di `preview_game()`**: Mengaudit status biner Steamworks langsung dari `$gdir` secara lightweight (<1ms) saat preview dirender, tanpa mengandalkan kolom string statis/cache.
4. **Re-evaluasi `$results` di `search_steam()`**: Menyegarkan status lokal di dalam loop pencarian setelah aksi `<Ctrl-A>`, `<Ctrl-S>`, atau `<Ctrl-U>` dieksekusi agar tag `[INSTALLED]` berubah seketika.

---

## 2. Granular Technical Execution Plan (Work Packet 17)

### Chunk 1: Implementasi `invalidate_scan_cache()` & Hook Titik Mutasi [VERIFIED]
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/steam/30_downloader.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Definisikan `invalidate_scan_cache()` di `src/core/10_utils.sh` untuk menghapus `${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}/scancache.tab*`.
  2. Ekspor `invalidate_scan_cache` di `src/main.sh`.
  3. Panggil `invalidate_scan_cache` di:
     - `inject_game` (`src/runners/50_launcher.sh`)
     - `launch_game` pasca auto-injeksi GBE (`src/runners/50_launcher.sh`)
     - `download_game` pasca download selesai (`src/steam/30_downloader.sh`)
     - `sync_steam` dan `unlock_game` (`src/steam/30_downloader.sh`)
     - `install_game_fix` dan `revert_game_fix` (`src/steam/35_fixes.sh`)
- **DoD**: File cache terhapus secara atomik setiap kali terjadi modifikasi status atau file game.

### Chunk 2: Hardening FZF Reload Binding & Dukungan `--refresh` pada CLI `list-formatted` [VERIFIED]
- **Target Files**: `src/main.sh`, `src/tui/70_dashboard.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pastikan subcommand `list-formatted` di `src/main.sh` meneruskan flag argumen (`--refresh` / `-r`) ke `scan_installed_games --formatted "$@"`.
  2. Pada `src/tui/70_dashboard.sh` (`library_menu`), perbarui seluruh binding reload FZF (`ctrl-i`, `ctrl-o`, `ctrl-p`, `ctrl-f`, `ctrl-d`) agar memanggil `$SELF_BIN list-formatted --refresh`.
  3. Bersihkan cache (`invalidate_scan_cache`) saat kembali dari eksekusi `launch_game` di dalam loop `library_menu`.
- **DoD**: Penekanan `<Ctrl-I>` atau kembali dari peluncuran game langsung memicu pembacaan segar dan tag di list FZF berubah seketika tanpa exit.

### Chunk 3: Dynamic Live Inspection pada Preview Pane (`preview_game`) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pada `preview_game()`, jika `$gdir` valid, lakukan probe dinamis ke direktori target:
     - Cari biner `steam_api64.dll`, `steam_api.dll`, `libsteam_api.so`.
     - Hitung ukuran file (`stat -c%s`): jika >7MB maka `GBE_FORK`, jika <=7MB maka `VALVE_DLL` / `VALVE_SO`.
     - Jika tidak ditemukan library Steamworks, status adalah `STANDALONE`.
  2. Gunakan status live terverifikasi ini untuk menampilkan badge status dan deskripsi preview.
- **DoD**: Preview pane menampilkan status real-time akurat dari storage bahkan sebelum cache kiri ter-refresh.

### Chunk 4: Re-evaluasi `$results` Dinamis di `search_steam` & Regression Harness [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Ekstrak logika pembentukan list `$results` di `search_steam` menjadi fungsi internal helper `_refresh_search_results` dan panggil dalam loop setelah aksi dieksekusi.
  2. Tambahkan test assertion baru di `tests/test_cli.sh` untuk memverifikasi kontrak real-time cache invalidation, `--refresh` list-formatted, dan live inspection.
  3. Rebuild bundle dan verifikasi 100% test assertions pass dengan Exit Code 0 (98/98 passed).
- **DoD**: Tag `[INSTALLED]` pada hasil pencarian berubah real-time setelah diunduh/di-unlock, seluruh suite pengujian lulus.

---

## 3. Matriks Milestone (Work Packet 17)
- [x] Chunk 1: Implementasi `invalidate_scan_cache()` & Hook Titik Mutasi [VERIFIED]
- [x] Chunk 2: Hardening FZF Reload Binding & Dukungan `--refresh` pada CLI `list-formatted` [VERIFIED]
- [x] Chunk 3: Dynamic Live Inspection pada Preview Pane (`preview_game`) [VERIFIED]
- [x] Chunk 4: Re-evaluasi `$results` Dinamis di `search_steam` & Regression Harness [VERIFIED]
