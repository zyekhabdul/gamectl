# ANALISIS ARSITEKTUR: TUI LOGGING, EXECUTION REVIEW & SCREEN HYGIENE

- **Author**: Antigravity Linux Systems Engineering Specialist
- **Target Repo**: `/home/aomiqaza/Projects/gamectl`
- **Scope**: Terminal Buffer Discipline, Managed Action Pager, Zero-Clutter Exit Standard
- **Status**: ARCHITECTURAL ANALYSIS & MAINTENANCE BLUEPRINT

---

## 1. RINGKASAN EKSEKUTIF

Dokumen ini memuat analisis sistem mendalam dan panduan implementasi teknis untuk pemeliharaan *gamectl* di laptop pengembang. Permasalahan yang ditangani mencakup dua friksi utama antarmuka terminal (TUI):
1. **Log Tercetak di Luar Dashboard & Layar Tidak Bersih Saat Keluar**: Output eksekusi fitur inti (`inject_game`, `sync_steam`, `download_game`, `rsync`) mencetak teks mentah langsung ke file descriptor `stdout` (fd 1) dan `stderr` (fd 2), membocorkan teks di luar layout TUI FZF dan meninggalkan residu (*dirty screen*) saat keluar dari dashboard.
2. **Langsung Terlempar Kembali ke Dashboard Sehabis Fitur Dijalankan**: Event-loop di antarmuka interaktif mengevaluasi perintah lalu seketika mengeksekusi ulang `fzf` dalam hitungan milidetik. Hal ini menimpa dan menghapus seluruh status/log eksekusi sebelum pengguna sempat membacanya.

---

## 2. BEDAH FORENSIK AKAR MASALAH (ROOT CAUSE FORENSICS)

### A. Kebocoran Buffer & Layar Kotor Saat Exit
Terminal Linux modern (xterm-256color, Alacritty, Kitty, Foot) menyediakan **Alternate Screen Buffer** (mode DEC 1049: `tput smcup` / `\033[?1049h` dan `tput rmcup` / `\033[?1049l`):
- `gamectl` telah menerapkan fungsi dasar `enter_tui_screen` dan `exit_tui_screen` di `src/core/10_utils.sh`.
- **Titik Patah 1 (Mixed-Buffer Bleed)**: Di `src/tui/70_dashboard.sh` dan `src/steam/30_downloader.sh`, fungsi backend dipanggil langsung tanpa pengalihan stream (`inject_game`, `sync_steam`, `backup_save`, `sync_save_remote`). Perintah-perintah ini mengeksekusi lusinan baris `echo "[INFO] ..."` dan proses eksternal (`rsync -avzP`). Modal notifikasi seperti `tui_modal_notice` hanya menutupi 25% tinggi layar, sehingga 75% layar sisanya dipenuhi sampah teks mentah yang tidak terkelola.
- **Titik Patah 2 (Incomplete TTY Restoration)**: Saat keluar (`Esc`), `exit_tui_screen` hanya menjalankan `tput rmcup`. Ketiadaan reset kursor (`tput cnorm`), pembersihan buffer alternatif (`printf '\033[2J\033[H'`), dan perbaikan mode echo canonical (`stty echo icanon`) menyebabkan teks yang sempat bocor ke primary screen sebelum inisialisasi TUI tertinggal di sesi shell pengguna.

### B. Ketiadaan Action Review Gate (Log Tertelan FZF)
Pada menu pencarian dan palet tindakan (`src/tui/70_dashboard.sh:838-865` & `L955-L968`):
```bash
elif [ "$trigger_key" = "ctrl-a" ]; then
    if [[ "$sel_status" =~ INSTALLED ]]; then
        inject_game "$gdir" "$sel_id"
    else
        download_game "$sel_id" "$dest_dir" "$sel_name" --all --background
    fi
    # Ketiadaan Review Gate / Pause
    # Loop while seketika memanggil fzf kembali
```
- Begitu proses selesai, loop `while true` langsung memanggil `_refresh_search_results` dan membuka `fzf`.
- `fzf` fullscreen seketika membersihkan viewport layar untuk merender daftar game.
- Seluruh output diagnosa (apakah file DLL cocok, AppID valid, atau kunci AES manifest tidak ada) lenyap dalam waktu <50 milidetik.

---

## 3. STANDAR INDUSTRI TERMINAL LINUX MODERN (CROWD BENCHMARK)

Berdasarkan arsitektur TUI standar industri (`lazygit`, `k9s`, `docker-compose`, `systemd journalctl`):

| Parameter | Praktik Lama (gamectl Saat Ini) | Standar Industri Linux Modern |
| :--- | :--- | :--- |
| **I/O Routing saat TUI Aktif** | Output dicetak langsung ke stdout/stderr TTY | Seluruh output dialihkan ke buffer stream / temporary capture log |
| **Alur Sehabis Eksekusi** | Langsung refresh loop fzf (menelan log) | Menahan layar via **Action Review Pager / Receipt Modal** |
| **Kontrol Pengguna** | Otomatis kembali tanpa konfirmasi | Pengguna secara sadar menekan `Enter` / `Esc` untuk kembali ke dashboard |
| **Kondisi Layar Saat Keluar** | Meninggalkan residu / kotor (*dirty screen*) | Bersih total, kursor normal (`cnorm`), TTY mode dipulihkan sempurna |

---

## 4. CETAK BIRU IMPLEMENTASI (MAINTENANCE BLUEPRINT)

Berikut langkah-langkah konkret yang dapat diimplementasikan saat sesi maintenance di laptop:

### Langkah 1: Implementasi Helper `tui_exec_action` di `src/core/10_utils.sh`
Buat fungsi pembungkus eksekusi yang menangkap output dan menampilkannya di dalam pager FZF berbingkai rapi:

```bash
# Execute command with captured TUI review screen (Zero Raw Leaks)
tui_exec_action() {
    local action_title="$1"
    shift
    local cmd=("$@")

    local run_dir
    run_dir="$(get_runtime_dir)"
    local tmp_log="$run_dir/action_review_$$.log"
    : > "$tmp_log"

    echo "[INFO] Running: $action_title..." > "$tmp_log"
    local rc=0
    "${cmd[@]}" >> "$tmp_log" 2>&1 || rc=$?

    local status_token="${UI_GREEN}[SUCCESS]${UI_RST}"
    [ "$rc" -ne 0 ] && status_token="${UI_RED}[FAILED (Exit $rc)]${UI_RST}"

    flush_tty_input
    # Interactive Review Screen: user reads output and presses Esc/Enter to return
    fzf \
        --border-label="  ╢ Result: $action_title :: $status_token ╟  " \
        --border-label-pos=2 \
        --header="ACTION EXECUTION REVIEW (Arrows: Scroll │ Esc / Enter: Return to Dashboard)" \
        --prompt="Review > " \
        --preview="echo -e '\033[38;5;60m╭─ EXECUTION TRACE ───────────────────────────────────╮\033[0m'; cat '$tmp_log'; echo -e '\033[38;5;60m╰─────────────────────────────────────────────────────╯\033[0m'" \
        --preview-window=down:75%:border-rounded:wrap \
        --height=85% \
        --reverse < "$tmp_log" >/dev/null 2>&1 || true

    rm -f "$tmp_log" 2>/dev/null || true
    flush_tty_input
    return "$rc"
}
```

### Langkah 2: Pengkabelan Titik Eksekusi di `src/tui/70_dashboard.sh`
Gantikan pemanggilan telanjang dengan `tui_exec_action`:
1. **Search Steam Hotkeys (`src/tui/70_dashboard.sh`)**:
   - `Ctrl-A`:
     `tui_exec_action "GBE Injection & Steam Sync" inject_game "$gdir" "$sel_id"`
     atau
     `tui_exec_action "Download Game ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --all --background --os "$target_os"`
   - `Ctrl-U`:
     `tui_exec_action "Synchronize Steam Entitlement" sync_steam "$sel_id" "$sel_name" "$gdir"`
   - `Ctrl-S`:
     `tui_exec_action "Standalone GBE Injection" inject_game "$gdir" "$sel_id" --no-sync`
   - `Ctrl-D`:
     `tui_exec_action "Live Stream Download" download_game "$sel_id" "$dest_dir" "$sel_name" --all --foreground --os "$target_os"`
2. **Library Menu Hotkeys (`src/tui/70_dashboard.sh`)**:
   - `Ctrl-I`:
     `tui_exec_action "GBE Injection" inject_game "$sel_dir" "$sel_appid"`
   - `Ctrl-S`:
     `tui_exec_action "Remote Companion Save Sync" sync_save_remote "$sel_dir" "$sel_title"`
   - `Ctrl-B`:
     `tui_exec_action "Savegame Backup Snapshot" backup_save "$sel_dir"`
   - `Ctrl-R`:
     `tui_exec_action "Savegame Snapshot Restore" restore_save "$sel_dir" "$chosen_slot"`

### Langkah 3: Pengerasan Terminal Screen Hygiene di `src/core/10_utils.sh`
Perbarui `exit_tui_screen`:
```bash
exit_tui_screen() {
    if [ -t 1 ] && [ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ]; then
        printf '\033[2J\033[H' 2>/dev/null || true
        tput rmcup 2>/dev/null || printf '\033[?1049l'
        tput cnorm 2>/dev/null || printf '\033[?25h'
        stty echo icanon 2>/dev/null || true
        GAMECTL_IN_ALT_SCREEN=0
    fi
    return 0
}
```

---

## 5. CHECKLIST VERIFIKASI (DoD) UNTUK LAPTOP MAINTENANCE

Setelah mengimplementasikan perubahan di atas pada laptop:
- [ ] Jalankan `./scripts/build.sh` untuk mengompilasi modular source ke `bin/gamectl`.
- [ ] Jalankan `./tests/test_cli.sh` (pastikan 122/122 test assertion lulus dengan Exit code 0).
- [ ] Uji manual di emulator terminal:
  - Buka `gamectl dashboard` -> jalankan pencarian Steam -> tekan `Ctrl-A` atau `Ctrl-S`.
  - Pastikan layar review muncul, log terbaca jelas, dan dashboard HANYA kembali saat user menekan `Enter` atau `Esc`.
  - Keluar dari gamectl (`Esc`), pastikan layar terminal host kembali bersih tanpa sisa-sisa ANSI atau teks berceceran.
