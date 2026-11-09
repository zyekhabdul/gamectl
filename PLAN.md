# WORK PACKET 22: COMPLETION OF HALF-DONE ARCHITECTURE & SOVEREIGN CAPABILITIES

**Track**: Feature Completion & Runtime Hardening  
**Status**: IN PROGRESS  
**Branch**: `main`  
**Max Chunks**: 6 Chunks (Active Packet <= 10)  
**Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/runners/40_wrappers.sh`, `src/steam/35_fixes.sh`, `src/diagnostics/60_doctor.sh`, `completions/gamectl.bash`, `src/main.sh`, `src/tui/70_dashboard.sh`, `tests/test_cli.sh`, `bin/gamectl`

---

## 1. Objective & Technical Scope
Menuntaskan seluruh fitur setengah jalan (half-done / incomplete) yang teridentifikasi dalam audit mendalam:
1. **Savegame Recovery Engine (`restore_save`)**: Menyempurnakan sistem snapshot savegame dengan fungsi pemulihan deterministik (`restore_save`) dari recovery slot (`slot1`-`slot3`) dengan safety pre-restore stash dan CLI/TUI exposure.
2. **Bidirectional Remote Save Sync (`pull_save_remote`)**: Menuntaskan sinkronisasi savegame jarak jauh agar dapat menarik (pull) progres dari companion device kembali ke workstation lokal.
3. **Safety `--dry-run` Previews**: Menerapkan dukungan `--dry-run` pada operasi file destruktif (`pfx clean`, `fix-revert`, `sync`).
4. **Downloader Engine Diagnostics in `doctor`**: Memperbaiki gap audit pada `doctor_audit` Layer 6 agar memverifikasi ketersediaan binary native Rust `gamectl-depot-dl`.
5. **Full Bash Autocompletion Synchronization**: Memperbarui `completions/gamectl.bash` agar mencakup seluruh 13 subcommand baru yang dirilis pada v1.3 & v1.4.
6. **Deterministic Machine Gate**: Menambahkan test assertions penjaminan regresi dan mengompilasi ulang bundle mandiri `bin/gamectl`.

---

## 2. Granular Technical Execution Plan (Todolist)

### [x] Chunk 1: Savegame Recovery Engine (`restore_save`) & CLI/TUI Exposure [VERIFIED]
- **Target Files**: `src/core/10_utils.sh`, `src/main.sh`, `src/tui/70_dashboard.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Implementasi fungsi `restore_save()` di `src/core/10_utils.sh`:
     - Parameter: `restore_save <game_dir> [slot_num] [is_quiet]`.
     - Validasi keberadaan direktori game dan folder `$game_dir/.save_snapshots`.
     - Normalisasi format slot (`1` atau `slot1` -> `slot1`).
     - Buat safety stash di `.pre_restore_stash` jika folder `saves/` aktif ada isinya.
     - Timpa isi `saves/` dari slot terpilih via `cp -a "$target_slot/." "$save_dir/"`.
     - Catat log via `log_msg "INFO" "SAVE"`.
  2. Ekspor fungsi `restore_save` di `src/main.sh` dan tambahkan handler subcommand:
     `restore|--restore|restore-save) restore_save "$2" "${3:-1}" ;;`
  3. Integrasikan ke TUI library (`src/tui/70_dashboard.sh`):
     - Tambahkan hotkey `Ctrl-R` di `library_menu` untuk memicu pemulihan snapshot savegame interaktif.
  4. Tambahkan test assertion di `tests/test_cli.sh` untuk siklus snapshot -> edit -> restore slot -> verifikasi pemulihan.
- **Definition of Done (DoD)**:
  - Pemulihan savegame dari slot1/slot2/slot3 terbukti memulihkan data persis seperti saat snapshot dibuat.

### [x] Chunk 2: Bidirectional Remote Save Sync (`pull_save_remote` / `sync-pull`) [VERIFIED]
- **Target Files**: `src/runners/50_launcher.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Implementasi `pull_save_remote()` di `src/runners/50_launcher.sh`:
     - Parameter: `pull_save_remote <game_dir> [title] [remote_host] [--dry-run]`.
     - Validasi konektivitas host tujuan via ssh batchmode.
     - Lakukan `backup_save "$game_dir" true` terlebih dahulu untuk melindungi savegame lokal saat ini.
     - Jalankan `rsync -avzP --exclude="*.tmp" "$rhost:\"~/$rel_path/saves/\"" "$sdir/"`.
  2. Ekspos subcommand CLI di `src/main.sh`:
     `--sync-pull|sync-pull|pull-remote|pull-companion) pull_save_remote "$2" "${3:-Game}" "${4:-}" ;;`
- **Definition of Done (DoD)**:
  - Pengguna dapat menarik data savegame dari perangkat pendamping (companion host) dengan aman tanpa risiko kehilangan data lokal.

### [x] Chunk 3: Safety `--dry-run` Previews on Destructive Operations [VERIFIED]
- **Target Files**: `src/runners/40_wrappers.sh`, `src/steam/35_fixes.sh`, `src/runners/50_launcher.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `manage_prefix()` (`clean` action):
     - Tangkap flag `--dry-run` atau `-n`.
     - Jika aktif, cetak daftar ukuran dan file prefix yang akan dihapus serta konfirmasi pembuatan backup tanpa memanggil `rm -rf "$pfx_dir"`.
  2. Di `revert_game_fix()`:
     - Tangkap flag `--dry-run` atau `-n`.
     - Jika aktif, simulasikan pembacaan snapshot dan cetak daftar file yang akan dipulihkan dan file fix yang akan dihapus tanpa menulis ke disk.
  3. Di `sync_save_remote()`:
     - Tangkap flag `--dry-run` atau `-n` dan operkan flag `-n` ke perintah `rsync`.
- **Definition of Done (DoD)**:
  - Seluruh operasi pembersihan dan sinkronisasi mendukung preview non-destruktif.

### [x] Chunk 4: Downloader Engine Status Audit in `gamectl doctor` [VERIFIED]
- **Target Files**: `src/diagnostics/60_doctor.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `doctor_audit()` Layer 6 ("Manifest Harvester & CDN Providers"):
     - Panggil `resolve_depot_dl_bin` untuk mendeteksi binary Rust `gamectl-depot-dl`.
     - Jika ditemukan dan executable: laporkan `[READY]` dengan path binary.
     - Jika tidak ditemukan: laporkan `[WARN] Standalone Rust downloader not compiled (Run 'make build-depot-dl')`.
- **Definition of Done (DoD)**:
  - `gamectl doctor` secara akurat mencerminkan kesiapan engine pengunduh mandiri.

### [ ] Chunk 5: Full Shell Autocompletion Synchronization (`completions/gamectl.bash`)
- **Target Files**: `completions/gamectl.bash`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan 13 subcommand baru ke variabel `commands` di `completions/gamectl.bash`:
     - `fix-check`, `fix-install`, `fix-revert`, `restart-steam`, `fetch-manifest`, `deploy-manifest`, `harvest-dlc`, `login-luatools`, `auth-status`, `detect-steamstub`, `unpack-stub`, `setup-gbe`, `logs`, `restore`, `sync-pull`.
  2. Tambahkan penyelesaian opsi untuk subcommand-subcommand baru tersebut.
- **Definition of Done (DoD)**:
  - Shell autocomplete bekerja 100% untuk seluruh perintah yang didukung CLI.

### [ ] Chunk 6: Regression Test Suite Expansion, Rebuild & Machine Gate
- **Target Files**: `tests/test_cli.sh`, `bin/gamectl`, `PLAN.md`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan test assertions untuk `restore_save`, `--dry-run`, dan completion integrity.
  2. Kompilasi bundle mandiri `make build`.
  3. Jalankan `make lint`, `make test`, dan `cargo test`.
  4. Perbarui status checklist `[x]` pada `PLAN.md` menjadi `COMPLETED [VERIFIED]`.
- **DoD**:
  - Seluruh pengujian lulus dengan Exit Code 0 (total >= 118 assertions).
  - Standalone bundle `bin/gamectl` tersinkronisasi 100%.

---

## 3. Verification Matrix

| Komponen | Perintah Uji | Kriteria Sukses (DoD) |
| :--- | :--- | :--- |
| **Savegame Restore** | `./tests/test_cli.sh` | Slot recovery terbukti memulihkan data save asli. |
| **Bidirectional Sync** | `./tests/test_cli.sh` | CLI `sync-pull` terdaftar dan memvalidasi path target. |
| **Dry-Run Safety** | `./tests/test_cli.sh` | Flag `--dry-run` mencegah penghapusan prefix fisik. |
| **Doctor Downloader** | `bin/gamectl doctor` | Layer 6 mendeteksi dan menampilkan status `gamectl-depot-dl`. |
| **Completions** | `./tests/test_cli.sh` | File completion memuat seluruh 13+ subcommand baru. |
| **Machine Gate** | `make lint && make test` | 0 syntax errors, 118+ test assertions lulus dengan Exit Code 0. |
