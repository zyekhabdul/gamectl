# Arsitektur Sistem Headless CLI vs GUI Runtime pada Linux Gaming

Dokumen ini menganalisis perbandingan arsitektur teknis antara runtime berbasis Graphical User Interface (GUI) dan pendekatan Headless Command Line Interface (CLI) / Terminal User Interface (TUI) untuk manajemen aset game pada lingkungan Linux desktop berdaya rendah (low-spec).

---

## 1. Analisis Resource Footprint: GUI Engine vs Headless CLI

### 1.1 Overhead Arsitektur GUI Client
Client distribusi game modern umumnya mengadopsi arsitektur multi-proses berbasis web runtime (Chromium Embedded Framework / Qt WebEngine):
- **Proses Utama**: Mengatur lifecycle aplikasi, koneksi socket, dan window manager hook.
- **Renderer & GPU Process**: Membutuhkan alokasi frame buffer GPU dan rasterisasi tampilan UI.
- **Resource Profiling**:
  - Alokasi RAM: 800 MB hingga 1.3 GB (tersebar di beberapa proses child).
  - CPU Utilization: 15% - 25% pada prosesor dual-core (Haswell generation) saat melakukan parsing DOM dan render animasi toko/library.
  - Disk I/O: Menulis cache visual (thumbnails, shader cache, webcache) secara kontinyu ke storage lokal.

### 1.2 Efisiensi Arsitektur Headless CLI
Arsitektur headless beroperasi murni pada network layer dan file I/O tanpa display stack:
- **Single Process Execution**: Menggunakan runtime native (C++) atau framework terkompilasi (.NET Core / Go).
- **Direct Stream I/O**: Mengambil package/chunk langsung dari Content Delivery Network (CDN) ke storage tanpa render graphical interface.
- **Resource Profiling**:
  - Alokasi RAM: < 100 MB.
  - CPU Utilization: 2% - 5% (terbatas pada kalkulasi checksum SHA/MD5 dan dekompresi data stream).
  - Disk I/O: Sequential write langsung ke disk blok target.

---

## 2. Arsitektur Pipeline Pengiriman Aset (Asset Delivery Pipeline)

### 2.1 Alur Pengambilan Metadata
1. **Manifest Blueprint**: File metadata terstruktur yang berisi daftar file, direktori, ukuran byte, dan daftar chunk hash (SHA-1) yang membentuk executable game.
2. **Chunk-based Storage**: Server game modern tidak mengirimkan file utuh tunggal, melainkan potongan terkompresi (chunks) berukuran ~1 MB.
3. **Content Resolution**: Client CLI mengirimkan permintaan HTTP/2 atau TCP langsung ke CDN edge server terdekat berdasarkan geographical DNS lookup.

### 2.2 Model Staging vs Direct Assembly
- **Two-Phase Commit (GUI Client)**:
  1. Chunk diunduh ke direktori staging terpisah (`steamapps/downloading/<id>/`).
  2. Verifikasi hash selesai seluruhnya.
  3. Proses commit memindahkan (atomic rename / copy) file ke direktori utama (`steamapps/common/<game>/`).
  4. *Kelemahan*: Membutuhkan kapasitas storage hingga 2x ukuran game selama proses berlangsung.
- **Direct In-Place Assembly (Headless CLI)**:
  1. File target langsung di-alokasikan di direktori tujuan.
  2. Chunk diunduh dan didekompresi langsung ke offset byte yang sesuai.
  3. *Keuntungan*: Zero-duplicate storage requirement, sangat optimal untuk partisi storage dengan sisa ruang terbatas.

---

## 3. Komparasi Tooling Headless pada Ekosistem Linux

| Komponen | SteamCMD (Official Valve) | DepotDownloader (SteamRE) | GUI Client (Steam/Electron) |
| :--- | :--- | :--- | :--- |
| **Arsitektur** | C++ Native CLI | .NET Core Single Executable | Electron / Qt WebEngine |
| **Use-Case Utama** | CI/CD Server, Dedicated Server | Asset Downloader, Build Downgrading | Consumer Desktop End-User |
| **Display Server** | None (Headless TTY) | None (Headless TTY) | X11 / Wayland Required |
| **Memory Overhead** | ~40 MB | ~60 MB | ~1000 MB+ |
| **Scriptability** | Sangat Tinggi (Bash/Automation) | Sangat Tinggi (CLI Arguments) | Sangat Rendah |

---

## 4. Pola Isolasi Runtime & Portabilitas (Portable Game Topology)

Untuk memastikan game dapat dieksekusi secara mandiri (standalone) dan dipindahkan antar node (misal dari node ThinkPad ke node companion TUF Gaming) tanpa dependensi client:

```
[ Root Game Directory ]
├── <game_executable>             # Binary ELF (Linux native) atau Windows .exe
├── libsteam_api.so / steam_api.dll # API Shim / Emulation Layer (GBE Fork)
├── steam_appid.txt               # Identifier numerik AppID
├── steam_settings/               # Konfigurasi offline & portable save
│   └── configs.user.ini          # Mapping save lokal (local_save_path=./saves)
└── saves/                        # Progress game terisolasi di dalam folder lokal
```

### 4.1 Keuntungan Topologi Terisolasi:
1. **Host Independence**: Game tidak membaca path absolut global (`~/.local/share/...`).
2. **Atomic Synchronization**: Sinkronisasi progres game antar-mesin cukup menggunakan protokol standar Unix (`rsync` / `scp`) tanpa perlu integrasi cloud proprietary:
   ```bash
   rsync -avzP ./GameDirectory/ target-node:~/Games/GameDirectory/
   ```
3. **Zero Runtime Mutation**: Client distribusi luar tidak dapat melakukan auto-update tak terduga yang merusak binary modifikasi atau konfigurasi lokal.

---

## 5. Arsitektur TUI Terpadu: Search, Headless Download, & Auto-Deploy

Untuk menjembatani efisiensi performa CLI dengan kemudahan navigasi GUI, arsitektur dikonsolidasikan ke dalam model Terminal User Interface (TUI) berbasis `fzf`:

```
┌──────────────────────────────────────┬──────────────────────────────────────────┐
│  PENCARIAN & DAFTAR GAME (KIRI)     │  PANEL DETAIL & PREVIEW (KANAN)          │
├──────────────────────────────────────┼──────────────────────────────────────────┤
│ > limbo                              │  JUDUL       : LIMBO                     │
│ ───────────────────────────────────  │  APPID       : 48000                     │
│ > [INSTALLED]  48000   LIMBO         │  PLATFORM    : Native Linux (ELF 64-bit) │
│   [STORE]      504230  Celeste       │  PROTONDB    : PLATINUM (Skor: 0.86)     │
│   [STORE]      105600  Terraria      │  RUNNER      : GBE Fork x64 (Active)     │
│                                      │  SAVE PATH   : ./saves/48000/remote/     │
│                                      │                                          │
│                                      │  [ SHORTCUTS ]                           │
│                                      │  <ENTER>  : Launch Standalone / Install  │
│                                      │  <CTRL-S> : Sync ke tuf-gaming-arch      │
│                                      │  <ESC>    : Keluar                       │
└──────────────────────────────────────┴──────────────────────────────────────────┘
```

### 5.1 End-to-End Pipeline
1. **Discovery**: Live query ke Steam Store API (`storesearch`) dan ProtonDB API via subshell asynchronous.
2. **Headless Execution**: Pemanggilan download engine secara terisolasi di background tanpa membuka client Steam.
3. **Auto Post-Processing**:
   - Penyalinan library emulator GBE Fork (`libsteam_api.so`).
   - Pemasangan konfigurasi portable save (`local_save_path=./saves`).
   - Pembuatan script launcher otomatis di `~/.local/bin/`.
4. **State Machine Lifecycle**:
   - `[STORE]` -> Belum terpasang di disk lokal.
   - `[DOWNLOADING]` -> Proses penarikan aset berlangsung di background.
   - `[DEPLOYING]` -> Pemasangan konfigurasi portabilitas GBE Fork.
   - `[INSTALLED]` -> Siap dieksekusi atau disinkronkan ke node lain.

---

## 6. Spesifikasi Ketahanan & Optimalisasi Backend (Backend Hardening)

Untuk memastikan sistem backend beroperasi 100% stabil, deterministik, dan bebas crash pada environment Linux host:

### 6.1 Detektor Otomatis Arsitektur Biner (ELF 32-bit vs 64-bit Selector)
Game Linux terbagi menjadi dua arsitektur biner. Memasang library dengan arsitektur yang salah akan memicu crash `wrong ELF class`:
- Backend wajib melakukan inspeksi tipe ELF sebelum menyalin library emulator:
  ```bash
  ELF_TYPE=$(file -b "$GAME_BINARY" | awk '{print $1}')
  if [ "$ELF_TYPE" = "ELF" ] && file -b "$GAME_BINARY" | grep -q "32-bit"; then
      cp "$HOME/.local/share/gbe-fork/regular/x86/libsteam_api.so" "$TARGET_DIR/libsteam_api.so"
  else
      cp "$HOME/.local/share/gbe-fork/regular/x64/libsteam_api.so" "$TARGET_DIR/libsteam_api.so"
  fi
  ```

### 6.2 Gerbang Izin Eksekusi POSIX (`chmod +x` Gate)
File biner yang diunduh langsung dari CDN sering kali hanya memiliki izin baca (`0644`).
- Pipeline post-processing wajib mengeksekusi otomatisasi perizinan:
  ```bash
  chmod +x "$TARGET_DIR/$GAME_EXECUTABLE"
  ```

### 6.3 Asynchronous Non-Blocking Worker & IPC State Streaming
Menjalankan engine download secara sinkron akan membekukan antarmuka TUI.
- **Pola Background Worker**:
  1. Downloader dipanggil di subshell terpisah dengan output log di `/tmp/dl_${APPID}.log`.
  2. PID proses disimpan di `/tmp/dl_${APPID}.pid`.
  3. TUI membaca stream status non-blocking via `tail -n 1 /tmp/dl_${APPID}.log` dengan interval polling 500ms.
  4. Antarmuka TUI tetap responsif 60 FPS dan mendukung sinyal pembatalan (`kill -15 $PID`).

### 6.4 Disiplin Partisi Storage (ext4 Invariant)
- Backend menolak alokasi target pada partisi NTFS (misal mount storage eksternal non-POSIX) untuk mencegah hilangnya atribut eksekusi POSIX dan symlink failure.
- Direktori target dikunci secara deterministik ke partisi Linux native (`$HOME/Games/` atau `$HOME/.local/share/Steam/steamapps/common/`).

### 6.5 Pre-Flight Network Probing pada Multi-Node Sync
Sebelum mengeksekusi transfer rsync ke node pendamping `tuf-gaming-arch`:
- Backend melakukan uji konektivitas SSH 1 detik:
  ```bash
  ssh -q -o ConnectTimeout=1 -o BatchMode=yes tuf-gaming-arch exit
  ```
- Jika node pendamping offline atau di luar jangkauan jaringan lokal, TUI menampilkan notifikasi peringatan non-blocking tanpa membekukan sesi aktif.

---

## 7. Invarian Stabilitas Jangka Panjang & Zero-Friction UX

Untuk memastikan sistem tidak membutuhkan pemeliharaan manual dan tahan lama:

### 7.1 Pembersihan Sampah Socket & Lock Otomatis (Pre-Flight Self-Clean)
- Sebelum TUI atau launcher berjalan, sistem secara transparan menghapus socket terlantar di `/tmp/` (`/tmp/SteaMidra-*`, `/tmp/steam_chrome_*`, `/tmp/.picsbuffer.lock`) untuk mencegah isu "process already running".

### 7.2 Rotasi Snapshot Savegame (3-Slot Rolling Backup)
- Sebelum eksekusi game dimulai, launcher membuat cadangan file save otomatis ke slot `.bak1`, `.bak2`, dan `.bak3`.
- Mengeliminasi risiko korupsi file save akibat baterai habis, force kill, atau system freeze.

### 7.3 Otomatisasi Profil CPU (Dynamic Governor Switching)
- Saat game diluncurkan, scaling governor dinaikkan ke `performance` (clock 2.6 - 3.3 GHz) untuk mencegah frame pacing stutter.
- Begitu game ditutup, governor dikembalikan otomatis ke `powersave` (clock 800 MHz) untuk menghemat daya dan menjaga suhu laptop tetap dingin.

### 7.4 Kompatibilitas Tiling Niri Wayland (Window-Rules Invariant)
- Menetapkan aturan jendela di Niri agar game diluncurkan dalam mode `fullscreen` atau `floating` terpusat, mencegah distorsi ukuran kolom tiling Wayland.

### 7.5 Single-Command Universal Hub (`game`)
- Seluruh ekosistem dikonsolidasikan ke dalam satu binary script mandiri di `~/.local/bin/game` (dan symlink `~/.local/bin/gamectl`).
- User tidak perlu lagi membuka direktori sistem, mengingat nomor AppID, atau menghafal perintah terminal yang rumit.
