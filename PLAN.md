# WORK PACKET 5: UNIFIED MASTER DASHBOARD & CROSS-NAVIGATION HUB

## 1. Objective & Scope
Mengintegrasikan seluruh fitur `gamectl` (Pustaka Game, Pencarian Steam Store, Pemantau Unduhan, Unlock Game Resmi, Konfigurasi Global, dan Diagnostik Sistem) ke dalam satu Master Dashboard TUI (`fzf`) interaktif dengan live status preview pane, sehingga pengguna tidak perlu lagi menghafal argumen CLI manual, serta mendukung navigasi bolak-balik tanpa mematikan backward compatibility perintah CLI.

---

## 2. Granular Chunks & Definition of Done (DoD)

### Chunk 1: Master Dashboard Hub (`dashboard_menu()` & System Preview Pane)
- **Target**: `bin/gamectl` (`dashboard_menu()`, `preview_dashboard()`, entrypoint `case "${1:-}"`)
- **DoD**:
  1. Buat fungsi `dashboard_menu()` sebagai entrypoint utama saat `gamectl` dijalankan tanpa argumen.
  2. Implementasikan antarmuka `fzf` dua panel:
     - Kiri: 6 menu aksi utama (`PUSTAKA GAME`, `PENCARIAN STEAM`, `PANTAU UNDUHAN`, `UNLOCK STEAM`, `KONFIGURASI GLOBAL`, `DIAGNOSTIK SISTEM`).
     - Kanan: Preview sistem live via `preview_dashboard()` (Host OS, Display stack, jumlah game terdeteksi, runner aktif, ketersediaan template GBE & tooling performa).
  3. Memilih menu membuka modul terkait dan kembali ke Hub setelah selesai.

### Chunk 2: Interactive Download Monitor & Steam Unlock Flow
- **Target**: `bin/gamectl` (`list_downloads_interactive()`, `unlock_interactive()`)
- **DoD**:
  1. Perbarui tampilan unduhan aktif menjadi interaktif: Menampilkan proses background aktif dengan opsi streaming live log (`tail -f`) atau membatalkan proses yang macet.
  2. Sediakan flow prompt interaktif untuk `unlock_game`: User cukup memasukkan AppID dan judul (opsional) melalui form TUI tanpa perlu mengetik perintah CLI `gamectl unlock <appid>`.

### Chunk 3: Submenu Konfigurasi Global (Persona, Wrappers, Libraries & Remote)
- **Target**: `bin/gamectl` (`configure_global()`)
- **DoD**:
  1. Buat menu interaktif untuk mengelola konfigurasi global di `~/.config/gamectl/`:
     - Opsi 1: Edit Persona LAN Global (Player Name & SteamID64 default).
     - Opsi 2: Edit Default Runtime Wrappers (GameMode, MangoHud, Gamescope FSR global).
     - Opsi 3: Tambah / Kelola path pustaka game kustom (`~/.config/gamectl/libraries`).
     - Opsi 4: Atur remote host sync savegame (`~/.config/gamectl/remote_host`).
  2. Perubahan tersimpan secara deterministik dan langsung aktif.

### Chunk 4: Modul Diagnostik Sistem (Doctor / Health Audit)
- **Target**: `bin/gamectl` (`doctor_audit()`, subperintah `doctor` / `audit`)
- **DoD**:
  1. Buat fungsi `doctor_audit()` yang memverifikasi 7 layer kesiapan sistem:
     - Dependensi CLI (`fzf`, `jq`, `curl`, `file`, `unzip`, `rsync`, `ssh`).
     - Python & YAML Engine (`ruamel.yaml` / `PyYAML`).
     - Template GBE Fork (Linux x64/x86, Windows x64/x86).
     - Windows Game Runner (`umu-run`, GE-Proton, Wine).
     - Performance Wrappers (`gamemoderun`, `mangohud`, `gamescope`).
     - Headless Downloader (`depotdownloader`).
     - Direktori Steam & SLSsteam config.
  2. Cetak rekap kesehatan sistem secara komprehensif dengan status `[READY]` / `[WARN]` / `[MISSING]`.

### Chunk 5: Cross-Navigation & Global Hotkeys di Pustaka Game
- **Target**: `bin/gamectl` (`library_menu()`)
- **DoD**:
  1. Tambahkan hotkey navigasi cepat di dalam menu Pustaka Game:
     - `<CTRL-F>`: Langsung membuka Pencarian Steam Store (`search_steam`).
     - `<CTRL-D>`: Langsung membuka Pemantau Unduhan (`list_downloads_interactive`).
  2. Ubah perilaku `<ESC>` pada `library_menu()` agar kembali ke Master Dashboard Hub, bukan langsung mematikan aplikasi.
  3. Sinkronkan header fzf di pustaka agar menampilkan hotkey baru.

### Chunk 6: CLI Compatibility Preservation & Direct Subcommands
- **Target**: `bin/gamectl` (`case "${1:-}"`)
- **DoD**:
  1. Tambahkan subperintah direct jump:
     - `gamectl library` atau `gamectl list-ui` -> Langsung membuka Pustaka Game.
     - `gamectl doctor` atau `gamectl audit` -> Langsung menjalankan audit sistem.
     - `gamectl menu` atau `gamectl dashboard` -> Membuka Master Dashboard.
  2. Pastikan 100% subperintah lama (`launch`, `inject`, `download`, `downloads`, `unlock`, `sync-steam`, `--search`, `--sync`, `--backup`, dll.) tetap berfungsi identik.
  3. Perbarui `completions/gamectl.bash` dan output `gamectl --help`.

### Chunk 7: End-to-End Test Matrix & Quality Gate
- **Target**: `bin/gamectl`, regression test suite
- **DoD**:
  1. `bash -n bin/gamectl` dan `bash -n completions/gamectl.bash` lulus exit code 0.
  2. Uji cetak preview dashboard (`--preview-dashboard 1..6`).
  3. Uji eksekusi non-interaktif `doctor_audit` menghasilkan exit code 0.
  4. Uji seluruh direct CLI commands eksisting untuk memastikan zero breaking changes.
