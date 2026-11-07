# WORK PACKET 15: PURE STANDALONE REMEDIATION, OFFLINE DLC HARVESTER & STEAMSTUB DEFENSE [ACTIVE]

## 1. Objective & Technical Scope
Merespon hasil postmortem insiden blunder "PURCHASE" (INC-2026-11-07) dan ratifikasi arsitektur Pure Standalone (ADR-022), Work Packet 15 mengeksekusi remediasi komprehensif agar `gamectl` berfungsi 100% mandiri tanpa ketergantungan pada Steam Client resmi maupun plugin SLSsteam:

1. **Sovereign Library Path Resolution**: Menghilangkan hardcoding direktori Steam (`~/.local/share/Steam/steamapps/common/`) sebagai satu-satunya default. Menyediakan resolusi cerdas ke `$GAMECTL_LIBRARY_DIR` atau `$HOME/Games/` untuk instalasi standalone.
2. **Offline-Resilient DLC Harvester**: Memperbaiki `fetch_dlc` agar tidak hanya mengandalkan curl ke Steam Store API publik. Jika internet offline/timeout, otomatis mem-parsing daftar AppID DLC langsung dari stplugin `.lua` lokal untuk menghasilkan `steam_settings/DLC.txt`.
3. **SteamStub DRM Inspector & Pre-Flight Warning**: Mengintegrasikan deteksi seksi ELF `.bind` (Linux) dan SteamStub PE (Windows) ke dalam `preview_game` dan `launch_game` untuk mencegah silent crash / execution redirect ke `steam.sh`.
4. **Hardened Pre-Flight GBE Auto-Injection**: Memperkuat deteksi arsitektur (x64 vs x86) dan auto-injection Goldberg Emulator (`libsteam_api.so`, `steam_api64.dll`, `steam_api.dll`) di `launch_game` sebelum proses biner dijalankan.
5. **Standalone Savegame & Storage Sandbox**: Memastikan savegame redirection Goldberg (`./saves` atau `steam_settings/save_dir`) terkonfigurasi otomatis dan tercakup dalam 3-slot snapshot engine tanpa menyentuh Steam Cloud.
6. **CLI Flag Decoupling & Engine Standardization**: Menjadikan `--standalone` sebagai default content & runtime engine pada `gamectl download` dan `gamectl launch`, serta membatasi `--sls` sebagai opt-in flag murni.
7. **Regression Test Suite Expansion**: Menambahkan skenario uji verifikasi offline DLC, deteksi SteamStub ELF `.bind`, dan standalone download routing di `tests/test_cli.sh` dengan target 88+ assertions (exit code 0).

---

## 2. Granular Technical Execution Plan (Work Packet 15)

### Chunk 1: Sovereign Library Path Resolution
- **Target Files**: `src/steam/30_downloader.sh`, `src/core/10_utils.sh`
- **Runtutan Eksekusi Teknis**:
  1. Buat fungsi `resolve_standalone_library_dir()` yang memprioritaskan:
     - Argument direktori eksplisit user.
     - Environment variable `$GAMECTL_LIBRARY_DIR`.
     - File config `$HOME/.config/gamectl/library_dir`.
     - Default sovereign directory: `$HOME/Games`.
  2. Pastikan `download_game` pada mode `--standalone` menggunakan path sovereign ini dan tidak memaksa instalasi ke folder `steamapps/common`.
- **DoD**: Unduhan standalone tersimpan di `$HOME/Games/<Title>` tanpa membuat symlink atau manifest di direktori Steam.

### Chunk 2: Offline-Resilient DLC Harvester
- **Target Files**: `src/steam/30_downloader.sh`
- **Runtutan Eksekusi Teknis**:
  1. Modifikasi `fetch_dlc`:
     - Coba ambil data dari Steam Store API via curl dengan timeout 3 detik.
     - Jika curl gagal atau mengembalikan JSON kosong (kondisi offline), lakukan fallback parsing terhadap file `.lua` milik AppID tersebut:
       Ekstrak seluruh `addappid(<id>)` yang bukan AppID induk game.
     - Tulis setiap AppID DLC ke `<game_dir>/steam_settings/DLC.txt` format `<dlc_id>=DLC_<dlc_id>`.
  2. Pastikan file `DLC.txt` ter-generate valid bahkan saat koneksi internet terputus total.
- **DoD**: Gamectl mampu menghasilkan `steam_settings/DLC.txt` lengkap saat dijalankan tanpa akses jaringan (air-gapped/offline).

### Chunk 3: SteamStub DRM Inspector & Pre-Flight Warning
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`
- **Runtutan Eksekusi Teknis**:
  1. Buat fungsi `detect_steamstub_drm "$binary_path"`:
     - Linux ELF: Periksa keberadaan seksi `.bind` (`readelf -S "$bin" 2>/dev/null | grep -q '\.bind'`).
     - Windows PE: Periksa pola header SteamStub atau gunakan Steamless detection.
  2. Tampilkan status SteamStub pada HUD controller dan TUI dashboard preview.
  3. Jika terdeteksi di Linux ELF pada `launch_game`, cetak peringatan diagnostik terarah bahwa game memiliki enkripsi stub bawaan Valve.
- **DoD**: `detect_steamstub_drm` mendeteksi seksi `.bind` pada binary Boson X secara akurat dan mengembalikan exit code 0.

### Chunk 4: Pre-Flight GBE Auto-Injection Hardening
- **Target Files**: `src/runners/50_launcher.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pertajam pre-flight inspection di `launch_game`:
     - Deteksi arsitektur biner game target secara presisi (ELF 32-bit vs 64-bit via `file -b`).
     - Jika target biner adalah 32-bit (seperti Boson X), pastikan emulator yang di-inject adalah x86 template (`gbe-fork/regular/x86/libsteam_api.so`).
     - Jika target biner adalah 64-bit, gunakan x64 template.
  2. Pastikan file backup `.orig` tersimpan aman dan tidak tertimpa jika injeksi diulang.
- **DoD**: Setiap game yang dijalankan otomatis ter-shim dengan arsitektur yang cocok sebelum dieksekusi.

### Chunk 5: Standalone Savegame Redirection & Snapshot Isolation
- **Target Files**: `src/runners/50_launcher.sh`
- **Runtutan Eksekusi Teknis**:
  1. Pada `inject_game`, pastikan direktori `<game_dir>/saves/` terbuat dengan izin `0700`.
  2. Jika game menggunakan Goldberg Emulator, pastikan `local_save.txt` atau konfigurasi save redirection aktif mengarah ke `./saves/`.
  3. Validasi bahwa fungsi `backup_save` tetap membackup slot snapshot dari folder `./saves/` lokal game sebelum sesi bermain dimulai.
- **DoD**: Savegame tersimpan terlokalisasi di dalam folder game, bebas dari dependensi Steam Cloud.

### Chunk 6: CLI Engine Decoupling (`--standalone` Default)
- **Target Files**: `src/main.sh`, `src/steam/30_downloader.sh`
- **Runtutan Eksekusi Teknis**:
  1. Ubah default engine pada `gamectl download` dari hybrid/steam menjadi `--engine standalone`.
  2. Opsi `--sls` atau `--engine steam` hanya aktif jika user secara eksplisit memberikan flag tersebut.
  3. Sinkronkan teks panduan CLI (`--help`) dan dokumentasi pengguna (`docs/GUIDE.md`).
- **DoD**: Menjalankan `gamectl download <appid>` secara default menjalankan engine mandiri tanpa menyentuh Steam Client.

### Chunk 7: Regression Harness Expansion & Machine Verification
- **Target Files**: `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan unit test untuk `detect_steamstub_drm` (menguji biner mock ber-seksi `.bind`).
  2. Tambahkan unit test untuk offline `fetch_dlc` fallback dari file Lua stplugin.
  3. Tambahkan unit test untuk resolusi path sovereign `$GAMECTL_LIBRARY_DIR`.
  4. Jalankan `scripts/build.sh` untuk kompilasi biner `bin/gamectl`.
  5. Jalankan `tests/test_cli.sh` dan pastikan seluruh test assertions (target 88+) lulus dengan Exit Code 0.
- **DoD**: Test runner melaporkan 88+ passed, 0 failed, exit code 0.

---

## 3. Matriks Milestone (Work Packet 15)
- [ ] Chunk 1: Sovereign Library Path Resolution [PENDING]
- [ ] Chunk 2: Offline-Resilient DLC Harvester [PENDING]
- [ ] Chunk 3: SteamStub DRM Inspector & Pre-Flight Warning [PENDING]
- [ ] Chunk 4: Pre-Flight GBE Auto-Injection Hardening [PENDING]
- [ ] Chunk 5: Standalone Savegame Redirection & Snapshot Isolation [PENDING]
- [ ] Chunk 6: CLI Engine Decoupling (`--standalone` Default) [PENDING]
- [ ] Chunk 7: Regression Harness Expansion & Machine Verification [PENDING]
