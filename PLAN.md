# WORK PACKET 26: TUI ERGONOMICS, HEADER STREAMLINING & PREVIEW I/O OPTIMIZATION

- Track: Maintenance / TUI Ergonomics / Visual Streamlining / I/O Latency Optimization / Zero-Bloat
- **Status**: IN PROGRESS [4/5 CHUNKS EXECUTED]
- **Target Branch**: `main`
- **Binding Purpose**: [Sovereign Original Purpose](docs/SOVEREIGN_ORIGINAL_PURPOSE.md) — lightweight, standalone, stable Steam replacement.
- **Operational Directive**: Executing sequentially under review mode (Option 2).

---

## 1. OBJECTIVE & ARCHITECTURAL RATIONALE

Audit visual dan runtime performance menemukan tiga area friksi dan inefisiensi:
1. **Visual Redundancy & Truncation**:
   - Dialog FZF mengulang judul modul di border atas dan awal baris `--header`.
   - Di Game Library, baris kedua header berisi string shortcut 214 karakter yang 100% terpotong (`··`) di panel kiri (lebar ~45%), sekaligus menduplikasi kotak `KEYBOARD SHORTCUTS` di panel kanan preview.
2. **Disk I/O Thrashing di Preview Pane**:
   - Setiap pergerakan kursor panah (naik/turun) di Game Library memicu eksekusi sinkron `du -sh "$gdir"` dan `du -sh "$gdir/saves"`. Pada game berukuran puluhan gigabyte, ini memicu disk thrashing dan lag navigasi.
   - Game berlisensi Steam sudah memiliki file manifest `appmanifest_${appid}.acf` dengan metadata `"SizeOnDisk"`. Membaca langsung nilai ini beroperasi secara instan ($O(1)$) tanpa penelusuran pohon direktori ($O(N)$).
3. **Multi-Pass Subshell di Dashboard Preview**:
   - `preview_dashboard()` memanggil 3 kali `find` + 1 kali `du` secara independen setiap kali menu Dashboard aktif.

---

## 2. CHUNK BREAKDOWN & DEFINITION OF DONE (DoD)

### [x] Chunk 26.01: Game Library Header Streamlining [VERIFIED]
- **Target File**: `src/tui/70_dashboard.sh` (`library_menu`)
- **Scope**:
  - Hapus duplikasi kata `GAME LIBRARY` dan string 214-karakter shortcuts yang terpotong.
  - Sederhanakan header menjadi 1 baris esensial:
    `Enter: Launch │ Ctrl-F: Search │ Ctrl-D: Downloads │ Esc: Dashboard`
  - Biarkan panel kanan preview tetap menjadi Single Source of Truth (SSoT) untuk referensi shortcut lengkap.
- **DoD**:
  - Panel kiri Game Library mendapatkan tambahan 1 baris vertikal untuk menampilkan game.
  - Zero teks terpotong (`··`) pada terminal lebar standar 80 kolom.
  - Semua 135 CLI regression contracts pass exit 0.

### [x] Chunk 26.02: Auxiliary Menus Header Unification [VERIFIED]
- **Target Files**: `src/tui/70_dashboard.sh`, `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/steam/30_downloader.sh`
- **Scope**:
  - **Master Dashboard**: Sederhanakan header ke `Enter: Open │ 1-7: Quick Select │ Ctrl-L: Logs │ Esc: Exit`.
  - **Activity Logs**: Sederhanakan header ke `Ctrl-X: Clear Log │ Esc: Return`.
  - **System Diagnostics**: Sederhanakan header ke `Esc / Enter / q: Return to Dashboard`.
  - **Prefix Manager**: Sederhanakan header ke `Enter: Execute │ Esc: Return`.
  - **Runtime Wrappers**: Sederhanakan header ke `Enter: Toggle/Select │ Esc: Save & Return`.
  - **Process HUD**: Sederhanakan header ke `Enter: Execute │ Esc: Return to Library`.
  - **Download Manager**: Sederhanakan header ke `Enter: Actions │ Ctrl-K: Pause │ Esc: Back`.
- **DoD**:
  - Tidak ada menu yang mengulang judul modulnya sendiri jika sudah tercantum pada `--border-label`.
  - Format seragam di seluruh subsistem TUI.
  - Semua 135 CLI regression contracts pass exit 0.

### [x] Chunk 26.03: O(1) Instant ACF Size Resolution in `preview_game` [VERIFIED]
- **Target File**: `src/tui/70_dashboard.sh` (`preview_game`)
- **Scope**:
  - Sebelum menjalankan `du -sh "$gdir"`, periksa keberadaan `appmanifest_${appid}.acf` di `$gdir` atau di direktori steamapps induk.
  - Jika ditemukan baris `"SizeOnDisk"`, ambil nilainya dan format menggunakan helper `format_bytes` ($O(1)$ file read).
  - Untuk savegame `./saves`, gunakan kalkulasi cepat bertahap atau cache mtime.
- **DoD**:
  - Ukuran game berbasis ACF ditampilkan instan tanpa penelusuran disk rekursif.
  - Zero stuttering saat menahan tombol panah atas/bawah di Game Library.
  - Test contract `test_preview_game_acf_instant_size_resolution_contract` pass (136/136 tests pass exit 0).

### [x] Chunk 26.04: Aggregated Dashboard Cache Evaluation [VERIFIED]
- **Target File**: `src/tui/70_dashboard.sh` (`preview_dashboard`)
- **Scope**:
  - Gabungkan pemindaian file cache (`find` dan `du`) ke dalam satu pass loop shell dengan 60s TTL cache saat menu `[02]` disorot.
- **DoD**:
  - Menghilangkan 3 subshell eksternal per navigasi item Dashboard.
  - Test contract `test_preview_dashboard_cache_aggregation` pass (Exit 0).

### Chunk 26.05: Deterministic Machine Harness Verification
- **Target Files**: `tests/test_cli.sh`, `tests/test_tui_safety.py`
- **Scope**:
  - Jalankan `./scripts/build.sh` untuk sinkronisasi binary `bin/gamectl`.
  - Verifikasi `./scripts/build.sh --check` (Exit 0).
  - Verifikasi `make lint` (Exit 0).
  - Verifikasi `bash tests/test_cli.sh` (135/135 contracts pass).
  - Verifikasi `python3 -m unittest discover -s tests` (42/42 tests pass).
- **DoD**:
  - Seluruh test suite lulus dengan Exit Code 0 tanpa regresi.

---

## 3. NEXT MILESTONE (POST-PACKET 26)

Setelah efisiensi TUI dan I/O latency Packet 26 selesai dan diverifikasi:
- **Packet 27: Windows Native Engine & Multi-Platform Packaging**
  - Implementasi PowerShell native runner (`gamectl.ps1`).
  - Audit packaging Windows & cross-platform distribution.
