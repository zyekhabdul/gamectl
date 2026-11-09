# WORK PACKET 21: CI/CD AUTOMATION, RELEASE INTEGRITY & SAVEGAME RESILIENCE HARDENING

**Track**: Maintenance / CI/CD & Testing Harness  
**Status**: IN PROGRESS  
**Branch**: `main`  
**Max Chunks**: 4 Chunks (Active Packet <= 10)  
**Target Files**: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `tests/test_cli.sh`, `PLAN.md`

---

## 1. Objective & Technical Scope
Mengatasi temuan audit eksternal yang valid untuk memperkuat continuous integration, keandalan rilis binary, dan proteksi integritas savegame pengguna:
1. **Savegame Snapshot & Rotation Integrity Test Harness**: Menambahkan unit test deterministik untuk memvalidasi rotasi rolling 3-slot (`slot1` -> `slot2` -> `slot3`) pada `backup_save()`, memastikan zero data-loss pada progres savegame pengguna.
2. **GitHub Actions Continuous Integration Pipeline (`.github/workflows/ci.yml`)**: Mengimplementasikan workflow CI otomatis untuk setiap push dan pull request pada branch `main` yang menjalankan linting sintaks bash, sinkronisasi bundle, pengujian Rust crate (`depot-dl`), dan 115+ test assertions CLI harness.
3. **Automated GitHub Release & Checksums Pipeline (`.github/workflows/release.yml`)**: Membangun workflow perilisan otomatis saat tag `v*` di-push, yang mengompilasi binary mandiri `gamectl`, binary Rust `gamectl-depot-dl`, Debian package (`.deb`), serta meng-generate file verifikasi integritas `SHA256SUMS`.
4. **Deterministic Machine Gate**: Menambahkan verifikasi regresi untuk file workflow, menjalankan build bundle, dan mengeksekusi test suite dengan Exit Code 0.

---

## 2. Granular Technical Execution Plan (Todolist)

### [x] Chunk 1: Savegame Snapshot & 3-Slot Rotation Integrity Test Harness [VERIFIED]
- **Target Files**: `tests/test_cli.sh`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan fungsi test `test_savegame_snapshot_rotation_contract()`:
     - Buat direktori game dummy dengan folder `saves/` dan file `game.sav` berisi token versi 1.
     - Panggil `backup_save "$t_game" true` -> verifikasi slot1 tercipta dan isinya identik dengan versi 1.
     - Mutasi file `game.sav` dengan token versi 2, panggil `backup_save "$t_game" true` -> verifikasi slot1 berisi versi 2 dan slot2 berisi versi 1.
     - Mutasi file `game.sav` dengan token versi 3, panggil `backup_save "$t_game" true` -> verifikasi slot1=v3, slot2=v2, slot3=v1.
     - Mutasi file `game.sav` dengan token versi 4, panggil `backup_save "$t_game" true` -> verifikasi slot1=v4, slot2=v3, slot3=v2, dan total slot tetap tepat 3 (rolling cap).
     - Bersihkan direktori temporary.
  2. Daftarkan pengujian ke runner test harness.
- **Definition of Done (DoD)**:
  - Pengujian rotasi savegame lulus 100% dengan Exit Code 0 tanpa error, membuktikan proteksi progres pemain aktif.

### [x] Chunk 2: GitHub Actions Automated CI Pipeline (`.github/workflows/ci.yml`) [VERIFIED]
- **Target Files**: `.github/workflows/ci.yml`
- **Runtutan Eksekusi Teknis**:
  1. Buat `.github/workflows/ci.yml`:
     - Triggers: `push` ke `main`, `pull_request` ke `main`, dan `workflow_dispatch`.
     - Matrix OS: `ubuntu-latest`.
     - Setup step: Checkout repository (`actions/checkout@v4`).
     - Rust toolchain: Install stable rust toolchain untuk crate `depot-dl`.
     - System packages: Install `fzf`, `jq`, `file`, `rsync`, `zip`, `unzip`, `p7zip-full`.
     - Lint step: `make lint` (Bash -n pada seluruh modul sumber dan bundler).
     - Bundle synchronization step: `./scripts/build.sh --check`.
     - Rust test step: `cargo test --manifest-path crates/depot-dl/Cargo.toml`.
     - CLI regression step: `./tests/test_cli.sh`.
  2. Validasi sintaks YAML menggunakan parser Python lokal.
- **Definition of Done (DoD)**:
  - File `.github/workflows/ci.yml` valid secara sintaks YAML dan mencakup seluruh layer uji otomatis.

### [x] Chunk 3: GitHub Actions Release & Checksum Generation Pipeline (`.github/workflows/release.yml`) [VERIFIED]
- **Target Files**: `.github/workflows/release.yml`
- **Runtutan Eksekusi Teknis**:
  1. Buat `.github/workflows/release.yml`:
     - Triggers: `push` pada tags `v*`.
     - Permissions: `contents: write`.
     - Build steps:
       - Kompilasi `bin/gamectl` via `./scripts/build.sh`.
       - Kompilasi `bin/gamectl-depot-dl` via `cargo build --release --manifest-path crates/depot-dl/Cargo.toml`.
       - Build Debian package via `packaging/debian/build-deb.sh`.
     - Checksum step:
       - Generate `sha256sum gamectl gamectl-depot-dl *.deb > SHA256SUMS`.
     - Release step:
       - Upload seluruh release assets (`gamectl`, `gamectl-depot-dl`, package `.deb`, dan `SHA256SUMS`) ke GitHub Releases via `softprops/action-gh-release@v2`.
  2. Validasi sintaks YAML menggunakan parser Python lokal.
- **Definition of Done (DoD)**:
  - File `.github/workflows/release.yml` terverifikasi secara sintaks dan mengotomatiskan rilis binary bertag dengan SHA256 checksums.

### [ ] Chunk 4: Regression Test Suite Expansion, Rebuild & Machine Gate
- **Target Files**: `tests/test_cli.sh`, `bin/gamectl`, `PLAN.md`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan pengujian verifikasi schema workflow CI/CD di `tests/test_cli.sh`.
  2. Jalankan `make build` untuk memastikan bundle sinkron.
  3. Jalankan `make lint`, `make test`, dan `cargo test`.
  4. Perbarui status checklist `[x]` pada `PLAN.md` menjadi `COMPLETED [VERIFIED]`.
- **DoD**:
  - Seluruh skenario baru lulus dengan Exit Code 0 (total >= 116 assertions).
  - Standalone bundle `bin/gamectl` tersinkronisasi 100%.

---

## 3. Verification Matrix

| Komponen | Perintah Uji | Kriteria Sukses (DoD) |
| :--- | :--- | :--- |
| **Savegame Rolling Contract** | `./tests/test_cli.sh` | Rotasi slot1 -> slot2 -> slot3 terbukti atomik dengan cap 3 slot. |
| **CI Workflow Schema** | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` | YAML valid, steps lengkap. |
| **Release Workflow Schema** | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"` | YAML valid, SHA256SUMS step terpasang. |
| **Machine Gate** | `make lint && make test` | 0 syntax errors, 116+ test assertions lulus dengan Exit Code 0. |
