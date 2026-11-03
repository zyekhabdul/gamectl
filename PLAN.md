# WORK PACKET 2: ENVIRONMENT HARDENING & TURNKEY SETUP
Track: Maintenance

## 1. Objective & Scope
Memperkuat instalasi dan kesiapan lingkungan `gamectl` agar bersifat *turnkey* (siap pakai di mesin Linux manapun) dengan scaffolding konfigurasi otomatis, audit dependensi lengkap, fallback YAML parser yang tahan banting, integrasi shell auto-completion, dan desktop entry untuk Wayland application launcher.

---

## 2. Granular Work Chunks (Max 10)

- [x] **Chunk 1: Audit Dependensi & Template GBE di `install.sh`**
  - Tambahkan `unzip` dan `python3` ke daftar dependensi wajib di `install.sh`.
  - Tambahkan pengecekan keberadaan template biner GBE Fork (`~/.local/share/gbe-fork/regular/x64/libsteam_api.so`).
  - Berikan panduan terminal jika template GBE belum tersedia di sistem.
  - DoD: `install.sh` memverifikasi seluruh runtime dependensi dengan pesan diagnostik yang jelas.

- [x] **Chunk 2: Scaffolding Konfigurasi Default (`~/.config/gamectl/`)**
  - Di `install.sh`, buat direktori `~/.config/gamectl/` jika belum ada.
  - Sediakan file template bertag komentar:
    - `~/.config/gamectl/libraries.example` (petunjuk penambahan path game custom).
    - `~/.config/gamectl/steam_user.example` (petunjuk penambahan akun Steam untuk DepotDownloader).
  - DoD: Menjalankan `./install.sh` menginisialisasi direktori config dan file template tanpa menimpa config yang sudah ada.

- [x] **Chunk 3: Resilient YAML Engine Fallback di `bin/gamectl` (`sync_steam`)**
  - Perbarui inline Python script di `sync_steam` untuk mencoba `ruamel.yaml` terlebih dahulu (guna mempertahankan quotes dan komentar).
  - Jika `ruamel.yaml` tidak terpasang (`ImportError`), fallback otomatis ke pustaka standar `yaml` (PyYAML).
  - DoD: `gamectl sync-steam` dan `gamectl unlock` tetap berhasil memutasi `config.yaml` baik menggunakan `ruamel.yaml` maupun `PyYAML`.

- [x] **Chunk 4: Shell Autocompletion untuk Bash & Zsh**
  - Buat skrip completion `completions/gamectl.bash` di repositori.
  - Lengkapi completion untuk seluruh subcommands (`download`, `downloads`, `unlock`, `inject`, `fetch-dlc`, `sync-steam`, `ensure-downloader`, `--search`, `--list`, `--sync`, `--backup`, `--help`, `--version`).
  - Lengkapi completion untuk flag download (`--raw`, `--inject-only`, `--all`, `-f`, `--foreground`).
  - Di `install.sh`, otomatis pasang completion ke `~/.local/share/bash-completion/completions/gamectl`.
  - DoD: Menekan `<TAB>` pada `gamectl ` di terminal Bash memunculkan daftar subcommand dan opsi secara akurat.

- [ ] **Chunk 5: Desktop Application Entry (`gamectl.desktop`)**
  - Buat file `gamectl.desktop` di repositori.
  - Konfigurasikan spesifikasi Freedesktop XDG (`Type=Application`, `Categories=Game;Utility;`, `Exec=sh -c '...'`).
  - Otomatis deteksi terminal emulator yang tersedia (`foot`, `alacritty`, `kitty`, `ghostty`, atau `xterm`) agar kompatibel dengan launcher Niri/Wayland (fuzzel, rofi, wofi).
  - Di `install.sh`, otomatis pasang file ke `~/.local/share/applications/gamectl.desktop`.
  - DoD: File desktop tervalidasi via `desktop-file-validate` (bila terpasang) dan terdaftar di `~/.local/share/applications/`.

- [ ] **Chunk 6: Pembaruan Dokumentasi & Uji Verifikasi Empiris**
  - Perbarui `README.md` dan `docs/GUIDE.md` untuk mendokumentasikan file konfigurasi, template, autocompletion, dan desktop entry.
  - Jalankan pengujian empiris end-to-end: `./install.sh`, uji completion, uji syntax `bash -n bin/gamectl`, uji fallback YAML.
  - DoD: Seluruh pengujian menghasilkan exit code 0 dan checkpoint RAG tersimpan.
