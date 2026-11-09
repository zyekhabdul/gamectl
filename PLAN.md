# WORK PACKET 19: IN-DASHBOARD RUNTIME LOGS & OUTSIDE FLICKER ELIMINATION

**Track**: Maintenance / Ergonomics & Reliability  
**Status**: PENDING APPROVAL  
**Branch**: `main`  
**Max Chunks**: 8 Chunks (Active Packet <= 10)

---

## 1. Objective & Technical Scope
Menuntaskan technical debt pada subsistem logging dan ergonomi visual TUI gamectl:
1. **SSoT Runtime Logger & Active Cockpit**: Memastikan log aktivitas runtime (`gamectl.log`) terhubung secara deterministik ke Master Dashboard Cockpit, tidak lagi kosong (`(No recent activity logged yet)`), serta dapat diakses instan via hotkey `<Ctrl-L>` tanpa kegagalan nested subshell.
2. **Eliminasi Screen Flickering di Luar Dashboard**: Mengeliminasi seluruh transisi berkedip (*screen flicker*), jeda `read -p`, pemanggilan `clear`, dan pembajakan navigasi `standalone=true` pada menu-menu di luar dashboard (`library_menu`, `search_steam`, `list_downloads_interactive`, `game_controller_hud`, `manage_prefix`).

---

## 2. Granular Technical Execution Plan (Max 10 Chunks)

### Chunk 1: Centralized Log Path SSoT (`get_runtime_log_file`) & Cockpit Event Hook [VERIFIED]
- **Target Files**: `src/core/10_utils.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Implementasikan fungsi kanonikal `get_runtime_log_file()` di `src/core/10_utils.sh` yang menjamin path absolut `${XDG_RUNTIME_DIR:-/tmp/gamectl-$(id -u 2>/dev/null || echo 1000)}/gamectl.log`.
  2. Refactor `log_msg()` untuk menggunakan `get_runtime_log_file()`.
  3. Export `get_runtime_log_file` pada `src/main.sh`.
  4. Perbarui `preview_dashboard()` dan `view_logs_interactive()` di `src/tui/70_dashboard.sh` agar membaca file secara seragam via `get_runtime_log_file()`.
  5. Tambahkan logging inisialisasi sesi saat dashboard dibuka: `log_msg "INFO" "DASHBOARD" "Cockpit active ($game_count titles indexed)"`.
  6. Perlebar truncation limit baris preview log di `preview_dashboard()` dari 68 karakter ke 90 karakter dengan formatting badge yang rapi.
- **DoD**:
  - `get_runtime_log_file` menghasilkan path valid di bash maupun `/bin/sh`.
  - Membuka dashboard langsung mencatat log event yang terlihat di kartu preview kanan.

### Chunk 2: Native In-Process Log Viewer (`--expect=ctrl-l`) & Buffer Preservation [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `dashboard_menu()`, ubah `--bind="ctrl-l:execute($SELF_BIN logs)"` menjadi `--expect=ctrl-l`.
  2. Tangani trigger `ctrl-l` di loop utama bash:
     ```bash
     if [ "$trigger_key" = "ctrl-l" ]; then
         view_logs_interactive
         continue
     fi
     ```
  3. Jalankan `view_logs_interactive` langsung pada proses aktif tanpa memicu subshell `$SELF_BIN logs` dan tanpa memanggil `exit_tui_screen` (`tput rmcup`).
- **DoD**:
  - Menekan `<Ctrl-L>` di dashboard membuka log viewer seketika tanpa jeda subshell dan tanpa merusak alternate screen buffer.
  - Menekan `Esc` di log viewer kembali ke dashboard dengan tampilan 100% utuh tanpa glitch.

### Chunk 3: Zero-Flicker Native Hotkey Dispatch di `library_menu` [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `library_menu()`, hapus seluruh binding `execute(...)` yang mengandung `bash -c 'read -n 1 ...'`:
     - Hapus `ctrl-i:execute(...)`
     - Hapus `ctrl-s:execute(...)`
     - Hapus `ctrl-b:execute(...)`
     - Hapus `ctrl-l:execute($SELF_BIN logs)`
  2. Tambahkan parameter `--expect=ctrl-i,ctrl-s,ctrl-b,ctrl-l,ctrl-o,ctrl-p,ctrl-f,ctrl-d` pada pemanggilan FZF di `library_menu()`.
  3. Di loop bash `library_menu()`, tangani masing-masing hotkey:
     - `ctrl-l`: Panggil `view_logs_interactive` secara in-process.
     - `ctrl-i`: Jalankan `inject_game` + `sync_steam`, tampilkan notifikasi via `tui_modal_notice`.
     - `ctrl-s`: Jalankan `sync_save_remote`, tampilkan notifikasi via `tui_modal_notice`.
     - `ctrl-b`: Jalankan `backup_save`, tampilkan notifikasi via `tui_modal_notice`.
     - `ctrl-o`: Panggil `configure_wrappers "$sel_dir" "$sel_title"`.
     - `ctrl-p`: Panggil `set_id_interactive "$sel_dir" "$sel_title"`.
     - `ctrl-f`: Panggil `search_steam "" false`.
     - `ctrl-d`: Panggil `list_downloads_interactive`.
- **DoD**:
  - Zero pemanggilan `read -p` atau pesan mentah ke stdout di dalam library menu.
  - Transisi aksi berlangsung mulus di dalam FZF tanpa layar berkedip hitam.

### Chunk 4: Eliminasi Raw Terminal Output di `list_downloads_interactive` [VERIFIED]
- **Target Files**: `src/steam/30_downloader.sh`
- **Runtutan Eksekusi Teknis**:
  1. Ganti `--bind="ctrl-k:execute(... read ...)"` dengan `--expect=ctrl-k`.
  2. Tangani aksi pause langsung di loop bash dan konfirmasi melalui `tui_modal_notice`.
  3. Pastikan `list_downloads_interactive` mengelola `enter_tui_screen` dan `exit_tui_screen` saat dipanggil secara mandiri dari terminal shell.
- **DoD**:
  - Menekan `<Ctrl-K>` pada monitor unduhan tidak memuntahkan teks bash mentah ke layar.

### Chunk 5: Pemisahan Navigasi Mandiri Shell (Eliminasi Perangkap `standalone=true`) [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pada `library_menu()`, hapus blok:
     ```bash
     if [ "$standalone" = "true" ]; then
         dashboard_menu
     fi
     ```
     Ganti dengan `[ "$standalone" = "true" ] && exit_tui_screen` sebelum `return 0`.
  2. Pada `search_steam()`, hapus pengalihan paksa `dashboard_menu` saat `standalone="true"`.
     Menekan `Esc` pada pencarian standalone harus keluar bersih ke shell terminal via `exit_tui_screen`.
- **DoD**:
  - `gamectl library` keluar langsung ke terminal shell saat ditekan `Esc`.
  - `gamectl search` keluar langsung ke terminal shell saat ditekan `Esc`.
  - Zero pengalihan paksa ke dashboard jika user memulai dari shell spesifik.

### Chunk 6: Modernisasi `game_controller_hud` Menjadi In-Dashboard FZF Modal [VERIFIED]
- **Target Files**: `src/runners/50_launcher.sh`
- **Runtutan Eksekusi Teknis**:
  1. Hapus pemanggilan `clear` di baris 17 & 46 serta loop `read -t 30 -r -p` di `game_controller_hud()`.
  2. Konversikan HUD controller menjadi dialog FZF modal terstruktur dengan live preview status proses (Running/Exited, PID, Log path, runtime type).
  3. Sediakan pilihan aksi: Kembali ke Library, Kembali ke Dashboard, Live Log Viewer, Graceful Stop, Force Kill.
- **DoD**:
  - Peluncuran game tidak pernah memanggil `clear` dan bebas dari prompt bash kuno.

### Chunk 7: Modernisasi `manage_prefix` Menjadi In-Dashboard FZF Modal
- **Target Files**: `src/runners/40_wrappers.sh`
- **Runtutan Eksekusi Teknis**:
  1. Hapus pemanggilan `clear` di baris 583 dan `read -t 15 -r -p` di baris 599 pada `manage_prefix()`.
  2. Ubah menu interaktif Wine Prefix Swiss Army Knife menjadi FZF palette murni dengan deskripsi modular untuk tiap tool (winecfg, regedit, cmd, shell, winetricks, kill, clean).
- **DoD**:
  - `gamectl pfx <dir>` interaktif berjalan 100% di dalam FZF tanpa mengosongkan layar terminal.

### Chunk 8: Suite Pengujian Regresi & Validasi Bundle
- **Target Files**: `tests/test_cli.sh`, `scripts/build.sh`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan test assertions pada `tests/test_cli.sh`:
     - Validasi SSOT `get_runtime_log_file`.
     - Validasi `dashboard_menu` mencatat event aktif saat dibuka.
     - Validasi ketiadaan `read -p` dan `execute` berkedip pada `library_menu` & `list_downloads_interactive`.
     - Validasi exit contract mandiri pada `library_menu standalone` dan `search_steam standalone`.
     - Validasi zero `clear` pada `game_controller_hud` dan `manage_prefix`.
  2. Kompilasi bundle mandiri via `./scripts/build.sh`.
  3. Verifikasi integritas: `./scripts/build.sh --check` dan `./tests/test_cli.sh`.
- **DoD**:
  - Seluruh assertion baru lulus (Exit code 0).
  - Total assertions > 106, 0 failed.
  - Standalone binary `bin/gamectl` tersinkronisasi 100%.

---

## 3. Verification Matrix

| Komponen | Perintah Uji | Kriteria Sukses (DoD) |
| :--- | :--- | :--- |
| **SSoT Log File** | `gamectl` lalu inspect log | File log terisi event dashboard dan terbaca di preview. |
| **Hotkey Logs** | Tekan `<Ctrl-L>` di Dashboard & Library | Log viewer terbuka mulus, buffer tidak rusak saat kembali. |
| **Library Shortcuts** | Tekan `<Ctrl-I>`, `<Ctrl-S>`, `<Ctrl-B>` | Modal FZF muncul instan tanpa flash teks mentah terminal. |
| **Standalone Exit** | `gamectl library` -> Tekan `Esc` | Kembali bersih ke shell terminal, tidak redirect ke dashboard. |
| **Zero Raw Clear** | `grep -rn "clear" src/` | Zero `clear` di alur runtime interactive menus. |
| **Regression Suite** | `./tests/test_cli.sh` | Seluruh test suite lulus dengan Exit Code 0. |
