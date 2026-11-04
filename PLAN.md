# WORK PACKET 6: SOVEREIGN GAMER HUD TUI OVERHAUL & DRIVER SAFETY GATE [COMPLETED]

## 1. Objective & Scope
Transform `gamectl`'s user interface from raw shell prompts into a world-class, international-grade "Sovereign Gamer HUD" terminal experience. Leverage `fzf`'s native rounded borders and Tokyo Night/Catppuccin color palette with standard Unicode 1.1 box drawing (`╭─╮`, `│`, `╰─╯`, `•`), English-first terminology, high-density pill badges, and eliminate all primitive text dumps. Fix the Intel Haswell / Terraria OpenGL threading crash by removing hardcoded `mesa_glthread=true` and converting it into a configurable wrapper toggle.

---

## 2. Granular Chunks & Definition of Done (DoD)

### Chunk 1: Driver Safety & Performance Gate (Terraria/Haswell Fix) [VERIFIED]
- **Target**: `bin/gamectl` (`launch_game()`, `build_wrapper_command()`, `configure_wrappers()`)
- **DoD**:
  1. Hapus `export mesa_glthread=true` yang di-hardcode secara global di `launch_game()`. [DONE]
  2. Tambahkan opsi `glthread=0|1` (Mesa GL Threading) ke dalam `.wrappers` per game (default: nonaktif/aman). [DONE]
  3. Izinkan toggle GL Threading di `configure_wrappers()` dan baca di `build_wrapper_command()`. [DONE]

### Chunk 2: Theme Engine & English-First ANSI Pill Badges [VERIFIED]
- **Target**: `bin/gamectl`
- **DoD**:
  1. Standarisasi ANSI escape codes (Tokyo Night / Gamer Dark: Cyan, Purple, Green, Amber, Ice, Dim). [DONE]
  2. Definisikan pill badges hotkey inverse (`ENTER`, `CTRL-I`, `CTRL-O`, `CTRL-P`, `CTRL-F`, `CTRL-D`, `CTRL-S`, `CTRL-B`, `CTRL-K`, `ESC`). [DONE]
  3. Konfigurasi `FZF_DEFAULT_OPTS` terpusat: background transparan (`bg:-1`), border rounded, pointer `▶`, marker `*`, scrollbar `│`. [DONE]

### Chunk 3: Library Menu & Game Preview HUD Redesign [VERIFIED]
- **Target**: `bin/gamectl` (`scan_installed_games()`, `preview_game()`, `library_menu()`)
- **DoD**:
  1. `scan_installed_games --formatted`: Output AppID warna dim, nama game tebal, status pill badges (`[GBE_FORK]`, `[VALVE_SO]`, `[VALVE_DLL]`, `[STANDALONE]`). [DONE]
  2. `preview_game()`: Box-drawing frame terstruktur (Game Details, Storage & Savegame, Performance Wrappers, LAN Co-op & Identity, Shortcut Deck). [DONE]
  3. Tambahkan alias `list-formatted` dan `--list-formatted` di `case "${1:-}"`. [DONE]

### Chunk 4: Master Dashboard Hub & Cockpit Preview Redesign [VERIFIED]
- **Target**: `bin/gamectl` (`preview_dashboard()`, `dashboard_menu()`)
- **DoD**:
  1. `preview_dashboard()`: Box frame high-density menampilkan Host OS, Display Stack, Games Loaded, Runner, GBE Templates, Tooling, dan modul terpilih. [DONE]
  2. `dashboard_menu()`: Menu list `[01]`..`[06]` dalam bahasa Inggris yang bersih dengan border rounded dan sub-deskripsi rapi. [DONE]

### Chunk 5: Submenu Modernization (Wrappers, Persona, Global Config) [VERIFIED]
- **Target**: `bin/gamectl` (`configure_wrappers()`, `configure_global()`, `set_id_interactive()`)
- **DoD**:
  1. `configure_wrappers()`: Menu berbingkai rapi dengan status toggle `[ACTIVE]` (hijau) vs `[OFF]` (dim) dan preset cepat. [DONE]
  2. `configure_global()`: Box-framed menu untuk Persona LAN, Default Wrappers, Custom Libraries, dan Remote Companion Sync. [DONE]
  3. `set_id_interactive()`: Box-framed form untuk identitas LAN dan broadcast peers. [DONE]

### Chunk 6: Search & Download Monitor TUI Redesign [VERIFIED]
- **Target**: `bin/gamectl` (`search_steam()`, `list_downloads_interactive()`)
- **DoD**:
  1. `search_steam()`: Border label rounded, status badge `[INSTALLED]` / `[NOT INSTALLED]`, ProtonDB audit tier badges (`[PLATINUM]`, `[GOLD]`, dll.). [DONE]
  2. `list_downloads_interactive()`: Box-framed list dengan status `[RUNNING]` / `[COMPLETED]` dan menu aksi streaming / terminasi proses yang rapi. [DONE]

### Chunk 7: System Diagnostics (Doctor) HUD Redesign [VERIFIED]
- **Target**: `bin/gamectl` (`doctor_audit()`)
- **DoD**:
  1. Format output 7-layer audit dengan header berbingkai, layer status pills (`[READY]`, `[WARN]`, `[MISSING]`), dan hardware GPU mitigation advice. [DONE]

### Chunk 8: Machine Verification & Local Checkpoint [VERIFIED]
- **Target**: `bin/gamectl`, `completions/gamectl.bash`, Git & Obsidian RAG
- **DoD**:
  1. `bash -n bin/gamectl` dan `bash -n completions/gamectl.bash` (exit code 0). [PASS]
  2. Uji cetak non-interaktif `gamectl --preview-dashboard 1`, `gamectl --list-formatted`, `gamectl doctor`. [PASS]
  3. Verifikasi eliminasi crash `mesa_glthread` pada Terraria. [PASS]
  4. Local git commit dan sinkronisasi Obsidian RAG `STATE.md` & `INDEX.md`. [PASS]
