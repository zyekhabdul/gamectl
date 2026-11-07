# WORK PACKET 14: STANDALONE DEPOT DOWNLOADER HARDENING, PACKAGING & WINDOWS EXPANSION [ACTIVE]

## 1. Objective & Technical Scope
Memperkuat arsitektur Standalone Steam CDN Depot Downloader (`gamectl-depot-dl`), memperbaiki 5 defek temuan audit pasca-implementasi, menyelaraskan instalasi dan build system, serta mengekspansi kompatibilitas engine ke target Windows:
1. **Source Code Tree Consolidation**: Memindahkan source Rust dari repositori referensi luar ke dalam repositori `gamectl` (`crates/depot-dl/` atau `src/rust/depot-dl/`) bersama script reproducible build `scripts/build-depot-dl.sh`.
2. **Packaging & Installer Synchronization**: Memperbarui `install.sh`, `Makefile`, dan `packaging/debian/build-deb.sh` agar menyertakan `bin/gamectl-depot-dl` ke `$BIN_DIR` (`~/.local/bin/` / `/usr/bin/`).
3. **Co-located Binary Path Resolution**: Menambahkan `"$script_dir/gamectl-depot-dl"` ke fungsi `resolve_depot_dl_bin` di `src/steam/30_downloader.sh`.
4. **Resilient Lua Manifest Regex**: Memperbarui regex `addappid` agar mendukung petik tunggal (`'`) dan ganda (`"`), serta variasi whitespace/tab.
5. **Terminal I/O Progress Throttling**: Mengoptimalkan progress event pada Rust binary agar tidak mencetak setiap file individual (`[FILE]`) yang memicu buffer flooding pada game puluhan ribu file.
6. **Windows Path Sanitization & NTFS Limits**: Menambahkan normalisasi path separator POSIX-ke-Windows (`/` ke `\`), sanitasi karakter terlarang NTFS (`: * ? " < > |`), dan support `\\?\` prefix untuk bypass `MAX_PATH`.
7. **Windows Cross-Compilation**: Mengompilasi binary release `bin/gamectl-depot-dl.exe` dengan target `x86_64-pc-windows-gnu`.
8. **Regression Verification Harness**: Memperbarui `tests/test_cli.sh`, memastikan 100% assertions lulus dengan exit code 0.

---

## 2. Granular Technical Execution Plan (Work Packet 14)

### Chunk 1: Source Code Tree Integration & Build Automation [DONE]
- Target Files: `crates/depot-dl/` (atau `src/rust/depot-dl/`), `scripts/build-depot-dl.sh`
- Runtutan Eksekusi Teknis:
  1. Buat direktori sub-crate `crates/depot-dl/` di repositori `gamectl`.
  2. Salin `src/bin/gamectl-depot-dl.rs` dan konfigurasi `Cargo.toml` dari repo referensi ke dalam `crates/depot-dl/`.
  3. Buat script automasi kompilasi `scripts/build-depot-dl.sh` untuk memproduksi binary release ke `bin/gamectl-depot-dl` secara reproducible.
- DoD: Source code Rust terintegrasi di repo `gamectl` dan dapat dikompilasi ulang secara mandiri.

### Chunk 2: Packaging & Installation Sync [DONE]
- Target Files: `install.sh`, `Makefile`, `packaging/debian/build-deb.sh`
- Runtutan Eksekusi Teknis:
  1. Perbarui `install.sh`: pasang/symlink `bin/gamectl-depot-dl` ke `$BIN_DIR` jika binary tersedia.
  2. Perbarui `Makefile`: sertakan `bin/gamectl-depot-dl` pada target `install` dan `uninstall`.
  3. Perbarui `packaging/debian/build-deb.sh`: sertakan binary ke paket `.deb`.
- DoD: Menjalankan `./install.sh` memasang kedua binary (`gamectl` dan `gamectl-depot-dl`) ke `$HOME/.local/bin`.

### Chunk 3: Co-located Binary Path Resolution [DONE]
- Target Files: `src/steam/30_downloader.sh`
- Runtutan Eksekusi Teknis:
  1. Tambahkan `"$script_dir/gamectl-depot-dl"` ke urutan teratas kandidat pencarian di `resolve_depot_dl_bin()`.
  2. Pastikan binary yang diletakkan di direktori yang sama dengan `gamectl` langsung terdeteksi tanpa relying on `$PATH`.
- DoD: Fungsi `resolve_depot_dl_bin` mendeteksi binary ketika diletakkan berdampingan di direktori custom manapun.

### Chunk 4: Resilient Lua Manifest Regex [DONE]
- Target Files: `src/steam/30_downloader.sh`
- Runtutan Eksekusi Teknis:
  1. Modifikasi regex `re_key` pada `src/steam/30_downloader.sh`:
     ```bash
     local re_key='addappid\([[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*[0-9]+[[:space:]]*,[[:space:]]*['\''"]([0-9a-fA-F]{64})['\''"]'
     ```
  2. Dukung format single-quote `'...'` dan double-quote `"..."` dari seluruh ragam provider manifest.
- DoD: Parser berhasil mengekstrak AES key baik dari format petik tunggal maupun ganda.

### Chunk 5: Rust CLI Terminal Output Throttling [DONE]
- Target Files: `crates/depot-dl/src/bin/gamectl-depot-dl.rs`
- Runtutan Eksekusi Teknis:
  1. Tambahkan flag `--quiet` / `-q` dan `--verbose` / `-v`.
  2. Pada mode default, nonaktifkan logging per-file individual (`[FILE] ...`).
  3. Pertahankan logging progress berbasis byte ter-throttle (`[PROGRESS] Transferred: ... MB`) dan ringkasan akhir (`[SUCCESS]`).
- DoD: Terminal I/O bersih dan throughput download tidak terhambat pada game dengan puluhan ribu file.

### Chunk 6: Windows Path Normalization & NTFS Sanitizer [DONE]
- Target Files: `crates/depot-dl/src/util.rs`
- Runtutan Eksekusi Teknis:
  1. Implementasikan fungsi sanitasi path Windows:
     - Ganti separator POSIX `/` dengan `\` pada platform Windows.
     - Sanitasi karakter ilegal NTFS: `:`, `*`, `?`, `"`, `<`, `>`, `|`.
     - Gunakan prefix `\\?\` untuk path absolut di Windows guna menghindari batas `MAX_PATH` 260 karakter.
- DoD: Logika sanitasi path teruji melalui unit test dan aman untuk dieksekusi di filesystem Windows.

### Chunk 7: Windows Cross-Compilation [DEFERRED TO WINDOWS BOOT]
- Target Files: `scripts/build-depot-dl.sh`, `bin/gamectl-depot-dl.exe`
- Status: Parameter `--target x86_64-pc-windows-gnu` dan mapping binary `.exe` sudah diimplementasikan di `scripts/build-depot-dl.sh`. Kompilasi binary `.exe` ditunda saat booting Windows (native toolchain) sesuai preferensi user untuk mencegah friksi toolchain mingw di Linux.
- DoD: Script build siap mengeksekusi target Windows.

### Chunk 8: Automated Regression Testing & Machine Verification [DONE]
- Target Files: `tests/test_cli.sh`, `scripts/build.sh`
- Runtutan Eksekusi Teknis:
  1. Tambahkan skenario pengujian di `tests/test_cli.sh`:
     - Test parsing Lua single-quote format.
     - Test co-located binary path contract.
     - Test dry-run installer verifikasi `gamectl-depot-dl`.
  2. Jalankan `./scripts/build.sh` untuk sinkronisasi `bin/gamectl`.
  3. Jalankan regression suite `./tests/test_cli.sh` (83 assertions).
  4. Buktikan Exit Code 0 dengan 0 failures / 0 skips.
- DoD: Seluruh 83 test assertions lulus dengan status Exit Code 0.

---

## 3. Matriks Milestone (Work Packet 14)
- [x] Chunk 1: Source Code Tree Integration & Build Automation [DONE]
- [x] Chunk 2: Packaging & Installation Sync [DONE]
- [x] Chunk 3: Co-located Binary Path Resolution [DONE]
- [x] Chunk 4: Resilient Lua Manifest Regex [DONE]
- [x] Chunk 5: Rust CLI Terminal Output Throttling [DONE]
- [x] Chunk 6: Windows Path Normalization & NTFS Sanitizer [DONE]
- [ ] Chunk 7: Windows Cross-Compilation [DEFERRED TO WINDOWS BOOT]
- [x] Chunk 8: Automated Regression Testing & Machine Verification [DONE]
