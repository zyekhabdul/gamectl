# REMEDIATION WORK PACKET: STANDARDIZATION & MONKEY-PATCH ELIMINATION

**Track**: Maintenance / Refactoring & Zero-Bloat  
**Status**: COMPLETED [VERIFIED]  
**Max Chunks**: 5 Chunks (Active Packet <= 10)  
**Target Files**: `src/steam/35_fixes.sh`, `src/runners/40_wrappers.sh`, `src/steam/30_downloader.sh`, `bin/gamectl`

---

## 1. Objective & Technical Scope
Mengeliminasi seluruh sisa kode *monkey-patch*, proses fork non-standar, duplikasi konfigurasi, dan pemotongan nama file berspasi:
1. **Zip-Slip Hardening**: Mengganti pemotongan parsing tabel `unzip -l | awk '{print $4}'` dengan kanonikal `unzip -Z1` untuk mencegah kegagalan audit pada arsip dengan nama file berspasi.
2. **Config Parsing Consolidation**: Menyatukan loop parsing `wrappers` yang terduplikasi di `build_wrapper_command()`, mengeliminasi subshell `echo | tr` dan `echo | sed` menjadi native Bash parameter expansion (zero-fork).
3. **Directory Non-Empty Probing**: Mengganti `ls -A` yang mem-buffer seluruh nama file ke memori Bash dengan short-circuit probing (`find ... | head -n 1`) pada validasi folder game fisik.
4. **Subshell Fork Elimination**: Mengganti eksekusi binary eksternal `$(seq 1 50)` dengan native Bash brace expansion `{1..50}` pada loop polling shutdown Steam Client.
5. **Deterministic Verification**: Memastikan bundle `bin/gamectl` terkompilasi ulang dan 110/110 pengujian regresi lulus dengan Exit Code 0.

---

## 2. Granular Technical Execution Plan (Todolist)

### [x] Chunk 1: Standardize Zip-Slip Security Inspection via Canonical `unzip -Z1`
- **Target File**: `src/steam/35_fixes.sh` (L365)
- **Runtutan Eksekusi Teknis**:
  1. Buka `src/steam/35_fixes.sh` pada fungsi `install_game_fix()`.
  2. Ganti `unzip -l "$tmp_zip" | awk '{print $4}' | grep -E ...` dengan `unzip -Z1 "$tmp_zip" 2>/dev/null | grep -E ...`.
  3. Verifikasi regex path traversal tetap menangkap sequence traversal (`^/`, `^\.\./`, `/\.\./`, `^\.\.\\`, `\\\.\.\\`).
- **Definition of Done (DoD)**:
  - File arsip ZIP dengan nama berspasi (`mods/custom fix.dll`) diaudit utuh tanpa pemotongan kata.
  - Path traversal berbahaya tetap tertolak deterministik dengan exit code 1.

### [x] Chunk 2: Eliminate Duplicate Config Parsing in `build_wrapper_command` via Array Loop & Native Expansion
- **Target File**: `src/runners/40_wrappers.sh` (L1015-L1053)
- **Runtutan Eksekusi Teknis**:
  1. Di `build_wrapper_command()`, gabungkan blok parsing `$HOME/.config/gamectl/wrappers` dan `$gdir/.wrappers` ke dalam satu perulangan: `for w_cfg in "$HOME/.config/gamectl/wrappers" "$gdir/.wrappers"; do`.
  2. Hapus proses fork `echo "$k" | tr -d '[:space:]'` dan `echo "$v" | sed ...`.
  3. Terapkan pembersihan native parameter expansion:
     - `k="${k//[[:space:]]/}"`
     - `v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"`
     - `v="${v#\"}"; v="${v%\"}"`
  4. Pertahankan precedence: nilai di `$gdir/.wrappers` menimpa konfigurasi global.
- **Definition of Done (DoD)**:
  - Duplikasi 16 baris kode terhapus (-20 baris).
  - 0 subshell fork pada setiap baris konfigurasi yang dibaca.
  - Konfigurasi wrapper per-game tetap berfungsi 100%.

### [x] Chunk 3: Short-Circuit Directory Non-Empty Check (Eliminate `ls -A` Memory Buffer)
- **Target File**: `src/steam/30_downloader.sh` (L1581, L1583, L1595, L1602, L1775, L1782)
- **Runtutan Eksekusi Teknis**:
  1. Di `sync_steam()` dan `unlock_interactive()`, temukan seluruh pemanggilan `[ -n "$(ls -A "$dir" 2>/dev/null)" ]`.
  2. Ubah menjadi pemeriksaan short-circuit yang berhenti pada file pertama:
     `[ -n "$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]`.
  3. Pastikan penanganan path berspasi tetap aman.
- **Definition of Done (DoD)**:
  - Tidak ada alokasi buffer memori untuk ribuan nama file di memori shell.
  - Logika Ghost ACF Defense tetap aktif: folder kosong tidak akan dianggap sebagai instalasi valid.

### [x] Chunk 4: Native Bash Brace Expansion for Steam Shutdown Polling Loop (`{1..50}`)
- **Target File**: `src/steam/35_fixes.sh` (L537)
- **Runtutan Eksekusi Teknis**:
  1. Di `restart_steam_client()`, ganti `for _ in $(seq 1 50); do` menjadi `for _ in {1..50}; do`.
  2. Verifikasi waktu tunggu polling tetap 50 iterasi x 0.2s = 10 detik.
- **Definition of Done (DoD)**:
  - 0 eksekusi process fork `/usr/bin/seq`.
  - Polling graceful shutdown Steam Client tetap berjalan normal.

### [x] Chunk 5: Rebuild Standalone Bundle & Regression Verification Harness
- **Target Files**: `bin/gamectl`, `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Jalankan `make lint` untuk memvalidasi kepatuhan sintaks seluruh modul bash.
  2. Jalankan `make build` untuk mengompilasi bundler modular ke `bin/gamectl`.
  3. Jalankan `make test` untuk mengeksekusi seluruh 110 skenario pengujian regresi.
- **Definition of Done (DoD)**:
  - `make lint` mengembalikan Exit Code 0.
  - `make build` mensinkronkan `bin/gamectl` dengan modular sources.
  - `make test` mencatat 110/110 test assertions lulus dengan Exit Code 0.
