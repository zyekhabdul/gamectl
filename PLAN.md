# WORK PACKET 4: TUI UX INTEGRITY, ACTION KEYS ALIGNMENT & VISUAL STATE HARDENING

## 1. Objective & Scope
Memperbaiki 6 inkonsistensi visual, false-positive state, dan UX disconnect pada TUI `gamectl` agar seluruh informasi di panel preview, Action Keys, configurator, dan pencarian Steam 100% akurat, transparan, dan tidak menyesatkan pengguna.

---

## 2. Granular Chunks & Definition of Done (DoD)

### Chunk 1: ACTION KEYS Alignment & Keybinding Visibility [COMPLETED]
- **Target**: `bin/gamectl` (`preview_game()`)
- **DoD**:
  1. [x] Daftarkan `<CTRL-I>` ke dalam blok `ACTION KEYS:` pada panel kanan preview.
  2. [x] Berikan label dinamis berdasarkan status game:
     - Jika status `[GBE_FORK]`: `<CTRL-I> : Re-Inject / Update GBE Fork & Full DLC`
     - Jika status non-GBE: `<CTRL-I> : Inject GBE Fork (Bebas Steam, Portable Saves & LAN)`
  3. [x] Pastikan urutan tombol konsisten dengan fzf keybindings.

### Chunk 2: Human-Readable Status Tag Annotation [COMPLETED]
- **Target**: `bin/gamectl` (`preview_game()`)
- **DoD**:
  1. [x] Tambahkan penjelasan semantik tepat di samping nilai `Status`:
     - `[VALVE_SO]`: `Valve Linux Library (DRM Steam Resmi - Butuh Client)`
     - `[VALVE_DLL]`: `Valve Windows DLL (DRM Steam Resmi - Butuh Client + Runner)`
     - `[GBE_FORK]`: `Goldberg Emulator Fork (Bebas Client, Full DLC, LAN Ready)`
     - `[STANDALONE]`: `DRM-Free Standalone Game`
  2. [x] Hilangkan ambiguitas istilah teknis bagi pengguna.

### Chunk 3: Conditional GBE LAN Multiplayer & Identity Section [COMPLETED]
- **Target**: `bin/gamectl` (`preview_game()`)
- **DoD**:
  1. [x] Jika status game `[GBE_FORK]`: Tampilkan header `LAN MULTIPLAYER & IDENTITY (GBE FORK: AKTIF)` beserta Player Name, SteamID64, dan Broadcast IP.
  2. [x] Jika status game bukan `[GBE_FORK]`: Tampilkan header `LAN MULTIPLAYER & IDENTITY (GBE FORK: NONAKTIF)` dengan pesan jelas:
     - `Status: Belum di-inject (Biner Steam resmi aktif)`
     - `Catatan: Tekan <CTRL-I> untuk mengaktifkan offline LAN & profil custom`

### Chunk 4: Savegame Storage & Snapshot Truthfulness Guard [COMPLETED]
- **Target**: `bin/gamectl` (`backup_save()`, `preview_game()`)
- **DoD**:
  1. [x] Modifikasi `backup_save()`: Jika folder `$gdir/saves` tidak ditemukan, jangan exit 0 secara diam-diam. Tampilkan pesan peringatan eksplisit:
     `[WARN] Folder saves portable ($gdir/saves) tidak ditemukan.`
     `       Game belum di-inject GBE Fork atau belum memiliki save terisolasi.`
     `       Tekan <CTRL-I> terlebih dahulu untuk mengaktifkan portable saves.`
  2. [x] Pada `preview_game()` di bagian `SAVEGAME & STORAGE`:
     - Jika `$gdir/saves` ada: Tampilkan `Save Path: $gdir/saves (PORTABLE - AKTIF)`.
     - Jika `$gdir/saves` belum ada: Tampilkan `Save Path: Default OS (~/.local/share atau ~/.config - Belum Terisolasi)` dan `Snapshots: Tidak aktif (Memerlukan GBE Fork ./saves)`.

### Chunk 5: Single Source of Truth for Installed Game Detection in Steam Search [COMPLETED]
- **Target**: `bin/gamectl` (`search_steam()`)
- **DoD**:
  1. [x] Refactor deteksi `is_installed` di `search_steam()` agar membaca seluruh library yang dipindai oleh `scan_installed_games` (termasuk Steam libraries, `~/Games`, `~/.local/share/lutris/games`, dan custom libraries di `~/.config/gamectl/libraries`).
  2. [x] Gunakan lookup associative array (`installed_appids` dan `installed_titles`).
  3. [x] Hilangkan false-negative `[BELUM TERPASANG]` pada game yang berada di direktori kustom.

### Chunk 6: Non-GBE Awareness Gate on LAN Persona Configurator [COMPLETED]
- **Target**: `bin/gamectl` (`set_id_interactive()`)
- **DoD**:
  1. [x] Saat `<CTRL-P>` ditekan pada game yang belum di-inject GBE: Tampilkan notifikasi sebelum meminta input:
     `[PERINGATAN] Game ini ($title) belum di-inject GBE Fork (masih biner Steam resmi/DRM).`
     `             Pengaturan persona ini akan disimpan ke steam_settings/configs.user.ini,`
     `             tetapi baru akan AKTIF setelah kamu menjalankan injeksi via <CTRL-I>.`
  2. [x] Tambahkan catatan aktivasi pada output konfirmasi penyimpanan.

### Chunk 7: End-to-End Test Matrix & Verification
- **Target**: `bin/gamectl`, regression test suite
- **DoD**:
  1. `bash -n bin/gamectl` lolos dengan exit code 0.
  2. Uji render preview untuk `[VALVE_SO]`, `[VALVE_DLL]`, `[STANDALONE]`, dan `[GBE_FORK]`.
  3. Verifikasi tombol `<CTRL-B>` pada game non-GBE menghasilkan pesan peringatan yang benar.
  4. Verifikasi `search_steam` mendeteksi game di custom library.
