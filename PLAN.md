# WORK PACKET 18: CLEAN TUI LIFECYCLE, CENTRALIZED LOGS & DANGLING FEATURE REMEDIATION [PLANNED]

**Track**: Spec-Driven Engineering (SDD) / Maintenance

## 1. Objective & Technical Scope
Mewujudkan ergonomi TUI berstandar modern ("Clean Outside", 100% In-Dashboard) serta membersihkan technical debt fitur menggantung:
1. **Terminal Screen Discipline ("Clean Outside")**: Mengisolasi sesi interaktif `gamectl` di dalam POSIX Alternate Screen Buffer (`tput smcup`/`rmcup`) dengan signal trap (`EXIT`, `INT`, `TERM`) sehingga riwayat shell terminal 100% bersih saat user keluar dari TUI.
2. **In-Dashboard Centralized Logging Subsystem**: Mengalihkan dan mencatat log operasional ke `${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}/gamectl.log` (maksimal 1.000 baris terbaru) dengan viewer terintegrasi di Dashboard (Menu [07] dan snippet preview panel).
3. **In-Dashboard FZF Modals**: Mengeliminasi seluruh prompt bash kuno (`clear` + `read -r -p`) pada `configure_global`, `configure_wrappers`, `set_id_interactive`, dan `doctor_audit` menjadi dialog modal FZF murni di dalam dashboard.
4. **Remediasi Fitur Menggantung & Ghost ACF**: Mengeliminasi pembuatan file dummy `appmanifest_<appid>.acf` kosong yang menghasilkan "Ghost Game" di Steam dan scanner lokal, serta memperluas monitor unduhan untuk melacak engine native `gamectl-depot-dl`.

---

## 2. Granular Technical Execution Plan (Max 10 Chunks)

### Chunk 1: Terminal Screen Lifecycle Engine (`enter_tui_screen` / `exit_tui_screen`) [VERIFIED]
- **Target Files**: `src/core/10_utils.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Implementasikan utilitas `enter_tui_screen()` dan `exit_tui_screen()` di `src/core/10_utils.sh` menggunakan `[ -t 1 ] && tput smcup` dan `tput rmcup`.
  2. Pasang sinyal trap: `trap 'trap - EXIT INT TERM; exit_tui_screen; exit' EXIT INT TERM`.
  3. Panggil `enter_tui_screen` saat memasuki `dashboard_menu()`, `library_menu()`, dan `search_steam()`.
  4. Panggil `exit_tui_screen` saat `dashboard_menu()` selesai.
- **DoD**: Menekan Esc di Dashboard keluar ke shell dengan terminal 100% bersih tanpa sisa teks atau log. (Terverifikasi empiris via tmux).

### Chunk 2: In-Dashboard Centralized Logger (`log_msg`) di Runtime Dir
- **Target Files**: `src/core/10_utils.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Buat utilitas `log_msg(level, component, message)` di `src/core/10_utils.sh`.
  2. Arahkan penulisan ke `${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}/gamectl.log`.
  3. Terapkan rolling buffer cap: jika ukuran melebihi 100KB, pangkas menjadi 1.000 baris terbaru via `tail -n 1000`.
  4. Hook panggilan `log_msg` pada aksi kunci: injeksi GBE, download manifest/depot, snapshot savegame, dan aktivasi launcher.
- **DoD**: File `gamectl.log` terbentuk secara terisolasi, aman per-user, dan mencatat histori aktivitas secara konsisten.

### Chunk 3: In-Dashboard Activity & Runtime Log Viewer
- **Target Files**: `src/tui/70_dashboard.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan menu `7) [07] ACTIVITY & RUNTIME LOGS` pada `dashboard_menu()`.
  2. Implementasikan viewer interaktif `view_logs_interactive()` berbasis FZF dengan preview timestamp, level badge, dan komponen.
  3. Tambahkan hotkey `<Ctrl-L>` di `dashboard_menu` dan `library_menu` untuk membuka log viewer instan.
  4. Tambahkan kartu informasi "Recent Activity Logs" (5 baris terbaru) pada preview cockpit kanan di `preview_dashboard()`.
- **DoD**: User dapat memeriksa riwayat aktivitas dan error langsung dari dalam TUI tanpa perlu keluar ke terminal.

### Chunk 4: Modernisasi `configure_global` Menjadi In-Dashboard FZF Modal
- **Target Files**: `src/runners/40_wrappers.sh`
- **Runtutan Eksekusi Teknis**:
  1. Hapus pemanggilan `clear` dan loop `read -r -p "Select option [1-5]: "` pada `configure_global()`.
  2. Bangun modal dialog berbasis FZF menu palette (`--height=45%`, `--border-rounded`).
  3. Konfigurasi persona (Nama & SteamID) dialihkan ke prompt modal FZF `--print-query`.
  4. Pilihan toggle wrappers langsung membuka modal wrapper FZF tanpa keluar dashboard.
- **DoD**: `configure_global` berjalan 100% di dalam antarmuka FZF tanpa melempar user ke terminal mentah.

### Chunk 5: Modernisasi `configure_wrappers` Menjadi In-Dashboard FZF Toggle Palette
- **Target Files**: `src/runners/40_wrappers.sh`
- **Runtutan Eksekusi Teknis**:
  1. Hapus `clear` dan `read -r -p "Select option [0-9]: "` pada `configure_wrappers()`.
  2. Tampilkan wrapper items dengan badge status `[ACTIVE]` dan `[OFF]` di list FZF.
  3. Menekan `Enter` langsung mengubah status flag (toggle) dan me-reload list secara instan.
  4. Menekan `Esc` menyimpan file `.wrappers` dan kembali ke Library menu.
  5. Pertahankan token literal `0|q|Q|cancel)` dan `continue` pada blok evaluasi untuk memuaskan invariant `test_fzf_menu_loop_break_invariants`.
- **DoD**: Konfigurasi wrappers game/global berjalan interaktif dan reaktif di dalam FZF modal.

### Chunk 6: Modernisasi `set_id_interactive` Menjadi In-Dashboard FZF Query Prompts
- **Target Files**: `src/steam/25_identity.sh`
- **Runtutan Eksekusi Teknis**:
  1. Ganti prompt baris perintah `read -r in_name`, `read -r in_id`, dan `read -r in_bc` dengan dialog modal input berbasis FZF (`: | fzf --print-query`).
  2. Pertahankan fallback nilai default yang sudah terpasang.
  3. Berikan opsi toggle penyimpanan global via modal konfirmasi FZF.
- **DoD**: Pengaturan LAN persona dan SteamID64 selesai seluruhnya di dalam dialog modal FZF.

### Chunk 7: Modernisasi Eksekusi `doctor_audit` di Dashboard
- **Target Files**: `src/tui/70_dashboard.sh`, `src/diagnostics/60_doctor.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pada menu `[06] SYSTEM DIAGNOSTICS` di `dashboard_menu`, alihkan eksekusi `doctor_audit` ke viewer scrollable FZF atau pager internal (`less -R`).
  2. Hilangkan jeda `read -r -p "Press [ENTER] to return to Dashboard..."` pada konteks TUI.
  3. Pertahankan output stdout normal ketika `doctor_audit` dipanggil dari CLI non-interaktif (`gamectl doctor`).
- **DoD**: Hasil diagnosa sistem dapat di-scroll dan dibaca di dalam dashboard, lalu kembali ke menu utama dengan menekan `Esc` / `q`.

### Chunk 8: Remediasi Ghost ACF & Validasi Entitlement
- **Target Files**: `src/steam/30_downloader.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pada `sync_steam()`, validasi keberadaan direktori game fisik: jika `$game_dir` kosong atau tidak memiliki file binary executable, tolak pendaftaran file dummy `appmanifest_${appid}.acf`.
  2. Pada `unlock_game()` / `unlock_interactive()`, tampilkan pesan panduan bahwa adopsi ACF hanya berlaku untuk game yang filenya telah terpasang di storage lokal.
  3. Pertahankan banner teks literal yang diuji pada `test_cli.sh` (`STEAM ENTITLEMENT & ACF ADOPTION ENGINE` dan `entitled in Steam Client with Full DLC & ACF manifest`) untuk mempertahankan kompatibilitas uji regresi.
- **DoD**: Tidak ada lagi pembuatan "Ghost Game" kosong di Steam maupun library `gamectl`.

### Chunk 9: Perluasan `list_downloads_interactive` untuk Sovereign Standalone Downloads
- **Target Files**: `src/steam/30_downloader.sh`
- **Runtutan Eksekusi Teknis**:
  1. Perluas pembacaan unduhan aktif di `list_downloads_interactive()` untuk memindai log dan PID `depot_dl_*` di `${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}`.
  2. Integrasikan item unduhan native `gamectl-depot-dl` ke dalam daftar FZF berdampingan dengan unduhan ACF Steam Client.
  3. Ganti pesan terminal `clear` + `read -r -p` saat daftar kosong dengan empty-state item di dalam FZF: `[EMPTY] No active downloads found. Press Esc to return.`
- **DoD**: Seluruh unduhan (baik Steam Client maupun Standalone CDN) terpantau di dalam Download Manager tanpa keluar ke terminal.

### Chunk 10: Regression Harness & Empirical Machine Verification
- **Target Files**: `tests/test_cli.sh`, `bin/gamectl`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan test assertion baru di `tests/test_cli.sh` untuk memverifikasi kontrak `enter_tui_screen`/`exit_tui_screen`, kontrak logging `log_msg`, dan validasi ghost ACF guard.
  2. Jalankan `./scripts/build.sh` untuk mengompilasi ulang biner mandiri `bin/gamectl`.
  3. Jalankan `./scripts/build.sh --check` untuk memverifikasi sinkronisasi source modular dengan bundle.
  4. Jalankan full suite `./tests/test_cli.sh` dan pastikan seluruh pengujian menghasilkan `Exit Code 0` (0 failures).
- **DoD**: Seluruh 100+ kontrak regresi lulus tanpa kompromi; binary bundle sinkron.

---

## 3. Matriks Milestone (Work Packet 18)
- [x] Chunk 1: Terminal Screen Lifecycle Engine (`enter_tui_screen` / `exit_tui_screen`) [VERIFIED]
- [ ] Chunk 2: In-Dashboard Centralized Logger (`log_msg`) di Runtime Dir
- [ ] Chunk 3: In-Dashboard Activity & Runtime Log Viewer
- [ ] Chunk 4: Modernisasi `configure_global` Menjadi In-Dashboard FZF Modal
- [ ] Chunk 5: Modernisasi `configure_wrappers` Menjadi In-Dashboard FZF Toggle Palette
- [ ] Chunk 6: Modernisasi `set_id_interactive` Menjadi In-Dashboard FZF Query Prompts
- [ ] Chunk 7: Modernisasi Eksekusi `doctor_audit` di Dashboard
- [ ] Chunk 8: Remediasi Ghost ACF & Validasi Entitlement
- [ ] Chunk 9: Perluasan `list_downloads_interactive` untuk Sovereign Standalone Downloads
- [ ] Chunk 10: Regression Harness & Empirical Machine Verification
