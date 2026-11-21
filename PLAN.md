# WORK PACKET 28: NATIVE LINUX ELF STEAMSTUB DRM UNPACKING & REMEDIATION ARCHITECTURE

- Track: Maintenance / DRM Remediation / Linux Native Independence / Zero-Bloat
- **Status**: COMPLETED & RATIFIED [4/4 CHUNKS EXECUTED]
- **Tujuan**: Mengimplementasikan unpacking otomatis DRM Valve Linux SteamStub (.bind) pada biner native Linux ELF (seperti Boson X) agar game dapat langsung dimainkan secara offline dan standalone tanpa crash/tergantung pada Steam Client.

---

## 1. Implementasi Minimalis (YAGNI)

### [x] Chunk 28.01: Core Linux ELF SteamStub Unpacker Engine (`src/core/10_utils.sh`) [VERIFIED]
- Implementasi `unpack_steamstub_elf()` menggunakan Python 3 inline (zero-bloat, pure `struct` ELF32/ELF64 parser).
- Ekstraksi header rolling XOR pada seksi `.bind` (validasi signature `0xc0dec0df`).
- Dekripsi seksi `.text` menggunakan AES-256-CBC (via library `cryptography` dengan graceful fallback ke CLI `openssl enc`).
- Pemulihan Original Entry Point (OEP) pada `e_entry` (offset `0x18`) dan pembuatan biner `<binary>.unpacked` dengan bit eksekusi `0755`.
- Perluas `resolve_unpacked_binary()` untuk mengenali pola `${base_no_ext}.unpacked` dan `${gbin}.unpacked`.

### [x] Chunk 28.02: Launcher Pre-Flight Auto-Unpack & CLI Subcommand Integration (`src/runners/50_launcher.sh`, `src/core/10_utils.sh`, `src/main.sh`) [VERIFIED]
- Pada `launch_game()`, saat `stub_type == "linux_elf"`:
  - Cek ketersediaan biner unpacked via `resolve_unpacked_binary`.
  - Jika belum ada, jalankan `unpack_steamstub_elf` secara otomatis sebelum eksekusi.
  - Alihkan `gbin` secara otomatis ke biner hasil unpack (`gbin="$unpacked_bin"`).
- Pada `cli_unpack_stub()`, tambahkan inspeksi arsitektur: dispatch ke `unpack_steamstub_pe` untuk Windows PE, dan `unpack_steamstub_elf` untuk Linux ELF.
- Perbarui `diagnose_steamstub()` agar menampilkan status Unpack (Ready / Pending) dan panduan remediasi untuk Linux ELF.
- Export `unpack_steamstub_elf` pada `src/main.sh`.

### [x] Chunk 28.03: Deterministic Machine Test Contracts (`tests/test_cli.sh`) [VERIFIED]
- Tambahkan 3 test contracts deterministik:
  1. `test_unpack_steamstub_elf_synthetic_contract`: Validasi parsing, dekripsi rolling XOR, AES-256-CBC, dan pemulihan OEP pada biner ELF sintetis.
  2. `test_cli_unpack_stub_dispatch_linux_elf`: Validasi bahwa CLI subcommand `gamectl unpack-stub` mendispatch Linux ELF dengan benar.
  3. `test_launch_game_auto_unpacks_linux_elf`: Validasi bahwa `launch_game` secara transparan mengeksekusi biner unpacked saat mendeteksi Linux ELF SteamStub.

### [x] Chunk 28.04: Kompilasi & Verifikasi Machine Harness [VERIFIED]
- Kompilasi `bin/gamectl` via `./scripts/build.sh` (11728 baris).
- Jalankan `make lint`, `./scripts/build.sh --check`, `tests/test_cli.sh` (142/142 contracts pass, exit 0), dan `python3 -m unittest discover -s tests` (42/42 tests pass, exit 0).

---

## 2. Kriteria Selesai (DoD)
- [x] Biner Linux ELF yang memiliki seksi `.bind` dapat di-unpack secara otomatis menghasilkan `<binary>.unpacked`.
- [x] `gamectl unpack-stub <elf_binary>` menghasilkan exit code 0 dan biner `0755`.
- [x] `gamectl launch` secara transparan memilih biner `<binary>.unpacked` tanpa memicu crash DRM atau membuka Steam Client.
- [x] Biner tetap portabel dan zero-bloat tanpa dependensi package Python eksternal wajib (mendukung `cryptography` dan fallback `openssl`).
- [x] Seluruh machine test harness lolos dengan exit code 0 (142/142 contracts pass).
