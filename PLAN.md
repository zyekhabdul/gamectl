# WORK PACKET 3: WINDOWS RUNNER SUPPORT, GBE DUAL-ARCH & RUNTIME WRAPPERS
Track: Maintenance

## 1. Objective & Scope
Memperluas kapabilitas `gamectl` agar mendukung ekosistem game Windows (.exe) dan kebutuhan kustomisasi gamer/modder tingkat lanjut di Linux/Wayland:
- Dual-architecture GBE Fork injection (Linux ELF `.so` + Windows `.dll`).
- Headless runner discovery (umu-run, Proton-GE, Wine) dengan prefix terisolasi (`$GAME_DIR/pfx`).
- Tooling wrapper modular (`gamemoderun`, `mangohud`, `gamescope` FSR/scaling).
- Multi-identity GBE manager (`gamectl set-id`) untuk multiplayer LAN tanpa bentrok SteamID.

---

## 2. Granular Work Chunks (Max 10)

- [x] **Chunk 1: Template Audit & Dual-Architecture GBE Injection (Windows DLL)**
  - Tambahkan audit template GBE Fork Windows (`steam_api64.dll` dan `steam_api.dll`) di `install.sh`.
  - Perbarui `inject_game` di `bin/gamectl` agar mendeteksi arsitektur target Windows (64-bit vs 32-bit).
  - Lakukan backup `.dll` asli ke `.dll.orig` dan pasang shim GBE Windows yang sesuai.
  - DoD: `gamectl inject` berhasil mendeteksi dan menginjeksi game berbasis biner Windows di samping binary Linux native.

- [x] **Chunk 2: Isolated Proton / Wine Prefix & Headless Runner Wrapper**
  - Implementasikan fungsi pencarian runner di `bin/gamectl` (prioritas: `umu-run` -> `GE-Proton` / `Proton` Steam -> `wine`).
  - Konfigurasikan inisialisasi Wine prefix terisolasi di direktori lokal game (`$GAME_DIR/pfx`).
  - Perbarui `find_game_binary` dan `launch_game` agar mampu meluncurkan biner `.exe` melalui runner terpilih dengan prefix terisolasi.
  - DoD: Menjalankan game Windows mengeksekusi runner yang valid dengan prefix lokal tanpa mengotori `~/.wine` di sistem host.

- [ ] **Chunk 3: Runtime Performance & Display Wrappers (GameMode, MangoHud, Gamescope)**
  - Deteksi ketersediaan `gamemoderun`, `mangohud`, dan `gamescope` pada sistem host.
  - Tambahkan argumen peluncuran fleksibel di CLI/TUI (`--hud`, `--fsr`, `--gamescope`, `--gamemode`).
  - Sediakan konfigurasi default persist di `~/.config/gamectl/wrappers`.
  - DoD: `launch_game` mampu merangkai wrapper (contoh: `gamemoderun mangohud gamescope -- <runner> <binary>`) secara deterministik saat diaktifkan.

- [ ] **Chunk 4: LAN Multi-Identity & SteamID Manager (`gamectl set-id`)**
  - Buat subcommand `gamectl set-id <player_name> [steamid]` dan helper generator SteamID acak yang valid.
  - Mutasi otomatis `steam_settings/configs.user.ini` pada game target atau direktori aktif.
  - Sediakan opsi scaffolding `steam_settings/custom_broadcasts.txt` untuk deteksi IP LAN teman bermain.
  - DoD: Perintah `gamectl set-id "Player2"` menghasilkan SteamID unik dan nama akun terpisah guna mencegah konflik sesi multiplayer offline.

- [ ] **Chunk 5: Shell Autocompletion, CLI Help & Panduan Dokumentasi**
  - Perbarui `completions/gamectl.bash` untuk subcommand `set-id` dan flag-flag wrapper baru (`--hud`, `--gamescope`, dll).
  - Perbarui `README.md` dan `docs/GUIDE.md` dengan panduan penggunaan runner Windows, template GBE DLL, dan integrasi wrapper.
  - DoD: `gamectl --help` menampilkan panduan perintah baru dan bash completion merespons input dengan presisi.

- [ ] **Chunk 6: Verifikasi Empiris & RAG Checkpoint**
  - Jalankan audit sintaks (`bash -n bin/gamectl install.sh completions/gamectl.bash`).
  - Lakukan dry-run verifikasi injeksi DLL dan eksekusi runner wrapper.
  - Catat checkpoint aktif ke `00-AGY-Memory/gamectl/STATE.md` via `agy-guard checkpoint`.
  - DoD: Seluruh pemeriksaan sintaks dan eksekusi menghasilkan exit code 0.
