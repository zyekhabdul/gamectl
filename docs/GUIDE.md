# Panduan Lengkap Operasional & Integrasi gamectl

Dokumen ini merupakan panduan praktis (*operational manual*) yang menghubungkan spesifikasi arsitektur headless di [ARCHITECTURE.md](file:///home/aomiqaza/Projects/gamectl/docs/ARCHITECTURE.md) dengan implementasi nyata pada lingkungan workstation Linux.

---

## 1. Filosofi Desain & Standar Standalone

`gamectl` dirancang untuk memisahkan lifecycle eksekusi game dari client grafis berat (Steam Client/Electron). Setiap game diperlakukan sebagai **unit mandiri (self-contained)**:

1. **Host-Independent**: Game membawa library runner, konfigurasi offline, dan data savegame di dalam foldernya sendiri.
2. **Zero-Duplicate Storage**: Tidak memerlukan staging download terpisah atau duplikasi cache visual browser.
3. **Atomic Sync**: Data progres game dapat disinkronkan antar-perangkat secara instan menggunakan SSH + Rsync.

---

## 2. Dependensi & Persyaratan Sistem

### 2.1 Dependensi Sistem
Pastikan paket berikut telah terpasang pada distribusi Linux:
- `bash` (versi 4.4 atau 5.x)
- `fzf` (mesin rendering Terminal User Interface)
- `jq` (parser payload JSON Steam API & ProtonDB)
- `curl` (HTTP client untuk discovery metadata)
- `rsync` & `openssh` (protokol transfer savegame multi-node)
- `file` (inspeksi header binary ELF 32-bit / 64-bit)
- `unzip` (ekstraksi archive binary DepotDownloader)
- `python3` & `python-ruamel-yaml` / `python-yaml` (sinkronisasi konfigurasi SLSsteam)

Pada Arch Linux:
```bash
sudo pacman -S fzf jq curl rsync openssh file unzip python python-ruamel-yaml
```

### 2.2 Dependensi Runner (GBE Fork & Windows Compatibility)
Untuk menjalankan game berbasis Steam API secara standalone tanpa client Steam aktif, `gamectl` mengintegrasikan emulator **Goldberg Emulator (GBE Fork)** dual-architecture:
- **Linux Native ELF**:
  - 64-bit library: `~/.local/share/gbe-fork/regular/x64/libsteam_api.so`
  - 32-bit library: `~/.local/share/gbe-fork/regular/x86/libsteam_api.so`
- **Windows PE DLL**:
  - 64-bit DLL: `~/.local/share/gbe-fork/windows/x64/steam_api64.dll`
  - 32-bit DLL: `~/.local/share/gbe-fork/windows/x86/steam_api.dll`

Untuk menjalankan game biner Windows (`.exe`), `gamectl` secara otomatis mendeteksi runner terbaik yang tersedia pada sistem host:
1. Custom override biner via `$GAME_DIR/.runner`
2. `umu-run` (Unified Linux Wine Game Launcher)
3. `GE-Proton` / `Proton` Steam (`~/.local/share/Steam/compatibilitytools.d/` atau Steam runtime)
4. `wine64` / `wine` sistem host

### 2.3 Dependensi Wrapper Performa & Display (Opsional)
- `gamemoderun` (`gamemode`): Optimasi prioritas proses, CPU governor, dan scheduler Linux saat game aktif.
- `mangohud`: On-Screen Display (OSD) overlay untuk memantau FPS, frametime, temperatur, dan utilisasi GPU/VRAM.
- `gamescope`: Micro-compositor Wayland dari Valve untuk integer scaling, resolusi kustom, dan AMD FidelityFX Super Resolution (FSR) upscaling.
- `systemd-run` (`systemd`): Isolasi pohon proses cgroups v2 (`--scope`) untuk terminasi instan tanpa zombie process.
- `bwrap` (`bubblewrap`): Sandbox keamanan rootless (`--sandbox`) untuk melindungi kredensial host (`~/.ssh`, `~/.gnupg`, token browser).

---

## 3. Konfigurasi Lingkungan

`gamectl` mendukung konfigurasi melalui environment variables dan file konfigurasi lokal.

### 3.1 Environment Variables
Tambahkan ke `~/.bashrc`, `~/.zshrc`, atau environment session Anda jika ingin mengubah default:

| Variabel | Default | Keterangan |
| :--- | :--- | :--- |
| `GAMECTL_REMOTE_HOST` | *Kosong* | Host alias SSH untuk target sinkronisasi savegame (`remote_host`) |
| `GAMECTL_GBE_X64` | `~/.local/share/gbe-fork/regular/x64/libsteam_api.so` | Path binary GBE Fork 64-bit |
| `GAMECTL_GBE_X86` | `~/.local/share/gbe-fork/regular/x86/libsteam_api.so` | Path binary GBE Fork 32-bit |
| `GAMECTL_LIBRARY_DIRS` | *Kosong* | Path tambahan dipisah titik dua (`/path1:/path2`) |

### 3.2 Custom Library Paths (`~/.config/gamectl/libraries`)
Selain direktori standar Steam (`steamapps/common`) dan `~/Games/`, Anda dapat menambahkan path folder game lain baris per baris:

```bash
mkdir -p ~/.config/gamectl
cat <<EOF > ~/.config/gamectl/libraries
# Baris komentar diawali tanda pagar
/mnt/storage/Games
~/Games/Emulators/Standalone
~/.local/share/lutris/games
EOF
```

### 3.3 Remote Sync Host (`~/.ssh/config` & `~/.config/gamectl/remote_host`)
Agar shortcut `<Ctrl-S>` atau perintah `gamectl --sync` dapat menyinkronkan savegame ke host lain via SSH tanpa password:
```text
Host companion-pc
    HostName 192.168.1.50
    User username
    IdentityFile ~/.ssh/id_ed25519
    ConnectTimeout 1
    BatchMode yes
```
Daftarkan alias host tersebut di `~/.config/gamectl/remote_host` atau via environment `GAMECTL_REMOTE_HOST`:
```bash
echo "companion-pc" > ~/.config/gamectl/remote_host
```

### 3.4 Kredensial Steam untuk Downloader (`~/.config/gamectl/steam_user`)
Jika Anda mengunduh game yang memerlukan lisensi akun Steam Anda:
```bash
echo "nama_akun_steam_anda" > ~/.config/gamectl/steam_user
```
DepotDownloader otomatis membaca username ini dan menyertakan flag `-remember-password`.

### 3.5 Konfigurasi Default Wrapper Performa (`~/.config/gamectl/wrappers`)
Untuk mengaktifkan wrapper secara default pada setiap game yang diluncurkan:
```bash
cp ~/.config/gamectl/wrappers.example ~/.config/gamectl/wrappers
```
Isi file mencakup:
```ini
gamemode=0
hud=0
gamescope=0
fsr=0
gamescope_args=-W 1280 -H 720 -w 1920 -h 1080 -F fsr -f
```
Konfigurasi per-game dapat ditimpa dengan membuat file `$GAME_DIR/.wrappers` atau melalui menu TUI interaktif (`<Ctrl-O>`).

### 3.6 Identitas Default LAN & SteamID (`~/.config/gamectl/persona`)
Untuk menetapkan nama pemain default dan SteamID saat injeksi GBE Fork:
```bash
cp ~/.config/gamectl/persona.example ~/.config/gamectl/persona
```
Atau cukup jalankan:
```bash
gamectl set-id "MyGamerTag" auto --global
```

### 3.7 Shell Completion & Desktop Launcher
Installer otomatis memasang integrasi sistem:

#### A. Shell Autocompletion (Bash & Zsh)
- **Lokasi Symlink Live**: Terpasang di `~/.local/share/bash-completion/completions/gamectl` dan di-symlink ke alias `game`.
- **Fitur Autocompletion**:
  1. **Top-Level Subcommands**:
     Ketik `gamectl <TAB><TAB>` atau `game <TAB><TAB>` untuk menampilkan seluruh sub-perintah:
     `launch`, `run`, `configure-wrappers`, `set-id`, `set-id-interactive`, `generate-steamid`, `download`, `downloads`, `entitle`, `adopt-steam`, `unlock`, `inject`, `fetch-dlc`, `sync-steam`, `ensure-downloader`, `detect-gpu`, `check-scope`, `check-sandbox`, `pfx`, `proton-list`, `proton-install`, `proton-remove`, `protondb`, `make-desktop`, `add-to-steam`, `fetch-art`, `--search`, `--list`, `--sync`, `--backup`, `--help`, `--version`.
  2. **Flag Konfigurasi Runtime Wrappers**:
     Ketik `gamectl launch <dir> --<TAB>` untuk melengkapi flag:
     `--hud`, `--no-hud`, `--mangohud`, `--no-mangohud`, `--gamemode`, `--no-gamemode`, `--gamescope`, `--no-gamescope`, `--fsr`, `--no-fsr`, `--glthread`, `--no-glthread`, `--scope`, `--no-scope`, `--prime`, `--no-prime`, `--sandbox`, `--no-sandbox`.
  3. **Identitas LAN & SteamID**:
     Ketik `gamectl set-id PlayerName <TAB>` untuk melengkapi keyword generator (`auto`, `random`) atau flag `--broadcast`, `--global`.
  4. **Pilihan Paket Download & Injeksi**:
     `gamectl download <appid> <dir> <title> --<TAB>` melengkapi `--raw`, `--inject-only`, `--all`, `--foreground`, `-f`.
     `gamectl inject <dir> <appid> --<TAB>` melengkapi `--all`, `--no-sync`.
  5. **Auto-Path Completion**:
     Melengkapi path folder direktori game (`_filedir -d`) dengan fallback cerdas `compgen -d`/`compgen -f` bahkan pada instalasi Linux minimal tanpa package `bash-completion`.
- **Aktivasi Manual pada Sesi Shell Aktif**:
  ```bash
  source ~/.local/share/bash-completion/completions/gamectl
  ```
- **Integrasi Zsh**:
  Bagi pengguna Zsh, tambahkan baris berikut ke `~/.zshrc`:
  ```zsh
  autoload -U +X bashcompinit && bashcompinit
  source ~/.local/share/bash-completion/completions/gamectl
  ```

#### B. Desktop Application Launcher
- **XDG Desktop Entry**: Terpasang di `~/.local/share/applications/gamectl.desktop`.
- **Integrasi Wayland / Application Launcher**: Game manager dapat dicari dan diluncurkan langsung melalui app launcher seperti **fuzzel**, **rofi**, **wofi**, atau **tofi** pada Wayland (Niri, Sway, Hyprland).

---

## 4. Resep Pembuatan Game Standalone Portabel (Portability Recipe)

Untuk mengubah game Linux native atau Windows menjadi format standalone portable yang kompatibel penuh dengan `gamectl`:

### 4.1 Struktur Standar Direktori Game
```text
[NamaGame]/
├── game_executable               # Binary ELF Linux native atau .exe Windows
├── libsteam_api.so / *.dll       # GBE Fork shim (asli tersimpan di *.orig)
├── steam_appid.txt               # Berisi angka AppID Steam (misal: 48000)
├── steam_settings/
│   ├── configs.user.ini          # Konfigurasi offline, nama pemain, SteamID
│   ├── custom_broadcasts.txt     # Daftar IP broadcast/peer untuk pencarian LAN
│   └── DLC.txt                   # Daftar DLC yang di-unlock (<id>=<nama>)
├── pfx/                          # Prefix Wine/Proton mandiri terisolasi (Windows)
├── .wrappers                     # Override wrapper lokal (opsional)
└── saves/                        # Folder penyimpan progres lokal (portable)
```

### 4.2 Otomatisasi Injeksi (`gamectl inject`)
Tidak perlu melakukan langkah manual di atas. Cukup jalankan satu perintah:
```bash
# Injeksi lengkap (GBE Fork + Portable Save + Sync Steam Client):
gamectl inject /path/to/game [appid]

# Injeksi standalone saja (tanpa menyentuh konfigurasi Steam client):
gamectl inject /path/to/game [appid] --no-sync
```

### 4.3 Headless Downloader (`gamectl download`)
Untuk mengunduh game tanpa membuka client Steam atau browser:
```bash
# 1. Unduh All-in-One di background (Unduh + Injeksi GBE + Sync Steam):
gamectl download 48000 "$HOME/Games/Limbo" "LIMBO"

# 2. Unduh + Injeksi GBE saja (Standalone tanpa client Steam):
gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" --inject-only

# 3. Unduh mentah saja (Raw download tanpa menyentuh file biner):
gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" --raw

# 4. Unduh di foreground (stream progres langsung ke terminal):
gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" -f
```

### 4.4 Registrasi Library Steam Tanpa Download (`gamectl unlock`)
Untuk menampilkan game dan seluruh DLC-nya di Library Steam resmi tanpa perlu mengunduh file aset game:
```bash
# Registrasi AppID & resolve otomatis judul + DLC dari Steam API:
gamectl unlock 1145360

# Atau dengan menyertakan judul eksplisit:
gamectl unlock 1145360 "Hades II"
```
Mekanisme ini secara otomatis:
1. Menambahkan AppID ke daftar lisensi SLSsteam (`~/.config/SLSsteam/config.yaml`).
2. Menarik seluruh katalog DLC dari Steam Web API dan memetakan `DlcData` di SLSsteam.
3. Menulis manifest `~/.local/share/Steam/steamapps/appmanifest_<appid>.acf` berstatus `StateFlags: 4` (Installed).
4. Saat Steam client dibuka, game langsung terdaftar di library dengan seluruh DLC aktif.

### 4.5 Pengaturan Identitas LAN & SteamID (`gamectl set-id`)
Untuk bermain co-op offline atau game multiplayer LAN menggunakan GBE Fork tanpa bentrok ID antar komputer:
```bash
# 1. Atur nama pemain (SteamID64 unik di-generate otomatis):
gamectl set-id "Player2" "$HOME/Games/Valheim"

# 2. Atur nama pemain dengan SteamID spesifik dan IP peer broadcast:
gamectl set-id "Alice" 76561198123456789 "$HOME/Games/Valheim" --broadcast "192.168.1.50"

# 3. Tambahkan beberapa IP broadcast sekaligus:
gamectl set-id "Bob" auto "$HOME/Games/Valheim" --broadcast "10.0.0.5,10.0.0.6"

# 4. Simpan profil default secara global ke ~/.config/gamectl/persona:
gamectl set-id "MyGamerTag" auto --global
```

### 4.6 Peluncuran Terisolasi & Wrapper Performa (`gamectl launch`)
Untuk meluncurkan game secara langsung dari shell dengan runner terisolasi dan wrapper performa:
```bash
# Luncurkan game dengan HUD MangoHud dan GameMode:
gamectl launch "$HOME/Games/Limbo" --hud --gamemode

# Luncurkan game Windows (.exe) dengan Gamescope FSR upscaling:
gamectl launch "$HOME/Games/Valheim" valheim.exe --gamescope --fsr

# Buka menu konfigurasi wrapper interaktif per-game:
gamectl configure-wrappers "$HOME/Games/Valheim"
```

---

## 5. Panduan Fitur & Alur Kerja TUI

### 5.1 Membuka Antarmuka
Cukup jalankan:
```bash
gamectl
# atau alias pendek:
game
```

### 5.2 Split-Pane Interface
- **Panel Kiri**: Daftar pustaka game yang terdeteksi otomatis dari seluruh library Steam dan direktori standalone.
- **Panel Kanan (Live Preview)**:
  - Judul & AppID Steam.
  - Status Runner:
    - `[GBE_FORK]`: Terkonfigurasi dengan emulator portabel Goldberg.
    - `[VALVE_SO]` / `[VALVE_DLL]`: Menggunakan library native bawaan Valve.
    - `[STANDALONE]`: Game DRM-free tanpa shim Steam API.
  - Runner & Prefix: Native Linux ELF atau Runner Windows (`umu-run` / `GE-Proton` / `wine`) dengan Wine prefix terisolasi di `$GAME_DIR/pfx`.
  - Profil Runtime Wrapper: Status aktif `GameMode`, `MangoHud`, `Gamescope`, `FSR`.
  - Identitas LAN Multiplayer: Nama pemain GBE, SteamID64, dan IP peer broadcast terdaftar.
  - Status Savegame: `(PORTABLE)` jika folder `saves/` terisolasi, atau lokasi default OS.
  - Jumlah DLC aktif (`steam_settings/DLC.txt`).
  - Status Snapshot Cadangan & Total Ukuran Storage.

### 5.3 Shortcut Keyboard

| Tombol | Deskripsi & Alur Kerja |
| :--- | :--- |
| `<ENTER>` | **Launch Game**: Membuat auto-snapshot savegame, merangkai active wrappers (`gamemoderun`, `mangohud`, `gamescope`), menaikkan CPU governor ke `performance`, mengaktifkan `mesa_glthread=true`, lalu meluncurkan game. Saat game ditutup, CPU governor dikembalikan ke `powersave`. |
| `<Ctrl-O>` | **Configure Runtime Wrappers**: Membuka dialog interaktif untuk mengaktifkan/menonaktifkan GameMode, MangoHud, Gamescope, dan FSR upscaling per-game. |
| `<Ctrl-P>` | **Configure LAN Persona & SteamID**: Mengatur nama pemain LAN, mengubah SteamID64, dan mendaftarkan IP peer broadcast teman bermain. |
| `<Ctrl-I>` | **Instant GBE Inject & Steam Sync**: Mengubah game `[VALVE_SO]` / `[VALVE_DLL]` atau `[STANDALONE]` menjadi `[GBE_FORK]` portabel, mengunduh DLC, dan menyinkronkan status instalasi ke Steam resmi + SLSsteam secara instan. |
| `<Ctrl-S>` | **Remote Save Sync**: Menguji konektivitas SSH ke remote host (`ConnectTimeout=1`). Jika online dan terkonfigurasi, melakukan sinkronisasi delta via `rsync` dari folder `./saves` lokal ke direktori game pada remote host. |
| `<Ctrl-B>` | **Manual Snapshot**: Membuat salinan cadangan instan savegame ke rotasi slot `.save_snapshots`. |
| `<ESC>` / `<Ctrl-C>` | Keluar dari antarmuka `gamectl`. |

---

## 6. Proteksi Savegame & Prosedur Disaster Recovery

`gamectl` menerapkan sistem cadangan berputar 3-slot (*3-slot rolling snapshots*) di dalam direktori game target:
`[GameDir]/.save_snapshots/` (`slot1`, `slot2`, `slot3`).

- **Rotasi Otomatis**: Setiap kali `<ENTER>` ditekan, `slot2` bergeser ke `slot3`, `slot1` bergeser ke `slot2`, dan state `./saves/` saat ini disalin ke `slot1`.
- **Prosedur Pemulihan (Disaster Recovery)**:
  Jika game crash dan file save mengalami korupsi data:
  ```bash
  cd ~/Games/[NamaGame]
  # Pulihkan save dari snapshot terakhir (slot1):
  cp -a .save_snapshots/slot1/* ./saves/
  # Atau dari snapshot sebelumnya (slot2):
  cp -a .save_snapshots/slot2/* ./saves/
  ```

---

## 7. Integrasi Window Rules (Wayland / Niri Compositor)

Bagi pengguna Wayland compositor bergaya scrolling/tiling seperti **Niri**, tambahkan window rules berikut pada `~/.config/niri/config.kdl` agar game tidak terdistorsi oleh sistem kolom:

```kdl
window-rule {
    match app-id="^limbo$"
    match app-id="^Terraria"
    match app-id="^Stardew"
    match app-id="^factorio$"

    open-fullscreen true
    default-column-width {}
}
```

---

## 8. Referensi CLI Lengkap

Selain antarmuka TUI interaktif, `gamectl` menyediakan sub-perintah langsung:

```bash
# 1. Buka antarmuka TUI utama
gamectl

# 2. Luncurkan game dengan prefix mandiri dan opsi wrapper performa
gamectl launch <dir> [binary] [title] [--hud] [--gamemode] [--gamescope] [--fsr]

# 3. Buka konfigurasi wrapper interaktif per-game
gamectl configure-wrappers <dir> [title]

# 4. Atur identitas nama pemain & SteamID64 LAN (GBE Fork)
gamectl set-id <player> [steamid] [dir] [--broadcast <ip>] [--global]

# 5. Generate SteamID64 valid 17-digit acak
gamectl generate-steamid

# 6. Unduh game secara headless via DepotDownloader (pilihan paket fleksibel)
gamectl download <appid> [target_dir] [title] [--raw|--inject-only|--all] [-f]

# 7. Pantau status & antrean download yang aktif
gamectl downloads

# 8. Buka game di Steam resmi tanpa unduh aset (Zero-Download Full DLC)
gamectl unlock <appid> [title]

# 9. Injeksi GBE Fork, konfigurasi save ./saves, dan auto-DLC
gamectl inject /path/to/game [appid] [--no-sync|--all]

# 10. Unduh & tulis daftar DLC Steam ke steam_settings/DLC.txt
gamectl fetch-dlc /path/to/game [appid]

# 11. Sinkronisasi dual-mode Steam Client resmi & SLSsteam full DLC (dengan direktori game)
gamectl sync-steam <appid> [title] [game_dir]

# 12. Tampilkan daftar game terdeteksi dalam format teks deterministik
gamectl --list

# 13. Cari game di Steam Store API dan cek kompatibilitas ProtonDB
gamectl --search

# 14. Sinkronisasi manual direktori game ke remote companion host
gamectl --sync /path/to/game "Game Title" [remote_host]

# 15. Buat snapshot manual savegame dari terminal
gamectl --backup /path/to/game

# 16. Tampilkan panduan ringkas
gamectl --help

# 17. Tampilkan versi aktif
gamectl --version
```

---

## 9. Pemecahan Masalah (Troubleshooting)

### Q: `gamectl --list` tidak mendeteksi game baru?
1. Pastikan file eksekutabel game memiliki izin eksekusi POSIX:
   ```bash
   chmod +x /path/to/game/start.sh
   ```
2. Jika game berada di luar path default, tambahkan path direktori induknya ke `~/.config/gamectl/libraries`.

### Q: Game keluar dengan error `wrong ELF class`?
- Terjadi ketidakcocokan arsitektur antara binary game dan `libsteam_api.so`. Jalankan `file -b ./game_bin`. Jika 32-bit, gunakan library dari folder `gbe-fork/regular/x86/`.

### Q: CPU Governor tidak berubah saat in-game?
- Fitur dynamic governor memerlukan izin tulis ke `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`. Jika dijalankan sebagai user biasa tanpa aturan udev/sudoers, `gamectl` akan melanjutkan eksekusi game secara aman (*graceful bypass*) tanpa memicu error.
