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

### Chunk 2: Implementasi `gamectl setup-gbe` (Auto-download & provisioning Goldberg templates) [VERIFIED]
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Buat fungsi `setup_gbe_templates()` untuk mengunduh rilis Goldberg Emulator resmi/fork dari upstream release (`Detanup01/gbe_fork`).
  2. Ekstrak biner template (`libsteam_api.so`, `steam_api64.dll`, `steam_api.dll`) ke `~/.local/share/gbe-fork/`.
  3. Daftarkan CLI subcommand `gamectl setup-gbe` dan auto-provisioning di `inject_game`.
  4. Perluas test suite regression dengan `test_setup_gbe_cli_contract` dan `test_setup_gbe_mock_provisioning_contract`.
- **DoD**: Template GBE terpasang lengkap di `~/.local/share/gbe-fork/` tanpa intervensi manual user, 90/90 test assertions lulus dengan Exit Code 0.

### Chunk 3: Pre-flight Hard-Stop & GBE Guard di `launch_game` [VERIFIED]
- **Target Files**: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pada `src/runners/40_wrappers.sh`, tambahkan flag `--allow-unshielded` untuk bypass darurat.
  2. Pada `src/runners/50_launcher.sh` (`launch_game`), periksa kandidat library Steamworks (`steam_api64.dll`, `steam_api.dll`, `libsteam_api.so`) hingga kedalaman folder 4.
  3. Lakukan auto-injeksi GBE (`inject_game`) jika ditemukan library Valve unshielded.
  4. Lakukan evaluasi ulang pasca-injeksi. Jika masih unshielded dan `--allow-unshielded` tidak diaktifkan, lakukan hard-stop terstruktur dengan exit code 1 dan instruksi remediasi.
  5. Perbaiki penanganan sinyal dan pembersihan status (`_restore_launch_state`) agar bebas dari unbound variables dan dependencies missing.
  6. Tambahkan 2 uji regresi di `tests/test_cli.sh` (`test_launch_hardstop_unshielded_contract` & `test_launch_allow_unshielded_override_contract`).
- **DoD**: Tidak ada game ber-Steamworks yang diizinkan jalan tanpa perlindungan emulator GBE (92/92 test assertions lulus Exit 0).

### Chunk 4: SteamStub Unpack/Interceptor Hook [VERIFIED]
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Implementasikan utilitas pendukung SteamStub di `src/core/10_utils.sh`: `detect_steamstub_type`, `resolve_unpacked_binary`, `find_steamless_cli`, `unpack_steamstub_pe`, dan `setup_steam_interceptor`.
  2. Pasang sovereign interceptor `setup_steam_interceptor` pada `src/runners/50_launcher.sh` (`launch_game`) di posisi terdepan `$PATH` untuk mencegat dan membungkam pemanggilan biner `steam` / `steam.sh` secara mandiri.
  3. Tambahkan logika mitigasi otomatis SteamStub PE pada `launch_game`: otomatis mendeteksi biner `*.unpacked.exe`, mengeksekusi Steamless CLI jika tersedia, dan mengalihkan binary peluncuran ke versi unpacked.
  4. Tambahkan pengujian regresi di `tests/test_cli.sh`: `test_steam_interceptor_contract` dan `test_steamstub_pe_unpack_resolution_contract`.
- **DoD**: Biner SteamStub ter-unpack atau ter-intercept sebelum proses game dieksekusi (94/94 test assertions lulus Exit 0).

### Chunk 5: Full DLC Manifest Resolution Harvester Expansion [PENDING]
- **Target Files**: `src/steam/30_downloader.sh`
- **Runtutan Eksekusi Teknis**:
  1. Perluas `fetch_manifest` dan `download_game` untuk memvalidasi ketersediaan depot fisik DLC.
  2. Unduh depot manifest DLC tambahan jika tersedia di provider.
- **DoD**: Unduhan game mencakup file fisik depot DLC secara utuh.

---

## 3. Matriks Milestone (Work Packet 16)
- [x] Chunk 1: Bugfix ${REPO_ROOT:-} & Isolasi Mock Fixture di test_cli.sh [VERIFIED]
- [x] Chunk 2: Implementasi `gamectl setup-gbe` (Auto-download & provisioning Goldberg templates) [VERIFIED]
- [x] Chunk 3: Pre-flight Hard-Stop & GBE Guard di `launch_game` [VERIFIED]
- [x] Chunk 4: SteamStub Unpack/Interceptor Hook [VERIFIED]
- [ ] Chunk 5: Full DLC Manifest Resolution Harvester Expansion [PENDING]
