# PROPOSAL: GLOBAL LINUX GAMING & DEVELOPER CAPABILITIES FOR GAMECTL

- **Author**: Antigravity Technical Architect
- **Status**: DRAFT / READY FOR EXECUTION
- **Date**: 2026-11-05
- **Target Repository**: `gamectl` (`src/` -> `bin/gamectl`)

---

## 1. Executive Summary

`gamectl` telah membuktikan diri sebagai sovereign, zero-bloat TUI/CLI game manager di Linux. Untuk bersaing dan melampaui launcher seperti Lutris, Heroic, dan Bottles secara headless dan efisien, `gamectl` membutuhkan kapabilitas yang secara spesifik memecahkan hambatan terbesar gamer dan developer Linux global:
1. Kegagalan multiplayer cracked/co-op akibat ketiadaan DLL overrides (OnlineFix).
2. Kegagalan modding Unity/Unreal/Capcom (BepInEx/UE4SS) akibat DLL hijacking yang diabaikan Wine/Proton.
3. Ketergantungan terhadap aplikasi GUI berat (Python/Flatpak) hanya untuk mengunduh rilis GE-Proton.
4. Friksi manajemen prefix Wine terisolasi (`winecfg`, `regedit`, `winetricks`, proses zombie `wineserver`).
5. Ketiadaan integrasi desktop standar (XDG `.desktop`) untuk GNOME/KDE/Rofi dan Steam Deck Game Mode.
6. Ketiadaan pre-flight compatibility query (ProtonDB) langsung dari terminal.

Dokumen ini merinci arsitektur teknis, spesifikasi API, dan rencana implementasi deterministik.

---

## 2. Rincian Arsitektur & Spesifikasi Fitur

### Fitur 1: OnlineFix & Steamworks Co-op Engine
- **Problem Statement**: Game co-op/multiplayer OnlineFix (online-fix.me) menggunakan DLL Windows custom (`OnlineFix64.dll`, `OnlineFix.dll`, `winmm.dll`, `version.dll`, `dnet.dll`, `SteamOverlay64.dll`) yang membajak Steamworks API dan mengarahkannya ke Spacewar (AppID 480). Di Linux/Wine, DLL native ini diabaikan secara default kecuali didefinisikan lewat `WINEDLLOVERRIDES`. Tanpa ini, game langsung crash atau fallback ke singleplayer offline.
- **Spesifikasi Teknis**:
  - **Auto-Detection**: Scan direktori root game dan subdirektori tempat binary `.exe` berada:
    - Signature: `OnlineFix64.dll`, `OnlineFix.dll`, `OnlineFix.ini`, `dnet.dll`, `SteamOverlay64.dll`.
  - **Dynamic Injeksi**: Saat terdeteksi, suntikkan environment variable sebelum eksekusi runner:
    ```bash
    WINEDLLOVERRIDES="OnlineFix=n;OnlineFix64=n;SteamOverlay64=n;dnet=n;winmm=n,b;version=n,b;steam_api64=n;steam_api=n;winhttp=n,b;${WINEDLLOVERRIDES:-}"
    ```
  - **Spacewar (AppID 480) Entitlement**:
    - Periksa apakah manifest `appmanifest_480.acf` ada di library Steam atau SLSsteam.
    - Sediakan perintah `gamectl onlinefix-setup <gdir>` untuk registrasi otomatis Spacewar via `sync_steam 480 "Spacewar"`.
  - **Config Management**:
    - Parsing dan update parameter player name dan language pada `OnlineFix.ini` secara headless atau interaktif.

---

### Fitur 2: Universal Modding & Dynamic DLL Overrides Engine
- **Problem Statement**: Mod loader modern di ekosistem PC gaming mengandalkan teknik DLL hijacking agar dapat dimuat saat engine game melakukan inisialisasi:
  - **Unity Engine**: BepInEx menggunakan `winhttp.dll` atau `doorstop_config.ini`.
  - **Unreal Engine 4/5**: UE4SS menggunakan `dwmapi.dll` atau `dxgi.dll`.
  - **Capcom RE Engine**: REFramework menggunakan `dinput8.dll`.
  - **Generic / ASI Loaders**: GTA/Bethesda menggunakan `dinput8.dll` atau `dsound.dll`.
  - **Post-Processing**: ReShade menggunakan `dxgi.dll` atau `d3d11.dll`.
- **Spesifikasi Teknis**:
  - **Auto-Scan Mod Artifacts**:
    - Jika terdapat folder `BepInEx/` atau file `winhttp.dll` -> tambahkan `winhttp=n,b`.
    - Jika terdapat folder `ue4ss/` atau file `dwmapi.dll` -> tambahkan `dwmapi=n,b`.
    - Jika terdapat file `dinput8.dll` -> tambahkan `dinput8=n,b`.
    - Jika terdapat file `dxgi.dll` (ReShade/SpecialK) -> tambahkan `dxgi=n,b`.
  - **Per-Game Declarative Overrides**:
    - Baca file `$gdir/.dll_overrides` jika user mendefinisikan override kustom.
    - Gabungkan secara cerdas tanpa duplikasi token.

---

### Fitur 3: Headless GE-Proton / Wine-GE Release Manager
- **Problem Statement**: Gamer Linux terpaksa memasang ProtonUp-Qt (berbasis Python/PySide/Flatpak dengan ukuran ratusan MB) hanya untuk mendownload rilis GE-Proton dari repo GitHub GloriousEggroll (`proton-ge-custom`).
- **Spesifikasi Teknis**:
  - **Zero-Dependency Engine**: Menggunakan native `curl`, `jq`, dan `tar`.
  - **Perintah CLI**:
    - `gamectl proton-list`:
      - Pindai direktori lokal (`~/.local/share/Steam/compatibilitytools.d/`, `~/.steam/root/compatibilitytools.d/`).
      - Query GitHub Releases API (`https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=5`) untuk membandingkan versi lokal vs rilis terbaru upstream.
    - `gamectl proton-install [latest|<tag>]`:
      - Unduh tarball rilis arsitektur `x86_64` langsung ke buffer pipa streaming:
        ```bash
        curl -# -L "$download_url" | tar -xz -C "$target_dir/"
        ```
      - Validasi file `compatibilitytool.vdf` dan permissions executable `proton`.
    - `gamectl proton-remove <tag>`:
      - Hapus folder rilis GE-Proton lama untuk membebaskan 1-3 GB ruang penyimpanan per versi.

---

### Fitur 4: Prefix Swiss Army Knife (`gamectl pfx`)
- **Problem Statement**: Pengguna seringkali perlu melakukan troubleshooting Wine prefix terisolasi milik game tertentu (misal: install dependensi Visual C++ Redistributable, buka `winecfg`, ubah Windows version, atau mematikan proses zombie yang mengunci file prefix), namun terbebani sintaks manual yang sangat panjang.
- **Spesifikasi Teknis**:
  - **Perintah CLI**: `gamectl pfx <gdir> <action> [args...]`
  - **Aksi yang Didukung**:
    - `winecfg`: Eksekusi `winecfg` dengan `WINEPREFIX="$gdir/pfx"` menggunakan runner terkonfigurasi.
    - `regedit`: Buka Windows Registry Editor terisolasi untuk prefix game tersebut.
    - `cmd`: Buka Windows command prompt interaktif di dalam prefix.
    - `shell`: Buka subshell Bash lokal dengan `WINEPREFIX`, `PATH`, dan environment runner sudah ter-export secara otomatis.
    - `kill`: Jalankan `wineserver -k` (atau terminate proses prefix) untuk melepaskan lockfile jika game crash/stuck.
    - `clean`: Hapus seluruh direktori `$gdir/pfx` secara aman (dengan konfirmasi) tanpa menyentuh file instalasi game.
    - `winetricks <verb>`: Jalankan winetricks headless pada prefix game tersebut jika binary `winetricks` tersedia di host.

---

### Fitur 5: Desktop & Steam Big Picture Integration (`gamectl make-desktop`)
- **Problem Statement**: Game yang dipasang di `~/Games/` tidak otomatis terdaftar di launcher sistem operasi (GNOME App Grid, KDE Kickoff, Rofi, Waybar, atau Steam Deck Desktop Mode).
- **Spesifikasi Teknis**:
  - **Perintah CLI**: `gamectl make-desktop <gdir> [title]`
  - **Output File**: `~/.local/share/applications/gamectl-<safe_name>.desktop`
  - **Icon Discovery**:
    1. Cari file icon lokal di root game: `icon.png`, `icon.ico`, `logo.png`.
    2. Jika `.ico` ditemukan dan `convert` (ImageMagick) tersedia, konversi otomatis ke `.png`.
    3. Jika tidak ada, gunakan default icon generic `input-gaming`.
  - **Spesifikasi Entry**:
    ```ini
    [Desktop Entry]
    Type=Application
    Name=<Title>
    Comment=Launched via gamectl sovereign runner
    Exec=gamectl launch "<absolute_gdir>"
    Path=<absolute_gdir>
    Icon=<resolved_icon_or_generic>
    Terminal=false
    Categories=Game;
    ```

---

### Fitur 6: ProtonDB Compatibility Audit CLI (`gamectl protondb`)
- **Problem Statement**: Sebelum mengunduh ratusan gigabyte atau meluncurkan game baru, gamer ingin mengetahui apakah game tersebut berjalan sempurna (Platinum/Gold), membutuhkan tweak tertentu, atau borked.
- **Spesifikasi Teknis**:
  - **Perintah CLI**: `gamectl protondb <appid|gdir>`
  - **Endpoint API**: `https://www.protondb.com/api/v1/reports/summaries/${appid}.json`
  - **Indikator Terminal**:
    - Status Tier dengan badge ANSI (Platinum = Cyan, Gold = Yellow, Silver = Gray, Borked = Red).
    - Skor Confidence komunitas.
    - Rekomendasi parameter peluncuran esensial (`PROTON_NO_ESYNC`, `PROTON_USE_WINED3D`, dll).

---

### Fitur 7: Smart Savegame Auto-Locate & Multi-Device Sync
- **Problem Statement**: Lokasi savegame Windows tersebar di berbagai direktori Wine prefix (`drive_c/users/steamuser/AppData/Local/...`, `AppData/Roaming/...`, `Documents/My Games/...`, `Saved Games/...`).
- **Spesifikasi Teknis**:
  - Auto-scan pola folder save Ludusavi di dalam prefix.
  - Snapshot otomatis terkompresi `.tar.gz` sebelum game diluncurkan (rollback safety).
  - Sinkronisasi instan via `rsync` over SSH ke laptop, PC desktop, atau Steam Deck lokal.

---

### Fitur 8: Game Developer Mode & Engine Profiler
- **Problem Statement**: Developer game membutuhkan telemetri mendalam saat menguji build native atau build Windows di Linux.
- **Spesifikasi Teknis**:
  - Toggle `WINEDEBUG` trace levels (`+relay`, `+seh`, `+loaddll`).
  - Toggle Vulkan Loader debug output (`VK_LOADER_DEBUG=all`).
  - Audit Steamworks mock logging (GBE log capture) untuk memastikan callback API tidak gagal silently.

---

## 3. Rencana Implementasi Bertahap (Work Packet 9)

```
[Packet 9.1: OnlineFix & Modding Overrides Engine]
  - Implementasi scan DLL di 40_wrappers.sh
  - Injeksi WINEDLLOVERRIDES di 50_launcher.sh
  - Registrasi Spacewar (AppID 480) di 30_downloader.sh

[Packet 9.2: Headless GE-Proton Manager]
  - Implementasi proton_list, proton_install, proton_remove di 40_wrappers.sh
  - Expose CLI di src/main.sh

[Packet 9.3: Prefix Swiss Army Knife]
  - Implementasi pfx_command di 40_wrappers.sh
  - Subcommands: winecfg, regedit, cmd, kill, clean

[Packet 9.4: ProtonDB CLI & Desktop Entry Generator]
  - Implementasi protondb_query & generate_desktop_entry
  - Verifikasi otomatis di tests/test_cli.sh
```

---

Dokumen ini disimpan sebagai referensi spesifikasi teknis resmi untuk dieksekusi saat sesi berikutnya dimulai.
