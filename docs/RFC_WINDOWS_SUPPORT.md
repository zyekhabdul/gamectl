# RFC: Windows Platform Support via Unified POSIX Bridge

- **Status**: [PROPOSED / BACKLOG]
- **Target Work Packet**: Work Packet 4
- **Author**: Antigravity & User Pair
- **Date**: 2026-11-04

---

## 1. Konteks & Sasaran Arsitektur

Saat ini `gamectl` beroperasi pada kernel Linux (POSIX Bash) dengan asumsi display server X11/Wayland, Wine/Proton/UMU runner untuk biner Windows PE, dan path Linux (`~/.local/share/Steam`, `~/.config/gamectl`).

Sasaran RFC ini adalah memungkinkan `gamectl` berjalan pada sistem operasi **Windows 10 / 11** secara seamless menggunakan **Unified POSIX Bridge (Git Bash / MSYS2)** tanpa perlu menulis ulang (rewrite) codebase ke bahasa lain, menjaga footprint tetap ultra-lean (<15MB RAM), dan mempertahankan 1 basis kode untuk Linux dan Windows.

---

## 2. Gap Analysis & Rencana Solusi

| Sub-Sistem | Linux (Saat Ini) | Windows (Target) | Solusi Arsitektural |
| :--- | :--- | :--- | :--- |
| **OS & Shell** | `uname -s` = `Linux` | `uname -s` = `MINGW64_NT*` / `MSYS_NT*` | Deteksi `IS_WINDOWS=true` jika `uname -s` cocok dengan pattern MinGW/MSYS/Cygwin. |
| **Steam & Library Paths** | `~/.local/share/Steam/steamapps` | `C:\Program Files (x86)\Steam` atau Registry | Query registry via `reg.exe query "HKCU\Software\Valve\Steam" /v SteamPath`. Normalisasi path Windows (`D:\\...`) ke format POSIX (`/d/...`). Tambahkan autodeteksi drive (`/c/Games`, `/d/Games`, `/e/Games`). |
| **Game Execution** | Runner Wine / Proton / UMU (`find_runner`) | Eksekusi biner Windows PE (.exe) **NATIVE** | Pada Windows, bypass `find_runner`. Eksekusi biner `.exe` langsung via `"$gdir/$gbin"` atau `cmd.exe /c start "" "$gdir/$gbin"`. Tolak eksekusi biner Linux ELF. |
| **GBE Fork Injection** | Dual-Arch (Linux `.so` + Windows `.dll`) | 100% biner target adalah Windows PE (`.exe`) | Hanya gunakan template `steam_api64.dll` & `steam_api.dll`. Template default disimpan di `%LOCALAPPDATA%/gbe-fork` atau `~/.local/share/gbe-fork/windows/`. |
| **Runtime Wrappers** | `gamemoderun`, `mangohud`, `gamescope` FSR | Tidak ada native gamescope/gamemode di Windows | Bypass wrapper chaining di Windows tanpa memicu error `command not found`. |
| **Downloader Engine** | `DepotDownloader-linux-x64.zip` | `DepotDownloader-windows-x64.zip` | Unduh target biner Windows dan panggil `DepotDownloader.exe`. Alihkan log ke `%TEMP%` atau `/tmp`. |
| **Steam Sync & Symlink** | `ln -sf` & `~/.config/SLSsteam` | NTFS Junction (`mklink /J`) & `%APPDATA%\SLSsteam` | Gunakan directory junction (`cmd.exe /c mklink /J`) yang tidak memerlukan hak akses Administrator untuk mapping ke `steamapps/common`. |
| **Host Entrypoint** | Bash CLI di `/usr/local/bin` atau `~/.local/bin` | CMD / PowerShell terminal | Sediakan shim launcher `gamectl.cmd` dan `gamectl.ps1` yang mendelegasikan ke `bash.exe bin/gamectl`. |

---

## 3. Blueprint Rencana Kerja (Work Packet 4 Chunks)

### Chunk 1: OS Detection & Path Normalization Gate
- Tambahkan flag `IS_WINDOWS=false`. Evaluasi `uname -s` saat bootstrap script.
- Buat fungsi pembantu `normalize_path()` untuk menerjemahkan path Windows backslash (`C:\...`) dan POSIX forward slash (`/c/...`).
- Query path instalasi Steam via `reg.exe query` dengan fallback ke default directory.

### Chunk 2: Native PE Execution & Runner Bypass
- Modifikasi `launch_game()`: Jika `IS_WINDOWS=true`, jangan panggil `find_runner` atau inisialisasi Wine prefix (`pfx/`).
- Eksekusi langsung biner `.exe` dengan argumen yang diberikan.
- Nonaktifkan chaining Linux wrapper (`gamemoderun`, `mangohud`, `gamescope`).

### Chunk 3: Windows Downloader Engine
- Modifikasi `ensure_downloader()` untuk mendeteksi `IS_WINDOWS`.
- Ambil rilis `DepotDownloader-windows-x64.zip` jika berjalan di Windows.
- Eksekusi `DepotDownloader.exe`.

### Chunk 4: Windows SLSsteam Config & NTFS Junctions
- Deteksi direktori config SLSsteam di Windows (`%APPDATA%/SLSsteam` / `/c/Users/<user>/AppData/Roaming/SLSsteam`).
- Buat junction directory `mklink /J` saat sinkronisasi `steamapps/common`.

### Chunk 5: Turnkey Shims & Installer Hardening
- Buat `gamectl.cmd`:
  ```cmd
  @echo off
  bash "%~dp0bin\gamectl" %*
  ```
- Buat `gamectl.ps1` untuk pemanggilan bersih dari PowerShell.
- Perbarui `install.sh` untuk mendeteksi environment Git Bash dan menginstal shim ke PATH pengguna.

### Chunk 6: Empirical Verification & Test Matrix
- Uji eksekusi skrip di lingkungan Linux (pastikan zero regression pada fungsi native).
- Uji mock environment Windows di Git Bash.

---

## 4. Invarian Desain
1. **Zero Linux Regression**: Seluruh percabangan Windows terisolasi di bawah `if [ "$IS_WINDOWS" = true ]`. Perilaku Linux tetap 100% utuh.
2. **Zero Bloat / YAGNI**: Tidak menambahkan runtime tambahan (seperti Node.js, Electron, dll). Cukup Git Bash yang sudah umum terpasang.
