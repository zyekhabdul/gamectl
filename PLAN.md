# WORK PACKET 10.5: TUI MODALITY UNIFICATION & STEAM ENTITLEMENT SEMANTICS [ACTIVE]

## 1. Objective & Technical Scope
Eliminate modality thrashing and screen flicker caused by raw shell `read -p` prompts and numbered transitions. Standardize the TUI around continuous alternate-screen modal action palettes. Reclassify the shallow and misleading term "[Unlock Steam DLC]" into its true technical utility: "[Steam Entitlement & ACF] Adopt files, Steam Input & Shaders (Full DLC)".

Scope of Work:
1. **TUI Modality Unification (`src/tui/70_dashboard.sh`)**: Replace raw `echo` and `read -p` numbered prompts (`1-5`, `1-6`) with TokyoNight-styled modal `fzf` action sheets, preserving the alternate screen buffer (`tput smcup`) without screen clears or cursor desync.
2. **Entitlement Engine & ACF Nomenclature (`src/steam/30_downloader.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`)**: Redefine the entitlement engine from a superficial DLC unlocker to an industrial-grade Steam asset adoption system (zero-download file adoption, community Steam Input mapping, Valve CDN Vulkan shader pre-caching, and base-game DLC activation).
3. **Ergonomic Direct Keybindings (`src/tui/70_dashboard.sh`)**: Integrate direct catalog hotkeys (`Ctrl-A` for All-in-One, `Ctrl-U` for Steam Entitlement, `Ctrl-S` for Standalone, `Ctrl-D` for Live Stream, `Enter` for Action Palette) to enable instant execution without sub-menu friction.
4. **Verification & Documentation Harmonization**: Update CLI contracts in `tests/test_cli.sh`, synchronize `bin/gamectl` via `./scripts/build.sh`, and update documentation in `README.md` and `DEVELOPMENT.md`.

---

## 2. Granular Technical Execution Plan (Active Packet)

### Chunk 1: TUI Modal Action Palette & Query Input Refactor [DONE] (`07501fd`)
- Target File: `src/tui/70_dashboard.sh`
- Runtutan Eksekusi Teknis:
  1. Refactor query input pada `search_steam`: ganti raw `read -r query` dengan modal picker atau prompt input yang aman tanpa merusak buffer terminal.
  2. Refactor seleksi aksi untuk game yang sudah terpasang (`INSTALLED`): hilangkan `read -r -p "Select action [1-5]: "`, ganti dengan modal `fzf` bertajuk `Action Palette: <Game Name>` dengan opsi:
     - Launch Game Directly
     - Inject GBE Fork Only (Standalone ./saves & DLC.txt)
     - Inject GBE + Sync Steam Client (All-in-One Full DLC)
     - Sync to Steam Client Entitlement Only (ACF & Steam Input)
     - Cancel / Return
  3. Refactor seleksi aksi untuk game belum terpasang (`NOT INSTALLED`): hilangkan `read -r -p "Select package [1-6]: "`, ganti dengan modal `fzf` Action Palette dengan opsi:
     - [All-in-One] Download + Inject GBE + Sync Steam (Background)
     - [All-in-One] Download + Inject GBE + Sync Steam (Live Stream)
     - [Standalone] Download + Inject GBE only (Steam-free)
     - [Steam Entitlement & ACF] Adopt files, Steam Input & Shaders (Full DLC)
     - [Raw Download] Download raw depot assets only
     - Cancel / Return
  4. Hapus seluruh prompt pasif `read -r -p "Press [ENTER] to continue..."` dan gantikan dengan transisi status kembali ke catalog atau dashboard.

### Chunk 2: Entitlement Engine Nomenclature & ACF Semantics Overhaul [DONE] (`efce9fd`)
- Target Files: `src/tui/70_dashboard.sh`, `src/steam/30_downloader.sh`, `src/main.sh`
- Runtutan Eksekusi Teknis:
  1. Perbarui Master Dashboard Hub (`dashboard_menu` di `src/tui/70_dashboard.sh`): ubah item `[04] UNLOCK STEAM (DLC)` menjadi `[04] STEAM ENTITLEMENT & ACF  Adopt files, Steam Input & shaders (Full DLC)`.
  2. Perbarui fungsi `unlock_game` di `src/steam/30_downloader.sh`: ubah teks banner dari `STEAM ZERO-DOWNLOAD UNLOCK (FULL DLC)` menjadi `STEAM ENTITLEMENT & ACF ADOPTION ENGINE`, sertakan deskripsi adopsi ACF dan Steam Input.
  3. Refactor `unlock_interactive` di `src/steam/30_downloader.sh`: hilangkan raw `clear` dan `read -p`, sediakan validasi numeric AppID yang bersih tanpa screen flashing.
  4. Perbarui CLI command dispatcher di `src/main.sh`: tambahkan alias deskriptif `entitle` dan `adopt-steam` di samping `unlock`, serta perbarui pesan help CLI.

### Chunk 3: Catalog Direct Action Shortcuts & Ergonomic Hotkeys
- Target File: `src/tui/70_dashboard.sh`
- Runtutan Eksekusi Teknis:
  1. Tambahkan binding `--bind` pada `fzf` Steam Catalog:
     - `ctrl-a`: Eksekusi langsung Download + Inject GBE + Sync Steam (Background).
     - `ctrl-u`: Eksekusi langsung Steam Entitlement & ACF adoption.
     - `ctrl-s`: Eksekusi langsung Standalone download.
     - `ctrl-d`: Eksekusi langsung Live Stream download.
  2. Tampilkan petunjuk hotkey pada header `fzf` catalog agar terbaca jelas oleh pengguna keyboard-centric (`Enter: Actions │ Ctrl-A: All-in-One │ Ctrl-U: Entitle │ Ctrl-S: Standalone │ Esc: Back`).
  3. Tangani multi-line output parsing dari `fzf` yang mengembalikan keybinding terpilih.

### Chunk 4: Machine Verification, Automated Regression Suite & Documentation
- Target Files: `tests/test_cli.sh`, `README.md`, `DEVELOPMENT.md`
- Runtutan Eksekusi Teknis:
  1. Tambahkan unit assertions pada `tests/test_cli.sh` untuk memverifikasi alias baru `gamectl entitle` dan `gamectl adopt-steam`.
  2. Perbarui dokumentasi di `README.md` dan `DEVELOPMENT.md` mengenai fungsi sebenarnya dari Steam Entitlement & ACF Adoption (adopsi file lokal, Steam Input gyro/touchpad, shader pre-caching).
  3. Jalankan kompilasi `./scripts/build.sh`, verifikasi integritas biner via `./scripts/build.sh --check`, dan pastikan seluruh 42+ test assertions lulus dengan exit code 0.

---

## 3. Matriks Milestone Sebelumnya (Work Packet 10 - Completed)
- [x] Chunk 1: Core, Runner & Diagnostics Internationalization (`82e3a84`) [DONE]
- [x] Chunk 2: Steam Engine & Interactive Dashboard TUI Internationalization (`17d3346`) [DONE]
- [x] Chunk 3: Legal Shielding, Neutral Nomenclature & Documentation Overhaul (`60d01f2`) [DONE]
- [x] Chunk 4: Turnkey Piped Web Installer & Arch Linux AUR Packaging (`139cb7d`) [DONE]
- [x] Chunk 5: Steam Deck shortcuts.vdf Non-Steam Integration Engine (`d5e670f`) [DONE]
- [x] Chunk 6: SteamGridDB & Steam CDN Artwork Pipeline for Game Mode (`07344fc`) [DONE]
- [x] Checkpoint Verifikasi: 42/42 tests passing (`d164e46`) [DONE]