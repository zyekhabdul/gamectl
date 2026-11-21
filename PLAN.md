# WORK PACKET 27: PLATFORM-SPECIFIC DEPOT FILTERING & MULTI-OS DOWNLOAD ARCHITECTURE

- Track: Maintenance / Downloader Optimization / Platform Filtering / Zero-Bloat
- **Status**: IN PROGRESS [1/2 CHUNKS EXECUTED]
- **Tujuan**: Memungkinkan filter OS saat download (`--os linux|windows|macos|all`) agar hemat bandwidth & disk, serta default otomatis ke Native Linux jika tersedia di host Linux.

---

## 1. Implementasi Minimalis (YAGNI)

### [x] Chunk 27.01: Parser Flag & Filter Depot OS (`src/steam/30_downloader.sh`) [VERIFIED]
- Tangkap flag `--os <linux|windows|macos|all>` dan `--os=*` di `download_game()`.
- Validasi nilai target OS secara case-insensitive.
- Ekstrak mapping depot ke `oslist` via `parse_depot_os_map()` dari staging manifest JSON.
- Filter depot cerdas: auto-detect Linux native jika ada, fallback Windows untuk Proton/Wine, keep shared/universal assets.
- Circuit breaker: tolak unduhan jika seluruh depot terfilter keluar dengan diagnostik jelas.
- Verifikasi: Test contracts `test_parse_depot_os_map_contract` dan `test_download_game_os_filter_contracts` pass (137/137 CLI contracts exit 0).

### [ ] Chunk 27.02: Izin Eksekusi Biner Linux & Harmonisasi TUI
- Pastikan biner Linux ELF yang diunduh otomatis mendapatkan `chmod +x`.
- Harmonisasi penerusan flag `--os` di TUI dashboard (`src/tui/70_dashboard.sh`).

### [ ] Chunk 27.03: Verifikasi Final & Ratifikasi
- Kompilasi `bin/gamectl` via `./scripts/build.sh`.
- Jalankan `make lint`, `./scripts/build.sh --check`, dan `tests/test_cli.sh`.

---

## 2. Kriteria Selesai (DoD)
- [x] `gamectl download <appid> --os linux` hanya mengunduh depot Linux + shared.
- [x] `gamectl download <appid> --os windows` hanya mengunduh depot Windows + shared.
- [x] Default tanpa flag pada Linux memilih depot Linux jika ada.
- [ ] Biner Linux ELF otomatis executable (`chmod +x`).
- [ ] Semua tes harness exit code 0.
