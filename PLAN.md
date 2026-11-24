# WORK PACKET 33: RELEASE READINESS HARDENING (REMOTE SYNC, PACKAGING & STANDALONE DEFAULTS)

- **Track**: Data Safety / Packaging Integrity / Sovereign Defaults / Static Analysis
- **Status**: COMPLETED [4/4 PACKETS]
- **Basis**: Temuan audit terbuka dari `docs/MAINTENANCE_AUDIT_2026-11-10.md` dan `docs/REVIEW_COMPLETED_TASKS_2026-11-12.md` yang terkonfirmasi masih aktif di `HEAD` (`f724d5d`).
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/runners/40_wrappers.sh`, `src/main.sh`, `scripts/build.sh`, `scripts/build-depot-dl.sh`, `packaging/debian/build-deb.sh`, `packaging/arch/PKGBUILD`, `packaging/arch/.SRCINFO`, `packaging/aur-git/PKGBUILD`, `packaging/aur-git/.SRCINFO`, `MANIFEST.in`, `Makefile`, `tests/test_cli.sh`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Masalah Empiris & Risiko Regresi yang Teridentifikasi

1. **Remote Sync (`src/runners/50_launcher.sh:754-890`)**:
   - Baris 804 & 862 mengapit `~` di dalam tanda kutip ganda (`"mkdir -p \"~/$rel_path\""`, `"[ -d \"~/$rel_path/saves\" ]"`), sehingga remote shell tidak mengekspansi `~` ke `$HOME`.
   - Exit code `ssh` (L804) dan `rsync` (L807, L881) tidak diperiksa: kegagalan transfer (`rsync` exit 23) tetap mengembalikan `0` dan mencetak `[VERIFIED]`.
   - Baris 876 menjalankan `mkdir -p "$sdir"` tanpa guard `[ "$is_dry_run" = false ]`, sehingga `--dry-run` tetap memutasi filesystem lokal.
   - `restore_save()` dan `pull_save_remote()` belum memeriksa apakah PID game terkait masih aktif di `active_games/*.info` (Chunk 25.03).
2. **Packaging & Build Freshness**:
   - `packaging/debian/build-deb.sh:7,26-27` membundel biner ELF x86-64 `bin/gamectl-depot-dl` ke paket `Architecture: all` dan `Depends:` belum mencantumkan `zip`.
   - `packaging/arch/PKGBUILD:7` dan `packaging/aur-git/PKGBUILD:6` mendeklarasikan `arch=('any')` padahal menginstal biner ELF native.
   - `pyproject.toml:64` hanya mendeklarasikan `bin/gamectl` (wheel `py3-none-any`), tetapi `MANIFEST.in:3` (`recursive-include src/gamectl_runner/bin *`) + `scripts/build.sh:91-92` + `scripts/build-depot-dl.sh:161-165` ikut menyalin ELF x86-64 ke dalam wheel.
   - `scripts/build-depot-dl.sh:72-80` (`--check`) hanya memeriksa keberadaan & bit executable biner, belum mengecek apakah source di `crates/depot-dl/` lebih baru dari `bin/gamectl-depot-dl`.
3. **Standalone Runner Default & Static Analysis**:
   - `get_compat_dir()` (`src/runners/40_wrappers.sh:298-310`) tetap fallback ke `$HOME/.local/share/Steam/compatibilitytools.d` pada mesin tanpa Steam (tidak selaras dengan `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`).
   - `Makefile:31-34` (`make lint`) hanya menjalankan `bash -n`; `shellcheck` belum terintegrasi sebagai gerbang opsional/strict.

---

## 2. Rencana Eksekusi Detail (Packet 33A - 33D)

### [x] Packet 33A: Remote Save Sync Hardening & Active-Game Save Guard
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Tambahkan SSoT `is_game_active_for_dir "$game_dir"` di `src/core/10_utils.sh` (ekspor di `src/main.sh`):
     - Canonicalize `$game_dir` (`realpath -m` / `cd && pwd`), iterasi `"$(get_runtime_dir)/active_games/"*.info`.
     - Baca `PID=` dan `DIR=`; bila `kill -0 "$pid" 2>/dev/null` aktif dan canonical `$DIR` sama dengan `$game_dir`, cetak `$pid` dan return `0`; selain itu return `1`.
  2. Pasang active-game guard:
     - Di `restore_save()` (`src/core/10_utils.sh:845+`): tolak dengan `[ERROR]` + return `1` bila `is_game_active_for_dir "$game_dir"` aktif sebelum menyentuh lock/saves.
     - Di `pull_save_remote()` (`src/runners/50_launcher.sh:817+`): tolak sebelum `backup_save`/`rsync` bila `is_dry_run=false` dan game aktif.
     - Di `sync_save_remote()` (`src/runners/50_launcher.sh:754+`): tolak bila `is_dry_run=false`, tidak ada `--force`, dan game aktif (mencegah upload save yang sedang ditulis).
  3. Perbaiki remote path resolution, quoting, dry-run, dan error propagation di `sync_save_remote()` & `pull_save_remote()`:
     - Pertahankan ekspresi normalisasi `rel_path="${canon_gdir#$HOME/}"` dan `rel_path="Games/$(basename "$canon_gdir")"` (wajib agar kontrak `tests/test_cli.sh:646-647` tetap hijau).
     - Tolak `$rel_path` yang mengandung newline/CR atau segmen `..`.
     - Ganti probe konektivitas `ssh ... exit` dengan pengambilan `$HOME` remote dalam 1 RTT:
       `remote_home=$(ssh -q -o ConnectTimeout=2 -o BatchMode=yes "$rhost" 'printf %s "$HOME"' 2>/dev/null)` (gagal/kosong -> return `1`).
     - Susun `remote_base="${remote_home%/}/${rel_path}"` dan `remote_saves="${remote_base}/saves"`; gunakan `printf -v q_base '%q' "$remote_base"` / `printf -v q_saves '%q' "$remote_saves"` untuk perintah `ssh` (`mkdir -p -- $q_base`, `test -d $q_saves`).
     - Gunakan flag `-s` (`--protect-args`) pada `rsync` (`rsync -s "${rsync_opts[@]}" ...`) agar spasi/kutipan pada judul game tidak dievaluasi remote shell.
     - Periksa exit code `ssh mkdir` dan `rsync` di kedua fungsi; hanya cetak `[VERIFIED]` bila seluruh tahap sukses.
     - Di `pull_save_remote()`: jalankan `mkdir -p "$sdir"` HANYA saat `[ "$is_dry_run" = false ]` (pada `--dry-run` tanpa `$sdir`, jangan buat direktori lokal).
- **Definition of Done (DoD)**:
  - Judul game berspasi dan berkutipan (`My "Test" Game`) berhasil dicek/disinkronkan pada fake remote shell nyata (`sh -c`) dengan `$HOME` remote teresolusi.
  - Kegagalan `ssh mkdir` atau `rsync` (mis. exit 23) mengembalikan exit non-zero dan 0 output `[VERIFIED]`.
  - `pull_save_remote --dry-run` pada direktori tanpa `saves/` tidak menciptakan folder `saves/`.
  - `restore_save` dan `pull_save_remote` menolak mutasi saat PID game masih hidup di `active_games/`.

### [x] Packet 33B: Packaging Architecture Integrity & `build-depot-dl.sh` Freshness Gate
- **Target Files**: `packaging/debian/build-deb.sh`, `packaging/arch/PKGBUILD`, `packaging/arch/.SRCINFO`, `packaging/aur-git/PKGBUILD`, `packaging/aur-git/.SRCINFO`, `MANIFEST.in`, `scripts/build.sh`, `scripts/build-depot-dl.sh`, `tests/test_cli.sh`
- **Langkah Teknis**:
  1. **`packaging/debian/build-deb.sh`**:
     - Deteksi `PKG_ARCH` secara akurat: bila `bin/gamectl-depot-dl` ikut dibundel, baca arsitektur ELF (`file -Lb` -> `x86-64` => `amd64`, `ARM aarch64` => `arm64`, fallback `dpkg --print-architecture`); hanya pakai `all` bila biner native tidak disertakan.
     - Tambahkan `zip` pada baris `Depends:` (`..., unzip, zip`).
     - Substitusi `Version: ${PKG_VER}` dan `Architecture: ${PKG_ARCH}` di `DEBIAN/control` (ubah `<< 'EOF'` menjadi `<< EOF`).
  2. **`packaging/arch/PKGBUILD` & `packaging/aur-git/PKGBUILD`**:
     - Ubah `arch=('any')` menjadi `arch=('x86_64')` agar konsisten dengan biner ELF x86-64 yang diinstal, lalu regenerasi `.SRCINFO` via `make pkg-aur`.
  3. **Pure Python Wheel (`MANIFEST.in`, `scripts/build.sh`, `scripts/build-depot-dl.sh`)**:
     - Ubah `MANIFEST.in` baris 3 dari `recursive-include src/gamectl_runner/bin *` menjadi `include src/gamectl_runner/bin/gamectl`.
     - Hapus penyalinan ELF `gamectl-depot-dl` ke `src/gamectl_runner/bin/` di `scripts/build.sh:91-93` dan `scripts/build-depot-dl.sh:160-172` agar wheel `py3-none-any` benar-benar pure-script lintas arsitektur.
  4. **Freshness Gate `scripts/build-depot-dl.sh --check`**:
     - Selain `[ -f "$bin" ] && [ -x "$bin" ]`, periksa apakah ada file di `crates/depot-dl/Cargo.toml`, `crates/depot-dl/Cargo.lock`, atau `crates/depot-dl/src/` yang mtime-nya lebih baru dari `$OUTPUT_DIR/$OUTPUT_NAME` (`find ... -newer`). Jika basi, cetak `[FAIL]` dengan instruksi rebuild dan exit `1`.
  5. **Pitfall Kontrak Tes Eksisting (`tests/test_cli.sh:470-478`)**:
     - Perkuat `test_debian_packaging_validation` dari pola lama `gamectl_*_all.deb` menjadi pengecekan `gamectl_*_${expected_arch}.deb`, verifikasi `Architecture: ${expected_arch}`, dan verifikasi `Depends:.*zip`.
- **Definition of Done (DoD)**:
  - `.deb` yang dibangun memiliki nama & field `Architecture:` sesuai ELF (`amd64`), serta `Depends:` mencantumkan `zip`.
  - `packaging/arch/{PKGBUILD,.SRCINFO}` dan `packaging/aur-git/{PKGBUILD,.SRCINFO}` sinkron dengan `arch = x86_64`.
  - `scripts/build.sh` tidak lagi menaruh ELF x86-64 di `src/gamectl_runner/bin/`.
  - `scripts/build-depot-dl.sh --check` gagal (exit 1) bila file source Rust lebih baru daripada `bin/gamectl-depot-dl`, dan lulus (exit 0) saat sinkron.

### [x] Packet 33C: Standalone-First `get_compat_dir()` & Optional `shellcheck` Lint Gate
- **Target Files**: `src/runners/40_wrappers.sh`, `Makefile`
- **Langkah Teknis**:
  1. **`get_compat_dir()` (`src/runners/40_wrappers.sh:298-310`)**:
     - Tambahkan dukungan override eksplisit `GAMECTL_RUNNER_DIR` (jika disetel).
     - Jika Steam root ditemukan (`[ -n "$s_dyn_root" ] && [ -d "$s_dyn_root" ]`), kembalikan `"$s_dyn_root/compatibilitytools.d"`; jika `[ -d "$HOME/.steam/root" ]`, kembalikan `"$HOME/.steam/root/compatibilitytools.d"`.
     - Bila Steam tidak terpasang, fallback ke `${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runners` (bukan menciptakan `$HOME/.local/share/Steam/compatibilitytools.d`).
     - **Pitfall Kontrak Tes**: Cek Test 18 & Test 20 di `tests/test_remediation.sh` yang menguji `proton_install` — pastikan direktori target di kedua tes mengikuti perilaku `get_compat_dir()`.
  2. **`Makefile` (`lint:` target)**:
     - Pertahankan `bash -n` wajib untuk seluruh modul.
     - Tambahkan pass `shellcheck` opsional: bila `command -v shellcheck >/dev/null 2>&1`, jalankan `shellcheck -S error src/*.sh src/*/*.sh scripts/*.sh`; bila tidak terpasang di host, cetak `[INFO] shellcheck not found (syntax-only lint passed)` kecuali `STRICT_LINT=1` (yang harus exit 1).
- **Definition of Done (DoD)**:
  - Pada lingkungan tanpa direktori Steam, `get_compat_dir()` mengembalikan `${XDG_DATA_HOME:-$HOME/.local/share}/gamectl/runners`.
  - `make lint` lulus Exit 0 baik saat `shellcheck` ada maupun tidak ada, dan `STRICT_LINT=1 make lint` gagal deterministik bila `shellcheck` absen.

### [x] Packet 33D: Regression Contracts, Bundle Sync & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `bin/gamectl`
- **Langkah Teknis**:
  1. Tambahkan Tests 21-23 di `tests/test_remediation.sh`:
     - **Test 21 (33A)**: Uji `sync_save_remote` & `pull_save_remote` memakai mock `ssh` yang mengeksekusi remote command (`sh -c`) di temp `REMOTE_HOME` dengan judul berspasi/kutip; uji propagasi error `rsync` (exit 23 -> rc != 0 & tanpa `[VERIFIED]`); uji `pull_save_remote --dry-run` tidak membuat `saves/`; uji `restore_save` & `pull_save_remote` ditolak saat PID hidup terdaftar di `active_games/`.
     - **Test 22 (33B)**: Uji `build-depot-dl.sh --check` menolak biner basi (via temp copy/mtime) dan meluluskan biner segar; uji `MANIFEST.in` & `scripts/build.sh` tidak menyalin ELF ke `src/gamectl_runner/bin/`; uji `.deb` `Architecture:` + `Depends: zip` dan `.SRCINFO` `arch = x86_64`.
     - **Test 23 (33C)**: Uji `get_compat_dir()` tanpa Steam mengembalikan `$XDG_DATA_HOME/gamectl/runners` dan `STRICT_LINT=1 make lint` gagal bila `shellcheck` tidak ada di `PATH`.
  2. Kompilasi bundle via `./scripts/build.sh` dan validasi `./scripts/build.sh --check`.
  3. Jalankan gerbang penuh:
     `make lint && make test && bash tests/test_depot_filter.sh && bash tests/test_hubcap.sh && python3 -m unittest tests/test_tui_safety.py tests/test_standalone_safety.py tests/test_save_safety.py && ./scripts/build-depot-dl.sh --check`
- **Definition of Done (DoD)**:
  - Seluruh test suite (CLI 147+, Remediation 23/23, Ergonomics, Depot Filter, Hubcap, Python 42/42) lulus Exit Code 0.
  - `bin/gamectl` sinkron 100% (`./scripts/build.sh --check` Exit 0) dan `build-depot-dl.sh --check` Exit 0.
