# WORK PACKET 29: SCANNER DEDUPLICATION, MULTI-STORE PRECEDENCE & TUI SHORTCUT INTEGRATION

- Track: Core Scanner / Discovery Robustness / UI Ergonomics / Zero-Bloat
- **Status**: COMPLETED & RATIFIED [5/5 CHUNKS EXECUTED]
- **Tujuan**: Mengeliminasi duplikasi entri game pada scanner (penanganan symlink & AppID collision antar-library), memperkuat heuristik deteksi status GBE, dan mengintegrasikan pembuatan shortcut FreeDesktop (.desktop) langsung dari TUI Dashboard.

---

## 1. Rencana Eksekusi & Quality Gate (Machine Verification)

### [x] Chunk 29.01: Modular Source Patching (`src/steam/20_discovery.sh`, `src/tui/70_dashboard.sh`) [VERIFIED]
- **Scanner Symlink Canonicalization (`src/steam/20_discovery.sh`)**:
  - Terapkan `realpath -e` pada variabel `$gdir` sebelum validasi `seen_dirs` di Loop 1 (Steam common) dan Loop 2 (Custom search dirs).
  - Pastikan symlink (seperti `steamapps/common/RustedWarfare -> ~/Games/RustedWarfare`) tidak terdaftar dua kali.
- **AppID Collision Precedence (`src/steam/20_discovery.sh`)**:
  - Inisialisasi tabel hash `seen_appids=()`.
  - Catat seluruh AppID numerik valid pada Loop 1 (Steam libraries).
  - Pada Loop 2 (Custom search dirs), lewati direktori dengan AppID numerik yang sudah terdaftar di `seen_appids` untuk mencegah duplikasi game fisik ganda.
- **Heuristik Deteksi GBE Multi-Dimensi (`src/steam/20_discovery.sh`)**:
  - Perluas evaluasi status `GBE_FORK` tidak hanya berdasarkan ukuran statis (`> 7 MB`), tetapi juga kehadiran artefak GBE: `.orig` backup binary, direktori `steam_settings/`, atau file `local_save.txt`.
- **Integrasi FreeDesktop Shortcut ke TUI (`src/tui/70_dashboard.sh`)**:
  - Perbarui header TUI library: tambahkan instruksi `Ctrl-D: Make Desktop`.
  - Petakan event handler `ctrl-d` untuk memanggil `create_desktop_entry "$sel_dir" "$sel_title"` dengan modal notice konfirmasi keberhasilan/kegagalan.

### [x] Chunk 29.02: Deterministic Compilation (`scripts/build.sh`) [VERIFIED]
- Jalankan `./scripts/build.sh` atau `make build` untuk mengompilasi modular source ke biner mandiri `bin/gamectl`.
- Verifikasi biner terbangun utuh dengan bit eksekusi `0755`.

### [x] Chunk 29.03: Syntax & Lint Gate (`make lint`) [VERIFIED]
- Jalankan `make lint` (`bash -n` ke seluruh modul shell di `src/`, `bin/`, `scripts/`, `packaging/`, dan `tests/`).
- Pastikan: 0 syntax error dan exit code 0.

### [x] Chunk 29.04: Regression & Integrity Test Suite (`tests/test_cli.sh`) [VERIFIED]
- Tambahkan test contract deterministik untuk symlink resolving dan AppID deduplication di `tests/test_cli.sh`.
- Jalankan `make test` (`./tests/test_cli.sh`).
- Pastikan seluruh test contracts lolos (exit code 0, 0 failures; 147/147 contracts pass).

### [x] Chunk 29.05: Empirical Install & Runtime Cache Purge [VERIFIED]
- Salin biner hasil kompilasi ke biner sistem lokal: `cp bin/gamectl ~/.local/bin/gamectl` (tervalidasi symlink SSOT).
- Bersihkan file cache usang: `rm -f /run/user/1000/scancache.tab`.
- Jalankan `gamectl list-formatted --refresh` dan verifikasi empiris terminal:
  - Terraria hanya muncul 1 entri: `105600 Terraria [GBE_FORK]`.
  - Rusted Warfare hanya muncul 1 entri: `647960 RustedWarfare [GBE_FORK]`.

---

## 2. Kriteria Selesai (Definition of Done)
- [x] Symlink game antar-library Steam dan `~/Games` tidak menghasilkan duplikat pada scanner.
- [x] Game dengan AppID sama pada multi-library terdeduplikasi dengan rapi (1 entri per game).
- [x] Deteksi status `[GBE_FORK]` akurat mengenali injeksi Goldberg tanpa false negative.
- [x] Shortcut `.desktop` dapat dibuat langsung dari antarmuka TUI via tombol `Ctrl-D`.
- [x] `make lint` dan `make test` menghasilkan exit code 0 (147/147 passed).
- [x] Menu TUI `gamectl` bersih tanpa entri duplikat.
