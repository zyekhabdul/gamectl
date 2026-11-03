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

Pada Arch Linux:
```bash
sudo pacman -S fzf jq curl rsync openssh file
```

### 2.2 Dependensi Runner (GBE Fork)
Untuk menjalankan game berbasis Steam API secara standalone tanpa client Steam aktif, `gamectl` mengintegrasikan emulator **Goldberg Emulator (GBE Fork)**:
- 64-bit library: `~/.local/share/gbe-fork/regular/x64/libsteam_api.so`
- 32-bit library: `~/.local/share/gbe-fork/regular/x86/libsteam_api.so`

---

## 3. Konfigurasi Lingkungan

`gamectl` mendukung konfigurasi melalui environment variables dan file konfigurasi lokal.

### 3.1 Environment Variables
Tambahkan ke `~/.bashrc`, `~/.zshrc`, atau environment session Anda jika ingin mengubah default:

| Variabel | Default | Keterangan |
| :--- | :--- | :--- |
| `GAMECTL_TUF_HOST` | `tuf-gaming-arch` | Host alias SSH untuk target sinkronisasi savegame |
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

### 3.3 SSH Config Node Pendamping (`~/.ssh/config`)
Agar shortcut `<Ctrl-S>` bekerja secara non-interaktif tanpa input password:
```text
Host tuf-gaming-arch
    HostName 192.168.1.50
    User aomiqaza
    IdentityFile ~/.ssh/id_ed25519
    ConnectTimeout 1
    BatchMode yes
```

---

## 4. Resep Pembuatan Game Standalone Portabel (Portability Recipe)

Untuk mengubah game Linux native menjadi format standalone portable yang kompatibel penuh dengan `gamectl`:

### 4.1 Struktur Standar Direktori Game
```text
[NamaGame]/
├── game_executable               # Binary ELF Linux native
├── libsteam_api.so               # GBE Fork shim
├── steam_appid.txt               # Berisi angka AppID Steam (misal: 48000)
├── steam_settings/
│   ├── configs.user.ini          # Konfigurasi offline & storage isolation
│   └── DLC.txt                   # Daftar DLC yang di-unlock (<id>=<nama>)
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
    - `[VALVE_SO]`: Menggunakan library native bawaan Valve.
    - `[STANDALONE]`: Game DRM-free tanpa shim Steam API.
  - Arsitektur Biner ELF (misal: `ELF 64-bit LSB pie executable`).
  - Status Savegame: `(PORTABLE)` jika folder `saves/` terisolasi, atau lokasi default OS.
  - Jumlah DLC aktif (`steam_settings/DLC.txt`).
  - Status Snapshot Cadangan & Total Ukuran Storage.

### 5.3 Shortcut Keyboard

| Tombol | Deskripsi & Alur Kerja |
| :--- | :--- |
| `<ENTER>` | **Launch Game**: Membuat auto-snapshot savegame, menaikkan CPU governor ke `performance`, mengaktifkan `mesa_glthread=true`, lalu meluncurkan game. Saat game ditutup, CPU governor dikembalikan ke `powersave`. |
| `<Ctrl-I>` | **Instant GBE Inject & Steam Sync**: Mengubah game `[VALVE_SO]` atau `[STANDALONE]` menjadi `[GBE_FORK]` portabel, mengunduh DLC, dan menyinkronkan status instalasi ke Steam resmi + SLSsteam secara instan. |
| `<Ctrl-S>` | **Multi-Node Sync**: Menguji konektivitas SSH ke node pendamping (`ConnectTimeout=1`). Jika online, melakukan sinkronisasi delta via `rsync` dari folder `./saves` lokal ke direktori game pada node target. |
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

# 2. Unduh game secara headless via DepotDownloader (pilihan paket fleksibel)
gamectl download <appid> [target_dir] [title] [--raw|--inject-only|--all] [-f]

# 3. Pantau status & antrean download yang aktif
gamectl downloads

# 4. Buka game di Steam resmi tanpa unduh aset (Zero-Download Full DLC)
gamectl unlock <appid> [title]

# 5. Injeksi GBE Fork, konfigurasi save ./saves, dan auto-DLC
gamectl inject /path/to/game [appid] [--no-sync|--all]

# 6. Unduh & tulis daftar DLC Steam ke steam_settings/DLC.txt
gamectl fetch-dlc /path/to/game [appid]

# 7. Sinkronisasi dual-mode Steam Client resmi & SLSsteam full DLC (dengan direktori game)
gamectl sync-steam <appid> [title] [game_dir]

# 7. Tampilkan daftar game terdeteksi dalam format teks deterministik
gamectl --list

# 8. Cari game di Steam Store API dan cek kompatibilitas ProtonDB
gamectl --search

# 9. Sinkronisasi manual direktori game ke host companion
gamectl --sync /path/to/game "Game Title"

# 10. Buat snapshot manual savegame dari terminal
gamectl --backup /path/to/game

# 11. Tampilkan panduan ringkas
gamectl --help

# 12. Tampilkan versi aktif
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
