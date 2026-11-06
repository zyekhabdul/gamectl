# RFC: Windows Platform Support via Native PowerShell Engine (Dual-Engine Architecture)

- **Status**: [PROPOSED / APPROVED_IN_PRINCIPLE]
- **Target Work Packet**: Work Packet 13 (Windows Platform Expansion)
- **Author**: Antigravity & User Pair
- **Date**: 2026-11-06

---

## 1. Konteks & Sasaran Arsitektur

### 1.1 Evaluasi & Pergantian Pendekatan Awal
Pendekatan awal berbasis *Unified POSIX Bridge (Git Bash / MSYS2)* dievaluasi ulang dan dihentikan atas pertimbangan adopsi global:
1. **Barrier to Entry Fatal**: Git Bash bukan komponen default Windows. Memaksa gamer desktop atau pengguna handheld PC (ROG Ally, Lenovo Legion Go, MSI Claw) menginstal Git terlebih dahulu menciptakan friksi adopsi yang masif.
2. **Penalti Fork Windows NT**: Emulasi `fork()` pada MSYS2/Cygwin berjalan 10x-30x lebih lambat daripada native Linux kernel, memicu latency dan UI stuttering pada parsing data dan subshell `fzf --preview`.

### 1.2 Sasaran Strategis: Dual-Engine Sovereign
Sasaran arsitektur ini adalah menghadirkan dukungan native Windows 10 & Windows 11 melalui **Native PowerShell Engine (`.ps1`)**, membentuk arsitektur **Dual-Engine Sovereign**:
- **Linux Engine**: Tetap 100% POSIX Bash (`src/*.sh` -> `bin/gamectl`) untuk Linux purists dan Steam Deck. Zero bloat, sub-80ms startup, cgroups v2, dan bwrap sandboxing.
- **Windows Engine**: Native PowerShell (`src_win/*.ps1` -> `bin/gamectl.ps1` + `bin/gamectl.cmd`). Pre-installed pada 100% sistem Windows, zero external shell dependency, dan akses langsung ke Win32 API serta .NET runtime.

---

## 2. Gap Analysis & Rencana Solusi Arsitektural

| Sub-Sistem | Linux Engine (POSIX Bash) | Windows Engine (Native PowerShell) | Solusi Arsitektural Windows |
| :--- | :--- | :--- | :--- |
| **Shell & Runtime** | POSIX Bash 4.x/5.x | Windows PowerShell 5.1 & PowerShell Core 7+ | Basis kode terpisah di `bin/gamectl.ps1` yang kompatibel penuh dengan Windows PowerShell 5.1 (bawaan Windows 10/11). |
| **Entrypoint / Shim** | Standalone executable di `~/.local/bin/gamectl` | Batch wrapper `gamectl.cmd` & `gamectl.bat` | Wrapper CMD meneruskan argumen dengan `-NoProfile -ExecutionPolicy Bypass` untuk memintas restriksi security policy Windows. |
| **Game Execution** | Runner Wine / Proton / UMU (`find_runner`) | **Direct Native Win32 PE (.exe)** | Bypass total setup Wine/Proton dan folder `pfx/`. Luncurkan proses langsung via `Start-Process` dengan working directory di folder game. |
| **Process Tree Isolation** | `cgroups v2` (`systemd-run --user --scope`) | **Win32 Job Objects / Process Tree Tracking** | Bungkus PID game dan child process (crash reporter, overlay) menggunakan Win32 Job Object atau terminasi tree rekursif (`Stop-Process -Id $pid -Force`). |
| **Security Sandboxing** | Bubblewrap (`bwrap`) tmpfs/namespaces | Windows Integrity Level / Token Restricted | Karena `bwrap` tidak ada di Windows, flag `--sandbox` beroperasi sebagai safe no-op dengan informasi diagnostik, atau token restricted jika elevation aktif. |
| **Steam & Library Discovery**| `~/.local/share/Steam/steamapps/libraryfolders.vdf` | Registry Windows + Multi-Drive Probing | Query registry `HKCU:\Software\Valve\Steam\SteamPath` untuk primary library. Enumerasi partisi drive Windows (`C:\Games`, `D:\Games`, `E:\Games`). |
| **Filesystem & Linking** | POSIX symlink `ln -sf` | **NTFS Directory Junctions** | Gunakan `New-Item -ItemType Junction` (ekivalen `mklink /J`) yang tidak memerlukan hak akses Administrator untuk mapping save dan Steam common. |
| **Emulation Layer (GBE)** | Dual-Arch (Linux `.so` + Windows `.dll`) | 100% Windows DLLs (`steam_api.dll` / `steam_api64.dll`) | Salin template DLL target ke direktori game. Simpan template lokal di `%LOCALAPPDATA%\gamectl\gbe-fork\`. |
| **TUI & Selection Engine** | `fzf` dari package manager Linux | Standalone `fzf.exe` Windows | Auto-probe `fzf.exe` di `$env:PATH`. Jika absen, download standalone single-binary `fzf.exe` otomatis ke `%LOCALAPPDATA%\gamectl\bin\`. |
| **Asset Downloader** | `DepotDownloader-linux-x64.zip` | `DepotDownloader-windows-x64.zip` | Unduh runtime Windows dan panggil `DepotDownloader.exe` via `Start-Process`. |

---

## 3. Invarian Desain & Mitigasi Gotchas Windows

### Invarian 1: Zero Linux Regression & Complete Decoupling
Arsitektur engine Windows tidak boleh menyentuh atau memodifikasi modul runtime Linux di `src/`. Linux tetap menggunakan POSIX Bash tanpa dependensi PowerShell (`pwsh`).

### Invarian 2: Strict PowerShell 5.1 Baseline (Zero PS7 Assumptions)
Windows 10/11 hanya menjamin ketersediaan Windows PowerShell 5.1 (`powershell.exe`). Kode PowerShell `gamectl.ps1` dilarang menggunakan fitur eksklusif PowerShell 7+ (seperti operator ternary `?:`, null-coalescing `??`, atau flag pipeline baru) agar dapat berjalan instan pada instalasi Windows bersih.

### Invarian 3: ExecutionPolicy Immunity via CMD Wrapper
File `bin/gamectl.cmd` menjadi entrypoint resmi di Windows:
```cmd
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gamectl.ps1" %*
```
Ini memastikan `gamectl` dapat dipanggil dari CMD, PowerShell, Windows Terminal, Run dialog (`Win+R`), maupun shortcut desktop tanpa memicu `PSSecurityException`.

### Invarian 4: Contract & Data Layout Parity
Semua artefak konfigurasi offline wajib kompatibel 100% antara Linux dan Windows:
- File identifier: `steam_appid.txt`
- Struktur emulasi: `steam_settings/configs.user.ini` dan `steam_settings/DLC.txt`
- Struktur savegame: `./saves/<appid>/remote/`
Format ini memungkinkan drive eksternal atau partisi game portabel dimainkan bergantian antara Linux (Steam Deck) dan Windows (Handheld/Desktop) tanpa konversi data.

---

## 4. Blueprint Rencana Kerja (Work Packet 13 Chunks)

### Chunk 1: Windows Bootstrapper & PowerShell Core Skeleton
- Buat `bin/gamectl.cmd` dengan parameter forwarding dan bypass policy.
- Scaffold `bin/gamectl.ps1` dengan parser CLI (`--help`, `--version`, `launch`, `doctor`, `inject`, `list`).
- Implementasikan ANSI color tokens yang kompatibel dengan ConPTY / Windows Terminal.

### Chunk 2: Native Steam Registry & Multi-Drive Discovery
- Implementasikan fungsi `Get-SteamRoot` via Registry Windows:
  `Get-ItemPropertyValue -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath"`
- Implementasikan parser `libraryfolders.vdf` di PowerShell untuk mendeteksi seluruh library Steam di Windows.
- Tambahkan auto-scanner untuk folder portabel di drive root (`C:\Games`, `D:\Games`, `E:\Games`).

### Chunk 3: Win32 Native Execution Engine & Live HUD Controller
- Implementasikan `Invoke-GameLaunch`:
  - Validasi biner target `.exe`.
  - Backup snapshot savegame 3-slot (`slot1`, `slot2`, `slot3`).
  - Eksekusi proses via `Start-Process -FilePath $gbin -WorkingDirectory $gdir -PassThru`.
- Buat Live Controller HUD di PowerShell (PID monitoring, log streaming via `Get-Content -Tail -Wait`, dan graceful/force kill via `Stop-Process -Id $pid -Force`).

### Chunk 4: GBE Fork DLL Injection & NTFS Junction Save Mapping
- Implementasikan `Invoke-GbeInject` untuk arsitektur Windows (x86 vs x64).
- Unduh dan ekstrak template resmi `steam_api.dll` & `steam_api64.dll` ke `%LOCALAPPDATA%\gamectl\gbe-fork\`.
- Implementasikan save redirection dan symlink menggunakan NTFS Directory Junction (`New-Item -ItemType Junction`).

### Chunk 5: Standalone Downloader & Tool Auto-Fetcher
- Implementasikan downloader bootstrapping untuk Windows:
  - `fzf.exe` (Windows x64 standalone).
  - `DepotDownloader.exe` (Windows x64 single file).
- Simpan tool biner pendukung di `%LOCALAPPDATA%\gamectl\bin\` dan daftarkan sementara ke `$env:PATH`.

### Chunk 6: Turnkey One-Liner Installer (`install.ps1`) & Distribution Manifests
- Buat installer turnkey PowerShell `install.ps1`:
  ```powershell
  irm https://raw.githubusercontent.com/zyekhabdul/gamectl/main/install.ps1 | iex
  ```
  Menyalin script ke `%LOCALAPPDATA%\gamectl`, mendaftarkan `%LOCALAPPDATA%\gamectl\bin` ke `User Path`, dan membuat shortcut Start Menu/Desktop.
- Buat manifest distribusi [Scoop](https://scoop.sh) (`packaging/scoop/gamectl.json`) dan template [Winget](https://github.com/microsoft/winget-pkgs).

### Chunk 7: Regression Harness & Contract Verification
- Tambahkan skrip verifikasi otomatis pada CI (`tests/test_windows_contract.sh` atau Pester test `tests/gamectl.Tests.ps1`).
- Validasi paritas data schema antara engine Bash dan engine PowerShell.
- Pastikan regression test Linux (`tests/test_cli.sh`) tetap menghasilkan 59/59 passing dengan Exit Code 0.
