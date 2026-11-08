# PROPOSAL: Clean TUI Lifecycle, Centralized Runtime Logs & Technical Debt Elimination

- **Status**: PROPOSAL (RFC)
- **Author**: Antigravity Technical Mentor
- **Scope**: TUI Screen Discipline, Logging Subsystem, Dangling Feature Remediation
- **Target Invariant**: Zero Terminal Clutter on Exit ("Clean Outside"), 100% In-Dashboard Ergonomics

---

## 1. Problem Statement

Saat ini, `gamectl` memiliki beberapa masalah ergonomi terminal dan inkonsistensi arsitektur:

1. **Terminal Clutter on Exit ("Kotor")**:
   - Sub-proses (`download_game`, `inject_game`, `doctor_audit`, `sync_steam`) mencetak langsung ke stdout/stderr di *Primary Screen Buffer*.
   - Saat keluar dari `dashboard_menu` (menekan Esc), seluruh tumpukan output teks tertinggal di riwayat scrollback terminal shell pengguna.
2. **Settings Keluar dari Dashboard (Raw Shell Dropouts)**:
   - Menu `[05] GLOBAL SETTINGS` (`configure_global`), `[06] SYSTEM DIAGNOSTICS` (`doctor_audit`), serta modal konfigurasi wrappers (`configure_wrappers`) dan persona (`set_id_interactive`) keluar dari engine FZF dan menggunakan bash kuno: `clear` + `read -r -p "Select option [1-5]: "`.
   - Ini merusak pengalaman TUI modern dan meninggalkan artefak prompt di terminal.
3. **Fitur Menggantung & Phantom State (Steam Entitlement / Ghost ACF)**:
   - Menu `[04] STEAM ENTITLEMENT & ACF` (`unlock_game`) membuat file `appmanifest_<appid>.acf` dengan `StateFlags: 4` (Installed) dan folder kosong di `steamapps/common/`.
   - Tanpa file game nyata, game tampil di Steam dan `gamectl` sebagai "INSTALLED", namun saat ditekan Play akan gagal dengan error `Missing executable` atau corrupt state.
   - Fitur ini merupakan peninggalan era SLSsteam (ADR-005) yang bertentangan dengan arsitektur berdaulat mandiri (ADR-022: Larangan Ketergantungan Steam Client).
4. **Download Monitor Tidak Menangkap Download Standalone**:
   - Menu `[03] DOWNLOAD MONITOR` (`list_downloads_interactive`) hanya memindai `appmanifest_*.acf` milik Steam Client resmi.
   - Unduhan yang berjalan via native engine `gamectl-depot-dl` (sovereign CDN) tidak terdeteksi di menu unduhan ini.

---

## 2. Standar Industri / Tren Modern (Crowd Standards Benchmark)

Berdasarkan benchmark standar TUI modern (`lazygit`, `k9s`, `btop`, `yazi`, `ranger`, `lazydocker`):

| Aspek | Tren Standar Modern | Status gamectl Saat Ini | Target Perbaikan |
| :--- | :--- | :--- | :--- |
| **Layar Terminal saat Exit** | 100% Bersih (Alternate Screen Buffer `smcup`/`rmcup`) | Kotor (Stdout bleed di primary buffer) | Bersih total via trap `rmcup` |
| **Sub-Settings / Dialog** | In-TUI Modals / Popups (FZF floating / nested) | Raw shell `clear` + `read -r -p` | 100% In-Dashboard FZF Modal |
| **Log Operasional** | Viewable in-app + auto-rotating file | Dicetak ke stdout terminal, hilang saat clear | Terpusat di `gamectl.log` + In-Dashboard Viewer |
| **Eksekusi Game** | Suspends TUI cleanly, resumes on game exit | Suspends, tapi meninggalkan log di terminal | Suspends, logs dialihkan ke runner log, resumes TUI |

---

## 3. Rencana Arsitektur & Remediasi

### A. Terminal Screen Discipline (Clean Outside)
- Bungkus sesi interaktif TUI di `src/main.sh` dan `dashboard_menu` menggunakan POSIX Alternate Screen Buffer:
  ```bash
  [ -t 1 ] && tput smcup 2>/dev/null || true
  trap '[ -t 1 ] && tput rmcup 2>/dev/null || true' EXIT INT TERM
  ```
- Perintah headless CLI (seperti `gamectl doctor`, `gamectl list-formatted`) **tidak menggunakan** alternate screen agar tetap ramah Unix pipe.

### B. In-Dashboard Unified Logging Subsystem
- Seluruh log operasional diarahkan ke file terisolasi:
  `${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}/gamectl.log`
- Dibatasi maksimal 1.000 baris (rolling buffer).
- Dashboard menyediakan menu `[07] ACTIVITY & RUNTIME LOGS` dan live card di preview pane kanan untuk membaca log tanpa keluar ke terminal.

### C. Refactor Sub-Settings ke 100% In-Dashboard FZF Modals
- Hapus seluruh penggunaan `read -r -p` dan `clear` pada:
  - `configure_global` -> Menggunakan loop FZF modal palette dengan toggle instan.
  - `configure_wrappers` -> Menggunakan multi-select atau toggling FZF palette.
  - `set_id_interactive` -> Menggunakan FZF `--print-query` modal prompt.
  - `doctor_audit` -> Ditampilkan di dalam scrollable preview / pager TUI.

### D. Resolusi Fitur Menggantung: Steam Entitlement & ACF
- **Masalah**: Menulis `appmanifest` kosong menciptakan "Ghost Game".
- **Solusi**:
  1. Hapus pendaftaran ACF kosong jika file fisik game belum terunduh.
  2. Ubah fungsi `adopt_steam` agar **hanya aktif** jika direktori game valid (`game_dir`) diberikan dan berisi binary game.
  3. Lepas `[04] STEAM ENTITLEMENT & ACF` dari menu utama Dashboard, atau ganti menjadi `[04] DOWNLOADS & ASSET MANAGER` yang terintegrasi langsung dengan progress engine native `gamectl-depot-dl`.
