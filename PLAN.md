# WORK PACKET 16: TURNKEY SOVEREIGN RUNTIME, GBE AUTO-PROVISIONING & DRUG-FREE HARNESS [ACTIVE]

**Track**: Maintenance

## 1. Objective & Technical Scope
Mewujudkan 100% Turnkey Sovereign Gaming Experience sesuai Piagam Dasar `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`:
1. **Zero-Defect Harness & Environment Hardening**: Memperbaiki bug unbound variable `${REPO_ROOT:-}`, menstabilkan fixture mock di `test_cli.sh`, dan memastikan script build graceful tanpa toolchain Rust eksternal. (88/88 test pass, exit 0).
2. **Turnkey GBE Provisioning (`setup-gbe`)**: Menghilangkan akar masalah kegagalan injeksi emulator dengan menyediakan mekanisme otomatis untuk mengunduh dan menata template biner Goldberg Emulator resmi ke `~/.local/share/gbe-fork/`.
3. **Pre-Flight Hard-Stop Guard di `launch_game`**: Menolak peluncuran game unshielded secara deterministik jika biner Valve belum ter-shim Goldberg Emulator.
4. **Active SteamStub Mitigation Hook**: Mengintegrasikan unpacker otomatis Steamless CLI untuk PE Windows dan interceptor stub untuk Linux ELF `.bind`.
5. **Full DLC Manifest Resolution**: Menjamin depot fisik DLC terunduh lengkap bersama game dasar dari CDN Valve.

---

## 2. Granular Technical Execution Plan (Work Packet 16)

### Chunk 1: Bugfix ${REPO_ROOT:-} & Isolasi Mock Fixture di test_cli.sh [VERIFIED]
- **Target Files**: `src/steam/20_discovery.sh`, `scripts/build-depot-dl.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Perbaiki ekspansi `REPO_ROOT` di `src/steam/20_discovery.sh` menjadi `${REPO_ROOT:-}` untuk mencegah crash `unbound variable` saat `set -u` aktif.
  2. Modifikasi `scripts/build-depot-dl.sh` agar mem-parse flag `--check` sebelum memeriksa dependensi `cargo`, dan mempertahankan precompiled binary yang sudah ada jika cargo tidak terpasang.
  3. Perbarui `test_doctor_audit()` di `tests/test_cli.sh` dengan mock fixture GBE terisolasi.
  4. Perbarui `test_optimized_library_scanner()` di `tests/test_cli.sh` dengan mock library game mandiri.
  5. Sinkronisasi biner via `scripts/build.sh` dan jalankan `tests/test_cli.sh` hingga exit code 0 (88/88 passed).
- **DoD**: Seluruh 88 test assertion lulus 100% dengan status Exit Code 0.

### Chunk 2: Implementasi `gamectl setup-gbe` (Auto-download & provisioning Goldberg templates) [PENDING]
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Buat fungsi `setup_gbe_templates()` untuk mengunduh rilis Goldberg Emulator resmi/fork dari sovereign mirror.
  2. Ekstrak biner template (`libsteam_api.so`, `steam_api64.dll`, `steam_api.dll`) ke `~/.local/share/gbe-fork/`.
  3. Daftarkan CLI subcommand `gamectl setup-gbe` dan opsi auto-prompt di TUI.
- **DoD**: Template GBE terpasang lengkap di `~/.local/share/gbe-fork/` tanpa intervensi manual user.

### Chunk 3: Pre-flight Hard-Stop & GBE Guard di `launch_game` [PENDING]
- **Target Files**: `src/runners/50_launcher.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pada `launch_game`, jika game terdeteksi memiliki dependensi `steam_api` dan belum ter-shim GBE:
     - Jalankan `inject_game`.
     - Jika GBE template belum ada, picu `setup_gbe_templates` secara otomatis.
     - Jika tetap gagal, hard-stop peluncuran dengan instruksi solutif guna mencegah game memanggil Steam Client ("PURCHASE").
- **DoD**: Tidak ada game ber-Steamworks yang diizinkan jalan tanpa perlindungan emulator GBE.

### Chunk 4: SteamStub Unpack/Interceptor Hook [PENDING]
- **Target Files**: `src/runners/50_launcher.sh`, `src/core/10_utils.sh`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan handler untuk biner Windows PE SteamStub via Steamless CLI.
  2. Tambahkan stub interceptor untuk Linux ELF `.bind` guna mencegah redirect paksa ke `steam.sh`.
- **DoD**: Biner SteamStub ter-unpack atau ter-intercept sebelum proses game dieksekusi.

### Chunk 5: Full DLC Manifest Resolution Harvester Expansion [PENDING]
- **Target Files**: `src/steam/30_downloader.sh`
- **Runtutan Eksekusi Teknis**:
  1. Perluas `fetch_manifest` dan `download_game` untuk memvalidasi ketersediaan depot fisik DLC.
  2. Unduh depot manifest DLC tambahan jika tersedia di provider.
- **DoD**: Unduhan game mencakup file fisik depot DLC secara utuh.

---

## 3. Matriks Milestone (Work Packet 16)
- [x] Chunk 1: Bugfix ${REPO_ROOT:-} & Isolasi Mock Fixture di test_cli.sh [VERIFIED]
- [ ] Chunk 2: Implementasi `gamectl setup-gbe` (Auto-download & provisioning Goldberg templates) [PENDING]
- [ ] Chunk 3: Pre-flight Hard-Stop & GBE Guard di `launch_game` [PENDING]
- [ ] Chunk 4: SteamStub Unpack/Interceptor Hook [PENDING]
- [ ] Chunk 5: Full DLC Manifest Resolution Harvester Expansion [PENDING]
