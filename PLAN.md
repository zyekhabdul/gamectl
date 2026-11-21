# WORK PACKET 27: PLATFORM-SPECIFIC DEPOT FILTERING & MULTI-OS DOWNLOAD ARCHITECTURE

- Track: Maintenance / Downloader Optimization / Platform Filtering / Zero-Bloat
- **Status**: IN PROGRESS [3/4 CHUNKS EXECUTED]
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

### [x] Chunk 27.02: Post-Download Linux ELF Permission Hook (`src/steam/30_downloader.sh`) [VERIFIED]
- Implementasi `ensure_linux_binaries_executable()` dengan bounded scan (`-maxdepth 4`, exclude media/pak) dan verifikasi magic signature `\x7fELF` (`7f454c46`).
- Pastikan biner Linux ELF yang diunduh otomatis mendapatkan `chmod +x` jika target OS adalah `linux` atau `all`.
- Verifikasi: Test contracts `test_ensure_linux_binaries_executable_contract` dan `test_download_game_elf_chmod_hook_contract` pass (Exit 0).

### [x] Chunk 27.03: Harmonisasi TUI Dashboard (`src/tui/70_dashboard.sh`) [VERIFIED]
- Pastikan parameter `--os "$target_os"` diteruskan secara konsisten di `search_steam`, `unlock_interactive`, dan `library_menu` missing binary bridge.
- Verifikasi: Test contract `test_tui_os_parameter_forwarding_contract` pass (Exit 0).

### [ ] Chunk 27.04: Verifikasi Final & Ratifikasi
- Kompilasi `bin/gamectl` via `./scripts/build.sh`.
- Jalankan `make lint`, `./scripts/build.sh --check`, `tests/test_depot_filter.sh`, dan `tests/test_cli.sh`.

---

## 2. Kriteria Selesai (DoD)
- [x] `gamectl download <appid> --os linux` hanya mengunduh depot Linux + shared.
- [x] `gamectl download <appid> --os windows` hanya mengunduh depot Windows + shared.
- [x] Default tanpa flag pada Linux memilih depot Linux jika ada.
- [x] Biner Linux ELF otomatis executable (`chmod +x`).
- [ ] Semua tes harness exit code 0.
