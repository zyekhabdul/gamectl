# gamectl: Sovereign TUI Game Manager for Linux

**gamectl** adalah antarmuka Terminal User Interface (TUI) berbobot ultra-ringan (< 15 MB RAM) yang dirancang untuk mengelola, meluncurkan, dan menyinkronkan game standalone portabel di Linux tanpa ketergantungan pada client distribusi berat seperti Steam Client atau wrapper AppImage berbasis Electron/Chromium.

Dibuat untuk arsitektur workstation Linux yang mengutamakan efisiensi resource, peluncuran instan, dan portabilitas game standalone antar perangkat.

---

## Fitur Utama

- **Zero-Bloat & Instant Startup**: Ditulis murni dalam POSIX Bash + `fzf` + `jq`. Memangkas 99% overhead memori dibandingkan client grafis konvensional.
- **Dynamic Multi-Library Autodetection**: Otomatis mendeteksi game yang terpasang dari seluruh direktori Steam (`libraryfolders.vdf` + ACF manifests), direktori portabel `~/Games/`, Lutris, serta custom path melalui `~/.config/gamectl/libraries` atau variabel `GAMECTL_LIBRARY_DIRS`.
- **Split-Pane Live Inspection**: Kolom kiri menampilkan daftar pustaka game; kolom kanan menampilkan metadata biner, arsitektur ELF (32-bit / 64-bit), status runner GBE Fork, konfigurasi wrapper performa, identitas LAN pemain, dan ukuran savegame secara real-time.
- **Savegame Snapshot Protection (Anti-Data-Loss)**: Membuat cadangan otomatis rotasi 3-slot (`slot1`, `slot2`, `slot3`) sebelum setiap game dijalankan, melindungi progres dari dirty shutdown atau crash.
- **Dual-Architecture GBE Fork Injection (`gamectl inject`)**: Mengonversi biner game Valve (Linux native `.so` dan Windows `.dll` x64/x86) menjadi standalone portabel dengan backup `.orig`, portable save `./saves`, dan generator `steam_settings/DLC.txt`.
- **Isolated Windows Runner & Proton Prefix**: Auto-discovery runner Windows (`umu-run` -> `GE-Proton` / `Proton` Steam -> `wine`) dengan Wine prefix terisolasi di direktori lokal game (`$GAME_DIR/pfx`) tanpa mengotori `~/.wine` host.
- **Modular Runtime Performance Wrappers**: Integrasi on-the-fly untuk `gamemoderun`, `mangohud`, dan `gamescope` FSR upscaling melalui menu TUI interaktif (`<Ctrl-O>`) atau CLI flags.
- **LAN Multi-Identity & SteamID Manager (`gamectl set-id`)**: Otomatis menghasilkan SteamID64 unik dan nama profil terpisah untuk co-op multiplayer offline tanpa bentrok ID, serta discovery IP peer (`custom_broadcasts.txt`).
- **Headless Downloader Engine (`gamectl download`)**: Mengunduh game langsung dari Steam Content Server via DepotDownloader headless CLI tanpa memerlukan client Steam GUI atau cache berat.
- **Zero-Download Steam Library Registration (`gamectl unlock`)**: Mendaftarkan kepemilikan AppID dan seluruh DLC ke SLSsteam serta membuat manifest ACF tanpa perlu mengunduh file game. Saat Steam resmi dibuka, game langsung muncul di library dengan status full DLC.
- **Dual-Mode Steam & SLSsteam Sync (`gamectl sync-steam`)**: Otomatis mendaftarkan AppID & DLC ke `~/.config/SLSsteam/config.yaml` dan membuat `appmanifest_<appid>.acf` berstatus terinstal. Game siap dimainkan mandiri dan langsung berstatus full DLC saat aplikasi Steam resmi dibuka.
- **One-Key Multi-Node Sync (`<Ctrl-S>`)**: Menyinkronkan progres savegame portabel ke host remote lain (SSH/Rsync) secara instan dengan proteksi pre-flight timeout (konfigurasi opsional).
- **Steam & ProtonDB Discovery**: Pencarian judul game via Steam Web API publik yang terintegrasi dengan tier rating kompatibilitas Linux dari ProtonDB (Native, Platinum, Gold, Silver).
- **Self-Healing Pre-Flight**: Pembersihan otomatis file lock dan socket terlantar di `/tmp/` sebelum sesi dimulai.

---

## Keyboard Shortcuts

| Shortcut | Aksi |
| :--- | :--- |
| `<ENTER>` | Luncurkan Game Standalone (Mesa GL Threading + Snapshot Backup + Wrappers) |
| `<Ctrl-O>` | Konfigurasi Runtime Wrappers (GameMode / MangoHud / Gamescope FSR) |
| `<Ctrl-P>` | Konfigurasi Identitas Pemain LAN & SteamID (GBE Fork) |
| `<Ctrl-I>` | Injeksi GBE Fork Portabel & Sinkronisasi Dual-Mode Steam/SLSsteam |
| `<Ctrl-S>` | Sinkronisasi Savegame Portabel ke Remote Host via SSH (jika dikonfigurasi) |
| `<Ctrl-B>` | Buat Snapshot Manual Savegame saat ini |
| `<ESC>` / `<Ctrl-C>` | Keluar dari Antarmuka |

---

## Instalasi Cepat

Pastikan dependensi sistem terpasang (`fzf`, `jq`, `curl`, `rsync`, `ssh`, `file`, `unzip`, `python3`):

```bash
git clone git@github.com:zyekhabdul/gamectl.git
cd gamectl
./install.sh
```

Installer otomatis melakukan setup turnkey:
1. Membuat symlink biner `gamectl` dan alias `game` di `~/.local/bin/`.
2. Menginisialisasi direktori konfigurasi dan template di `~/.config/gamectl/` (`libraries.example`, `steam_user.example`).
3. Memasang autocompletion shell ke `~/.local/share/bash-completion/completions/gamectl`.
4. Mendaftarkan desktop entry ke `~/.local/share/applications/gamectl.desktop` untuk launcher Wayland (fuzzel, rofi, wofi).
5. Memastikan runtime headless downloader (DepotDownloader) dan template GBE Fork siap digunakan.

---

## Penggunaan

1. **Buka Library Game**:
   ```bash
   gamectl
   # atau menggunakan alias:
   game
   ```

2. **Cari & Unduh Game Langsung via TUI**:
   ```bash
   gamectl --search
   ```

3. **Unduh Game Headless (Opsi Fleksibel)**:
   ```bash
   # Paket Lengkap (All-in-One: Unduh + Injeksi GBE + Sync Steam):
   gamectl download 48000 "$HOME/Games/Limbo" "LIMBO"

   # Paket Standalone Saja (Unduh + Injeksi GBE tanpa sync Steam):
   gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" --inject-only

   # Unduh Mentah Saja (Raw download tanpa menyentuh biner/injeksi):
   gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" --raw

   # Jalankan di foreground (stream log langsung):
   gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" -f
   ```

4. **Injeksi GBE Fork Standalone & Portable Save**:
   ```bash
   # Injeksi + Sync ke Steam resmi (All-in-One):
   gamectl inject "$HOME/Games/Limbo" 48000

   # Injeksi standalone saja (tanpa menyentuh client Steam):
   gamectl inject "$HOME/Games/Limbo" 48000 --no-sync
   ```

5. **Buka di Steam Resmi Tanpa Download (Zero-Download Full DLC)**:
   ```bash
   gamectl unlock 1145360 "Hades II"
   # atau cukup masukkan AppID (judul di-resolve otomatis via Steam API):
   gamectl unlock 1145360
   ```

6. **Sinkronisasi Dual-Mode ke Steam Client Resmi (Dengan Game Files)**:
   ```bash
   gamectl sync-steam 427520 "Factorio" "$HOME/Games/Factorio"
   ```

7. **Luncurkan Game dengan Prefix Terisolasi & Wrapper Performa**:
   ```bash
   # Luncurkan game dengan HUD MangoHud dan GameMode:
   gamectl launch "$HOME/Games/Limbo" --hud --gamemode

   # Luncurkan game Windows (.exe) dengan Gamescope FSR upscaling:
   gamectl launch "$HOME/Games/WindowsGame" game.exe --gamescope --fsr
   ```

8. **Konfigurasi Identitas LAN & SteamID (GBE Fork)**:
   ```bash
   # Set nama pemain LAN (SteamID64 di-generate acak otomatis):
   gamectl set-id "Player2" "$HOME/Games/Valheim"

   # Set nama pemain dengan SteamID spesifik dan IP peer broadcast:
   gamectl set-id "Alice" 76561198123456789 "$HOME/Games/Valheim" --broadcast "192.168.1.50"

   # Simpan sebagai identitas default global untuk injeksi berikutnya:
   gamectl set-id "MyGamerTag" auto --global
   ```

9. **Daftar Game yang Terdeteksi**:
   ```bash
   gamectl --list
   ```

10. **Sinkronisasi Manual Savegame ke Remote Host**:
   ```bash
   gamectl --sync /path/to/game "Game Title" [remote_host]
   ```

---

## Dokumentasi Lengkap

- **[Panduan Operasional & Integrasi (GUIDE.md)](docs/GUIDE.md)**: Panduan langkah demi langkah pembuatan game standalone portable, injeksi GBE Fork, konfigurasi multi-node sync, disaster recovery savegame, dan integrasi window rules Wayland / Niri.
- **[Spesifikasi Arsitektur Sistem (ARCHITECTURE.md)](docs/ARCHITECTURE.md)**: Analisis mendalam komparasi resource footprint headless vs GUI, arsitektur pipeline aset, dan prinsip hardening backend.

---

## Struktur Proyek

```
gamectl/
├── bin/
│   └── gamectl          # Core TUI executable script
├── completions/
│   └── gamectl.bash     # Shell autocompletion script (Bash/Zsh)
├── docs/
│   ├── ARCHITECTURE.md  # Spesifikasi mendalam arsitektur headless Linux
│   └── GUIDE.md         # Panduan operasional, standalone setup & disaster recovery
├── gamectl.desktop      # Freedesktop XDG application launcher
├── install.sh           # Script installer turnkey otomatis
├── README.md            # Dokumentasi ringkas & overview
└── .gitignore           # Filter file temporer dan cache
```
