# WORK PACKET 7: SOVEREIGN SYSTEM DYNAMIC RESOLUTION & HARDCODED REMEDIATION

## 1. Objective & Scope
Eliminate all developer-specific, local-machine, and static hardcoded values across `bin/gamectl` and `install.sh`. Replace them with dynamic runtime detection mechanisms: hierarchical SteamID resolution, native display resolution detection for Gamescope FSR scaling, dynamic GPU architecture evaluation in UI menus, pre-launch CPU governor state preservation, multi-architecture headless downloader provisioning, neutral companion host variables, and multi-path Steam library discovery.

---

## 2. Granular Chunks & Definition of Done (DoD)

### Chunk 1: Dynamic SteamID Resolution & SSoT Identity Gate [VERIFIED]
- **Target**: `bin/gamectl` (`sync_steam()`, `get_game_persona()`, `inject_game()`)
- **DoD**:
  1. Hapus nilai statis pribadi `local steamid="${GAMECTL_STEAMID:-76561198609877617}"` dari `sync_steam()`. [DONE]
  2. Implementasikan fungsi resolusi SteamID berjenjang (`resolve_active_steamid()`): [DONE]
     - Priority 1: Environment variable `GAMECTL_STEAMID` (jika disetel). [DONE]
     - Priority 2: File konfigurasi `$HOME/.config/gamectl/persona` (`account_steamid`). [DONE]
     - Priority 3: Auto-detect dari file Steam client aktif (`loginusers.vdf` atau direktori `userdata/`). [DONE]
     - Priority 4: Dynamic fallback ke `generate_steamid64()`. [DONE]
  3. Sinkronkan penggunaan fungsi ini pada `sync_steam()`, `inject_game()`, dan `get_game_persona()`. [DONE]

### Chunk 2: Dynamic Display Resolution & Gamescope Scaling [VERIFIED]
- **Target**: `bin/gamectl` (`get_native_resolution()`, `build_wrapper_command()`, `configure_wrappers()`, `configure_global()`), `install.sh`
- **DoD**:
  1. Implementasikan fungsi `get_native_resolution()` untuk mendeteksi lebar dan tinggi native display via `/sys/class/drm/card*-*/modes`, `hyprctl`, atau `xrandr`. [DONE]
  2. Hitung resolusi render FSR (`-W -H`) dan resolusi display native (`-w -h`) secara dinamis berdasarkan native resolution host. [DONE]
  3. Ganti hardcoded `-W 1280 -H 720 -w 1920 -h 1080` pada default wrappers, submenu global configuration, per-game configuration, dan template `install.sh`. [DONE]

### Chunk 3: Dynamic Hardware & Mesa GPU Audit in UI Menus [VERIFIED]
- **Target**: `bin/gamectl` (`configure_wrappers()`, `configure_global()`, `doctor_audit()`)
- **DoD**:
  1. Buat helper `is_haswell_gpu()` untuk mendeteksi apakah GPU host bertipe Intel Haswell / 4th Gen Core. [DONE]
  2. Modifikasi teks toggle Mesa GL Threading di `configure_wrappers()` dan `configure_global()`: tampilkan `(Intel Haswell: Keep OFF)` hanya jika Haswell terdeteksi; tampilkan `(Opt-in Performance)` jika bukan Haswell. [DONE]
  3. Pastikan `doctor_audit()` tetap memberikan advisory proteksi yang akurat tanpa hardcode statis pada layer visual. [DONE]

### Chunk 4: Dynamic CPU Scaling Governor Preservation [VERIFIED]
- **Target**: `bin/gamectl` (`launch_game()`)
- **DoD**:
  1. Di awal fungsi `launch_game()`, simpan nilai governor aktif host saat ini dari `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` ke variabel lokal `prev_governor`. [DONE]
  2. Jika governor diubah ke `performance`, pulihkan kembali ke `prev_governor` saat game ditutup, bukan memaksakan `powersave`. [DONE]

### Chunk 5: Dynamic Multi-Arch DepotDownloader Engine [VERIFIED]
- **Target**: `bin/gamectl` (`ensure_downloader()`)
- **DoD**:
  1. Periksa arsitektur sistem menggunakan `uname -m`. [DONE]
  2. Petakan `x86_64 -> linux-x64` dan `aarch64|arm64 -> linux-arm64`. [DONE]
  3. Gunakan URL download DepotDownloader yang sesuai dengan arsitektur host. [DONE]

### Chunk 6: Neutral Companion Host & Remote Synchronization [VERIFIED]
- **Target**: `bin/gamectl` (`get_remote_host()`, `sync_save_remote()`, exports)
- **DoD**:
  1. Ganti variabel utama menjadi `GAMECTL_REMOTE_HOST` / `GAMECTL_COMPANION_HOST` (pertahankan `GAMECTL_TUF_HOST` sebagai fallback backward compatibility). [DONE]
  2. Sediakan alias fungsi generik `sync_to_companion` di samping `sync_to_tuf`. [DONE]

### Chunk 7: Dynamic Multi-Path Steam Library Detection [VERIFIED]
- **Target**: `bin/gamectl` (`get_steam_root()`, `get_steam_primary_apps()`, `get_steam_libraries()`, `sync_steam()`, `doctor_audit()`)
- **DoD**:
  1. Perluas pencarian direktori Steam root: `$HOME/.local/share/Steam`, `$HOME/.steam/steam`, `$HOME/.steam/root`, Flatpak (`$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam`), Snap (`$HOME/snap/steam/common/.local/share/Steam`). [DONE]
  2. Implementasikan fungsi `get_steam_root()` dan `get_steam_primary_apps()`. [DONE]
  3. Deduplikasi scan direktori Steam library pada `get_steam_libraries()` via `realpath` dan associative array. [DONE]
  4. Gunakan Steam primary library dinamis pada `sync_steam()` alih-alih hardcoded `$HOME/.local/share/Steam/steamapps`. [DONE]
  5. Sediakan CLI subcommands `get-steam-root` dan `get-steam-libraries` (`steam-libs`). [DONE]

### Chunk 8: Machine Verification & Quality Gate [VERIFIED]
- **Target**: `bin/gamectl`, `install.sh`, deterministic test harness
- **DoD**:
  1. Jalankan static syntax check: `bash -n bin/gamectl && bash -n install.sh && bash -n completions/gamectl.bash` (Exit 0). [DONE]
  2. Verifikasi empiris:
     - Tes resolusi SteamID (pastikan bukan `76561198609877617` statis). [DONE]
     - Tes kalkulasi resolusi display Gamescope (sesuai layar host saat ini `1600x900`). [DONE]
     - Tes fallback governor saat launch exit. [DONE]
     - Tes `bin/gamectl doctor` (Exit 0, 17 pass, 0 missing). [DONE]
  3. Local git checkpoint dan sinkronisasi Obsidian RAG `STATE.md`. [DONE]
