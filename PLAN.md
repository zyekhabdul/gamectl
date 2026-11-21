# WORK PACKET 28: NATIVE LINUX ELF STEAMSTUB DRM UNPACKING & REMEDIATION ARCHITECTURE

- Track: Maintenance / DRM Remediation / Linux Native Independence / Zero-Bloat
- **Status**: COMPLETED & RATIFIED [4/4 CHUNKS EXECUTED]
- **Tujuan**: Mengimplementasikan unpacking otomatis DRM Valve Linux SteamStub (.bind) pada biner native Linux ELF (64-bit dan 32-bit seperti Boson X) agar game dapat langsung dimainkan secara offline dan standalone tanpa crash/tergantung pada Steam Client.

---

## 1. Implementasi Minimalis (YAGNI)

### [x] Chunk 28.01: Core Linux ELF SteamStub Unpacker Engine (`src/core/10_utils.sh`) [VERIFIED]
- Implementasi `unpack_steamstub_elf()` menggunakan Python 3 inline (zero-bloat, pure `struct` ELF32/ELF64 dual-architecture parser).
- Ekstraksi header rolling XOR pada seksi `.bind` (validasi signature 64-bit `0xc0dec0df` dan 32-bit `0xc0dec0de`).
- Dukungan bit flag `0x04` (`NoEncryption`): bypass dekripsi AES jika seksi kode sudah berupa plaintext untuk mencegah korupsi biner.
- Dekripsi seksi `.text` menggunakan AES-256-CBC (via library `cryptography` dengan graceful fallback ke CLI `openssl enc`).
- Pemulihan Original Entry Point (OEP) pada `e_entry` (offset `0x18`) untuk ELF32 dan ELF64 dan pembuatan biner `<binary>.unpacked` dengan bit eksekusi `0755`.
- Perluas `resolve_unpacked_binary()` untuk mengenali pola `${base_no_ext}.unpacked` dan `${gbin}.unpacked`.

### [x] Chunk 28.02: Launcher Pre-Flight Auto-Unpack & CLI Subcommand Integration (`src/runners/50_launcher.sh`, `src/core/10_utils.sh`, `src/main.sh`) [VERIFIED]
- Pada `launch_game()`, saat `stub_type == "linux_elf"`:
  - Cek ketersediaan biner unpacked via `resolve_unpacked_binary`.
  - Cek apakah biner in-place sudah diremediasi (entry point di luar `.bind`).
  - Jika belum ada, jalankan `unpack_steamstub_elf` secara otomatis sebelum eksekusi.
  - Alihkan `gbin` secara otomatis ke biner hasil unpack (`gbin="$unpacked_bin"`).
- Pada `cli_unpack_stub()`, tambahkan inspeksi arsitektur: dispatch ke `unpack_steamstub_pe` untuk Windows PE, dan `unpack_steamstub_elf` untuk Linux ELF.
- Perbarui `diagnose_steamstub()` agar menampilkan status DRM cerdas: membedakan active stub vs remediated binary (`.bind` inactive / OEP restored).
- Export `unpack_steamstub_elf` pada `src/main.sh`.

### [x] Chunk 28.03: Deterministic Machine Test Contracts (`tests/test_cli.sh`) [VERIFIED]
- Tambahkan 5 test contracts deterministik:
  1. `test_unpack_steamstub_elf_synthetic_contract`: Validasi parsing, dekripsi rolling XOR, AES-256-CBC, dan pemulihan OEP pada biner ELF64 sintetis.
  2. `test_unpack_steamstub_elf32_synthetic_contract`: Validasi parsing, rolling XOR, bypass NoEncryption, dan pemulihan OEP pada biner ELF32 sintetis.
  3. `test_cli_unpack_stub_dispatch_linux_elf`: Validasi bahwa CLI subcommand `gamectl unpack-stub` mendispatch Linux ELF dengan benar.
  4. `test_launch_game_auto_unpacks_linux_elf`: Validasi bahwa `launch_game` secara transparan mengeksekusi biner unpacked saat mendeteksi Linux ELF SteamStub.
  5. `test_diagnose_steamstub_remediated_contract`: Validasi status forensik active vs remediated binary pada `diagnose_steamstub`.

### [x] Chunk 28.04: Kompilasi & Verifikasi Machine Harness [VERIFIED]
- Kompilasi `bin/gamectl` via `./scripts/build.sh`.
- Jalankan `make lint`, `./scripts/build.sh --check`, `tests/test_cli.sh` (144/144 contracts pass, exit 0), dan `python3 -m unittest discover -s tests` (42/42 tests pass, exit 0).

---

## 2. Kriteria Selesai (DoD)
- [x] Biner Linux ELF (32-bit dan 64-bit) yang memiliki seksi `.bind` dapat di-unpack secara otomatis menghasilkan `<binary>.unpacked`.
- [x] Biner dengan flag `NoEncryption` (seperti Boson X) tidak rusak oleh dekripsi AES yang tidak semestinya.
- [x] `gamectl unpack-stub <elf_binary>` menghasilkan exit code 0 dan biner `0755`.
- [x] `gamectl launch` secara transparan memilih biner `<binary>.unpacked` tanpa memicu crash DRM atau membuka Steam Client.
- [x] `gamectl detect-steamstub` secara akurat mengidentifikasi status aktif vs status biner yang sudah diremediasi.
- [x] Biner tetap portabel dan zero-bloat tanpa dependensi package Python eksternal wajib (mendukung `cryptography` dan fallback `openssl`).
- [x] Seluruh machine test harness lolos dengan exit code 0 (144/144 contracts pass).
