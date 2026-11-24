# WORK PACKET 32: TRANSACTIONAL SAFETY, SUPPLY-CHAIN INTEGRITY & NETWORK/RUNNER HARDENING

- **Track**: Atomic File Integrity / Archive Supply-Chain Security / Runner & Network Hardening
- **Status**: COMPLETED [4/4 PACKETS]
- **Basis**: Audit empiris lanjutan codebase `src/` (`sed -i` injection, raw JSON heredoc, streaming `proton_install` tanpa SHA-512/staging, Zip-Slip symlink gap, unbounded `curl` Store Search, drift `list_runner_dirs`, dan duplikasi fallback `30_downloader.sh`).
- **Target Files**: `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/steam/25_identity.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/diagnostics/60_doctor.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Rencana Eksekusi Detail (Packet 32A - 32D)

### [x] Packet 32A: Atomic & Injection-Safe File Mutations (Eliminasi `sed -i` & JSON Injection)
- **Target Files**: `src/core/10_utils.sh`, `src/steam/25_identity.sh`, `src/runners/50_launcher.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Tambahkan dua helper atomik SSoT di `src/core/10_utils.sh` dan ekspor di `src/main.sh`:
     - `atomic_set_kv_file "$file" "$key" "$val" [sep]`: perbarui key-value secara deterministik memakai `awk -v` + `mktemp` + `mv -f`, kebal karakter khusus (`|`, `/`, `&`, `\`, `"`) dan tanpa mutasi parsial saat crash.
     - `atomic_prepend_line "$file" "$line"`: tambahkan baris di awal file via `mktemp` + `mv -f` (tetap bekerja pada file 0-byte dan menjaga permission `0600` bila file baru).
  2. Gantikan seluruh 6 titik `sed -i` non-atomik:
     - `src/core/10_utils.sh:1832` (`set_config_value`)
     - `src/steam/25_identity.sh:192,197` (`set_id`)
     - `src/runners/50_launcher.sh:269` (`setup_onlinefix`)
     - `src/steam/30_downloader.sh:908,2262` (`addappid(...)` pada `stplug-in/*.lua`)
  3. Gantikan konstruksi heredoc `latest.json` pada `install_game_fix()` (`src/steam/35_fixes.sh:395-403`) dengan `jq -n --arg ...` yang ditulis secara atomik lewat `mktemp` + `mv -f` agar judul fix berisi tanda kutip `"` atau backslash `\` tidak merusak JSON backup.
- **Definition of Done (DoD)**:
  - `grep -rn "sed -i" src/` mengembalikan 0 pemanggilan pada mutasi config/INI/Lua.
  - Nilai persona / config yang mengandung `/`, `|`, `&`, `\`, serta judul fix berisi `"` tersimpan utuh dan valid JSON (`jq empty`).

### [x] Packet 32B: Supply-Chain & Archive Security Hardening (`tar` / `zip`)
- **Target Files**: `src/core/10_utils.sh`, `src/runners/40_wrappers.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Tambahkan SSoT `audit_zip_safety "$zip_file"` di `src/core/10_utils.sh` (ekspor di `src/main.sh`) yang memvalidasi:
     - Integritas `unzip -tq`
     - Penolakan path traversal (`..`), absolute path (`/`), backslash/drive letter (`\`, `C:`)
     - Penolakan entri **symlink di dalam ZIP** (`unzip -Z` dengan mode awal `l`)
  2. Gunakan `audit_zip_safety` pada `validate_manifest_zip()` (`src/steam/30_downloader.sh:160`) dan `install_game_fix()` (`src/steam/35_fixes.sh:365`).
  3. Refactor `proton_install()` (`src/runners/40_wrappers.sh:460`) agar tidak langsung `curl | tar -xz` ke direktori live:
     - Unduh tarball ke direktori staging `mktemp -d` (dengan `trap` cleanup + `--connect-timeout 15`).
     - Bila release GitHub menyediakan aset `.sha512sum`, unduh dan verifikasi `sha512sum -c`.
     - Audit daftar path tarball (`tar -tzf`) sebelum ekstraksi agar bebas path traversal (`..` / `/`).
     - Ekstrak ke direktori staging lalu pindahkan secara atomik (`mv`) ke direktori runner target hanya setelah seluruh verifikasi lulus.
- **Definition of Done (DoD)**:
  - Arsip ZIP berisi symlink atau `../` ditolak oleh `audit_zip_safety` sebelum ekstraksi.
  - `proton_install()` menolak tarball bila checksum `.sha512sum` tidak cocok atau tarball rusak tanpa meninggalkan direktori runner setengah jadi.

### [x] Packet 32C: Runner Directory SSoT, Network Timeout Guard & Deduplikasi `30_downloader.sh`
- **Target Files**: `src/runners/40_wrappers.sh`, `src/diagnostics/60_doctor.sh`, `src/steam/30_downloader.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Ekstrak SSoT `list_runner_dirs()` di `src/runners/40_wrappers.sh` (ekspor di `src/main.sh`) yang mencacah `${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runners` + direktori Steam `compatibilitytools.d`, lalu gunakan secara seragam di `find_runner()`, `proton_list()`, `proton_remove()`, dan `doctor_audit()`.
  2. Tambahkan `--max-time 15` pada 3 pemanggilan `curl` Store Search (`src/tui/70_dashboard.sh:1357,1464` dan `src/steam/30_downloader.sh:2528`) agar TUI/CLI tidak menggantung bila upstream macet pasca-TCP handshake.
  3. Bersihkan duplikasi fallback `strip_ansi`, `get_runtime_dir` (inkonsistensi `/tmp/gamectl-$UID`), dan `fetch_cached_json` di `src/steam/30_downloader.sh:1-50` dengan menyelaraskannya ke `src/core/10_utils.sh` (sambil tetap menjaga skrip aman bila di-`source` mandiri oleh suite test).
- **Definition of Done (DoD)**:
  - `gamectl proton-list`, `gamectl proton-remove`, `find_runner()`, dan `doctor_audit()` melihat runner standalone XDG maupun Steam secara konsisten.
  - Tidak ada pemanggilan `curl` Store Search tanpa `--max-time`.
  - Test yang meng-`source` `30_downloader.sh` secara langsung tetap berjalan dengan jalur runtime `get_runtime_dir` yang konsisten.

### [x] Packet 32D: Regression Contracts, Bundle Sync & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `bin/gamectl`
- **Langkah Teknis**:
  1. Tambahkan contract tests deterministik offline di `tests/test_remediation.sh` untuk Packet 32A, 32B, dan 32C:
     - Uji karakter spesial (`/`, `|`, `&`, `\`, `"`) pada `atomic_set_kv_file`, `set_id`, `setup_onlinefix`, dan `latest.json` via `jq`.
     - Uji penolakan ZIP bersymlink & path traversal oleh `audit_zip_safety`.
     - Uji staged `proton_install` (verifikasi SHA-512 lulus/gagal + zero partial dir) serta `list_runner_dirs`.
  2. Kompilasi bundle via `./scripts/build.sh` dan verifikasi `./scripts/build.sh --check`.
  3. Eksekusi gerbang verifikasi penuh: `make lint && make test && python3 -m unittest tests/test_tui_safety.py tests/test_standalone_safety.py tests/test_save_safety.py`.
- **Definition of Done (DoD)**:
  - `make lint` dan `make test` (`test_cli.sh`, `test_remediation.sh`, `test_tui_ergonomics.sh`) lulus Exit Code 0.
  - Seluruh Python safety suites (`42+` tests) lulus Exit Code 0.
  - `bin/gamectl` sinkron 100% dengan source (`./scripts/build.sh --check` Exit 0).
