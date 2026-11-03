# gamectl: Sovereign TUI Game Manager for Linux

**gamectl** adalah antarmuka Terminal User Interface (TUI) berbobot ultra-ringan (< 15 MB RAM) yang dirancang untuk mengelola, meluncurkan, dan menyinkronkan game standalone portabel di Linux tanpa ketergantungan pada client distribusi berat seperti Steam Client atau wrapper AppImage berbasis Electron/Chromium.

Dibuat khusus untuk arsitektur workstation efisien (seperti ThinkPad T440p) yang dipasangkan dengan companion node performa tinggi (`tuf-gaming-arch`).

---

## Fitur Utama

- **Zero-Bloat & Instant Startup**: Ditulis murni dalam POSIX Bash + `fzf` + `jq`. Memangkas 99% overhead memori dibandingkan client grafis konvensional.
- **Dynamic Multi-Library Autodetection**: Otomatis mendeteksi game yang terpasang dari seluruh direktori Steam (`libraryfolders.vdf` + ACF manifests), direktori portabel `~/Games/`, Lutris, serta custom path melalui `~/.config/gamectl/libraries` atau variabel `GAMECTL_LIBRARY_DIRS`.
- **Split-Pane Live Inspection**: Kolom kiri menampilkan daftar pustaka game; kolom kanan menampilkan metadata biner, arsitektur ELF (32-bit / 64-bit), status runner GBE Fork, dan ukuran savegame secara real-time.
- **Savegame Snapshot Protection (Anti-Data-Loss)**: Membuat cadangan otomatis rotasi 3-slot (`slot1`, `slot2`, `slot3`) sebelum setiap game dijalankan, melindungi progres dari dirty shutdown atau crash.
- **Dynamic Hardware Profiling**: Otomatis menggeser CPU governor ke `performance` saat sesi game aktif, dan mengembalikannya ke `powersave` begitu game ditutup.
- **One-Key Multi-Node Sync (`<Ctrl-S>`)**: Menyinkronkan progres savegame portabel langsung ke node pendamping (`tuf-gaming-arch`) via SSH/Rsync dengan proteksi pre-flight timeout 1 detik.
- **Steam & ProtonDB Discovery**: Pencarian judul game via Steam Web API publik yang terintegrasi dengan tier rating kompatibilitas Linux dari ProtonDB (Native, Platinum, Gold, Silver).
- **Self-Healing Pre-Flight**: Pembersihan otomatis file lock dan socket terlantar di `/tmp/` sebelum sesi dimulai.

---

## Keyboard Shortcuts

| Shortcut | Aksi |
| :--- | :--- |
| `<ENTER>` | Luncurkan Game Standalone (Mesa GL Threading + Snapshot Backup) |
| `<Ctrl-S>` | Sinkronisasi Savegame Portabel ke `tuf-gaming-arch` via SSH |
| `<Ctrl-B>` | Buat Snapshot Manual Savegame saat ini |
| `<ESC>` / `<Ctrl-C>` | Keluar dari Antarmuka |

---

## Instalasi Cepat

Pastikan dependensi sistem terpasang (`fzf`, `jq`, `curl`, `rsync`, `file`):

```bash
git clone git@github.com:zyekhabdul/gamectl.git
cd gamectl
./install.sh
```

Installer akan membuat symlink eksekutabel ke `~/.local/bin/gamectl` dan alias `~/.local/bin/game`.

---

## Penggunaan

1. **Buka Library Game**:
   ```bash
   gamectl
   # atau menggunakan alias:
   game
   ```

2. **Daftar Game yang Terdeteksi**:
   ```bash
   gamectl --list
   ```

3. **Cari Game di Steam Store & Cek ProtonDB**:
   ```bash
   gamectl --search
   ```

4. **Sinkronisasi Manual Direktori Tertentu**:
   ```bash
   gamectl --sync /path/to/game "Game Title"
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
├── docs/
│   ├── ARCHITECTURE.md  # Spesifikasi mendalam arsitektur headless Linux
│   └── GUIDE.md         # Panduan operasional, standalone setup & disaster recovery
├── install.sh           # Script installer otomatis ke ~/.local/bin/
├── README.md            # Dokumentasi ringkas & overview
└── .gitignore           # Filter file temporer dan cache
```
