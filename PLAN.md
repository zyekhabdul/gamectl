# WORK PACKET 22: COMPLETION OF HALF-DONE ARCHITECTURE & SOVEREIGN CAPABILITIES

**Track**: Feature Completion & Runtime Hardening  
**Status**: COMPLETED [VERIFIED]  
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

### [x] Chunk 5: Full Shell Autocompletion Synchronization (`completions/gamectl.bash`) [VERIFIED]
- **Target Files**: `completions/gamectl.bash`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan 13 subcommand baru ke variabel `commands` di `completions/gamectl.bash`:
     - `fix-check`, `fix-install`, `fix-revert`, `restart-steam`, `fetch-manifest`, `deploy-manifest`, `harvest-dlc`, `login-luatools`, `auth-status`, `detect-steamstub`, `unpack-stub`, `setup-gbe`, `logs`, `restore`, `sync-pull`.
  2. Tambahkan penyelesaian opsi untuk subcommand-subcommand baru tersebut.
- **Definition of Done (DoD)**:
  - Shell autocomplete bekerja 100% untuk seluruh perintah yang didukung CLI.

### [x] Chunk 6: Regression Test Suite Expansion, Rebuild & Machine Gate [VERIFIED]
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

---

# WORK PACKET 23: RUNTIME HARDENING, PROCESS SUPERVISION & RESILIENCE

**Track**: Stability / Zero Risk / High Reliability  
**Status**: PLANNED [READY FOR RESUME]  
**Branch**: `main`  
**Max Chunks**: 6 Chunks  
**Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`, `crates/depot-dl/src/bin/gamectl-depot-dl.rs`, `crates/depot-dl/src/util.rs`, `crates/depot-dl/src/manifest/mod.rs`, `packaging/debian/build-deb.sh`, `pyproject.toml`, `tests/test_cli.sh`, `bin/gamectl`

---

## 1. Objective & Technical Scope
Menyelesaikan sisa temuan audit mendalam (Maintenance Audit & Verification 2026-11-10) untuk mencapai standar Zero Error, Zero Risk, dan Zero Trouble:
1. **Transactional Savegame Restore (`restore_save`)**: Mengganti penghapusan prematur live saves (`rm -rf`) dengan atomic staging, backup verifikasi sebelum penghapusan, dan rollback terjamin saat error copy/disk full.
2. **Supervisor Process Ownership (`launch_game`)**: Mengganti sibling process wait (`wait "$game_pid"` di subshell background terpisah yang return 127) dengan arsitektur supervisor yang memegang child process secara langsung dan mencegah cleanup prematur saat game masih aktif.
3. **Remote Sync Robustness (`sync_save_remote`, `pull_save_remote`)**:
   - Memvalidasi exit status `rsync` dan `ssh` secara ketat (tidak mencetak `[VERIFIED]` saat transfer gagal).
   - Memperbaiki ekspansi tilde remote (`~`) dengan menghapus quoting yang mencegah resolusi home directory remote.
   - Menghilangkan side-effect `mkdir -p "$sdir"` pada flag `--dry-run`.
4. **TUI Action Observability (`70_dashboard.sh`)**:
   - Menghubungkan notifikasi visual TUI ke exit code backend yang sebenarnya (mencegah modal sukses palsu).
   - Membungkus eksekusi perintah di dashboard agar tidak membocorkan raw stdout/stderr ke layar fzf.
5. **Rust Quality & Mutation Hardening (`crates/depot-dl`)**:
   - Memperbaiki 3 Clippy strict warnings (`single_match_else`, `manual_checked_ops`).
   - Merapikan formatting dengan `cargo fmt`.
   - Mengatasi test fixture `all-features` yang hilang di `src/manifest/mod.rs` (isolasi/synthetic fixtures).
   - Menambahkan unit test edge-case pada `safe_relative_path` (`.`, `..`, `/`) untuk menangkap 1 mutan yang lolos (target: 100% mutation score).
6. **Multi-Arch Packaging & Dependency Advisory Review**:
   - Memperbaiki deklarasi architecture pada paket Debian (`Architecture: any/amd64` bukan `all`) dan wheel Python agar tidak mengemas binary ELF x86-64 dengan tag `py3-none-any`.
   - Melakukan evaluasi reachability pada 8 dependensi Rust dengan advisory OSV.

---

## 2. Granular Technical Execution Plan (Todolist)

### [ ] Chunk 1: Transactional Savegame Restore Engine (`restore_save`)
- **Target Files**: `src/core/10_utils.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `restore_save()`:
     - Tahap A (Staging): Salin snapshot terpilih ke staging temporary directory di `.save_snapshots/.staging_restore_$$`.
     - Tahap B (Verifikasi Staging): Pastikan proses copy berhasil 100% dan direktori staging tidak kosong. Jika gagal, batalkan tanpa menyentuh live save.
     - Tahap C (Safety Backup): Pindahkan atau buat backup utuh live save ke `.save_snapshots/.pre_restore_stash` dengan verifikasi return code.
     - Tahap D (Commit): Pindahkan hasil staging ke direktori `saves/` aktif secara atomik.
     - Tahap E (Rollback): Jika tahap commit gagal, pulihkan kembali live save dari stash.
  2. Tambahkan test di `tests/test_cli.sh` dengan simulasi `cp` gagal (fault injection) untuk membuktikan data save asli tetap utuh.
- **DoD**:
  - Live save tidak pernah hilang atau rusak ketika terjadi kegagalan penyalinan snapshot.

### [ ] Chunk 2: Supervisor Process Ownership in Background Watchdog
- **Target Files**: `src/runners/50_launcher.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Restrukturisasi pemanggilan game background di `launch_game()`:
     - Gunakan dedicated supervisor wrapper shell yang meluncurkan game sebagai child langsungnya, sehingga `wait "$child_pid"` valid dan menangkap exit code asli.
     - Hanya picu pembersihan `$info_file`, penghentian systemd scope, dan restorasi CPU governor SETELAH child benar-benar exit.
  2. Tambahkan regression test di `tests/test_cli.sh` memverifikasi `$info_file` tetap ada selama proses game mock berjalan di background.
- **DoD**:
  - Watchdog tidak lagi mengembalikan exit code 127, dan status proses game terpantau akurat dari peluncuran hingga selesai.

### [ ] Chunk 3: Remote Sync Robustness & Zero-Side-Effect Dry-Run
- **Target Files**: `src/runners/50_launcher.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Tangkap exit code `rsync`:
     - Jika rsync mengembalikan kode != 0, tampilkan pesan error dan hentikan dengan return code 1.
  2. Perbaiki remote tilde quoting:
     - Gunakan `$HOME` remote atau unquoted tilde saat membuat direktori via SSH.
  3. Di `pull_save_remote()`:
     - Pastikan `mkdir -p "$sdir"` hanya berjalan jika `[ "$is_dry_run" = false ]`.
     - Validasi keberhasilan `backup_save` sebelum memulai rsync penimpaan.
  4. Tambahkan test case di `tests/test_cli.sh` untuk rsync failure mock dan dry-run directory creation avoidance.
- **DoD**:
  - Gagal rsync melaporkan error, remote tilde berekspansi ke remote user home, dan dry-run tidak mengubah filesystem lokal.

### [ ] Chunk 4: TUI Action Wrapper & Observability
- **Target Files**: `src/tui/70_dashboard.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Implementasikan helper `tui_exec_action()` untuk menjalankan operasi backend (inject, sync, backup, fix).
  2. Tangkap output stdout/stderr ke buffer sementara dan periksa exit code status backend.
  3. Tampilkan modal notice hasil: `[SUCCESS]` jika rc=0, `[ERROR]` dengan ringkasan error jika rc!=0.
- **DoD**:
  - Pengguna mendapatkan umpan balik akurat di TUI saat aksi berhasil maupun gagal.

### [ ] Chunk 5: Rust Quality Gate & Mutation Hardening
- **Target Files**: `crates/depot-dl/src/bin/gamectl-depot-dl.rs`, `crates/depot-dl/src/util.rs`, `crates/depot-dl/src/manifest/mod.rs`
- **Runtutan Eksekusi Teknis**:
  1. Selesaikan 3 Clippy warnings di `gamectl-depot-dl.rs` (ganti `match ... None => exit(1)` dengan idiomatic `unwrap_or_else`, rapikan formula pembagian).
  2. Jalankan `cargo fmt` untuk standardisasi format file Rust.
  3. Tambahkan unit test di `crates/depot-dl/src/util.rs` yang menguji input normalization kosong (`.`, `..`, `/`) pada `safe_relative_path`.
  4. Isolasi fixture test `all-features` di `src/manifest/mod.rs` dengan synthetic fixtures atau conditional skip jika file eksternal tidak ada.
- **DoD**:
  - `cargo clippy --all-targets -- -D warnings` lulus tanpa warning.
  - `cargo fmt --check` lulus tanpa diff.
  - Mutation score `src/util.rs` mencapai 100% (43/43 caught).

### [ ] Chunk 6: Multi-Arch Packaging & Deterministic Verification Gate
- **Target Files**: `packaging/debian/build-deb.sh`, `pyproject.toml`, `Makefile`, `bin/gamectl`
- **Runtutan Eksekusi Teknis**:
  1. Sinkronisasi arsitektur paket:
     - Sesuaikan `Architecture` pada Debian deb dan platform tag pada Python wheel sesuai keberadaan binary native.
  2. Re-bundle `bin/gamectl` via `make build`.
  3. Jalankan `make lint`, `./scripts/build.sh --check`, dan `./tests/test_cli.sh` (122+ assertions PASS).
- **DoD**:
  - Semua artifact distribusi memiliki metadata arsitektur valid dan seluruh test suite lulus 100%.

---

## 3. Verification Matrix (Work Packet 23)

| Komponen | Perintah Uji | Kriteria Sukses (DoD) |
| :--- | :--- | :--- |
| **Transactional Restore** | `./tests/test_cli.sh` | Live save utuh saat proses restore diinterupsi/gagal. |
| **Process Supervision** | `./tests/test_cli.sh` | Metadata `$info_file` bertahan selama game hidup di background. |
| **Remote Sync Guard** | `./tests/test_cli.sh` | Gagal transfer rsync menghasilkan exit code 1; `--dry-run` zero write. |
| **TUI Action Handling** | Smoke PTY test | Modal error muncul saat aksi gagal; terminal buffer bersih. |
| **Rust Clippy & Format** | `cargo clippy && cargo fmt` | Zero warning pada strict clippy, zero formatting issues. |
| **Mutation Testing** | `cargo mutants` | 100% mutan tertangkap pada `safe_relative_path`. |
| **Full Machine Gate** | `make lint && make test` | 122/122 assertions lulus dengan Exit Code 0. |
