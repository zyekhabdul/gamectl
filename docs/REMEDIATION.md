# REMEDIATION WORK PACKET: SYSTEMIC STANDARDIZATION & ARCHITECTURAL DECOUPLING

**Track**: Architecture Decoupling / Universal TUI Harness / SSoT Consolidation  
**Status**: READY FOR IMPLEMENTATION (AWAITING USER GO-AHEAD)  
**Max Chunks**: 7 Chunks (Active Packet <= 10)  
**Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`, `src/steam/20_discovery.sh`, `src/runners/40_wrappers.sh`, `src/steam/30_downloader.sh`, `tests/test_cli.sh`, `bin/gamectl`

---

## 1. Objective & Architectural Separation (SoC)
Menghentikan siklus *monkey-patch treadmill* secara permanen dengan menerapkan prinsip arsitektur modern (Separation of Concerns: Headless Engine Domain vs TUI Presentation Layer):

1. **Headless Engine Discipline (`launch_game`)**:
   - Engine bertanggung jawab 100% atas persiapan eksekusi, spawning detached process, dan registrasi state PID.
   - Engine murni headless: 0 baris teks dekoratif ke stdout saat dipanggil dalam konteks TUI (`GAMECTL_IN_ALT_SCREEN=1`), serta tidak pernah memanggil antarmuka interaktif (`game_controller_hud`) secara mandiri.
2. **Universal TUI Subshell Execution Harness (`tui_run_engine`)**:
   - Membungkus pemanggilan fungsi engine dalam subshell terisolasi dengan `stdin < /dev/null`, mengalihkan stdout ke runtime log dan menangkap stderr secara atomik.
   - Mencegah polusi terminal scrollback, mutasi variabel shell induk, dan rusaknya trap sinyal TUI.
3. **In-Dashboard Process Management**:
   - Memindahkan manajemen proses game aktif menjadi fitur kelas satu di TUI:
     - Di `Library`: Game yang sedang `[RUNNING]` jika ditekan `Enter` membuka palet manajemen (`Stop SIGTERM`, `Force Kill SIGKILL`, `Live Log Stream`, `Return`).
     - Di `Master Dashboard`: Status cockpit menampilkan ringkasan proses aktif dengan hotkey `<Ctrl-P>` untuk akses langsung ke Process Controller.
     - Tanpa modal interupsi popup yang menyela saat launch sukses (seamless background start seperti Steam/Lutris).
4. **Canonical TUI UI Primitives & Input Sanitization**:
   - Menghapus 12x duplikasi hack `: | fzf --print-query` dan inkonsistensi `--height` sembarang (35%, 40%, 70%, 80%).
   - Menyediakan fungsi kanonikal terpadu: `tui_prompt_input`, `tui_action_palette`, dan `tui_modal_notice` dengan perlindungan format string (`printf "%s"`).
5. **SSoT DRM & Runtime Architecture Resolution**:
   - Menyatukan duplikasi evaluasi artefak emulator Goldberg/DRM di `20_discovery.sh` dan `70_dashboard.sh` ke dalam satu fungsi kanonikal `resolve_game_drm_status` dengan pembedaan jelas antara status heuristik (preview) vs verifikasi biner (launcher).
6. **Trap Scope Isolation & Dual-Mode Runtime Path SSoT**:
   - Single ownership pembersihan terminal oleh `exit_tui_screen`. Menghilangkan penghapusan destruktif `trap - INT TERM EXIT` di child launcher.
   - Memisahkan secara tegas:
     - `get_desktop_runtime_dir()`: System XDG runtime untuk bind mount socket desktop (Wayland/Audio/D-Bus).
     - `get_runtime_dir()`: Private application runtime untuk PID, info aktif, dan logs gamectl.
7. **Deterministic Machine Verification**:
   - Validasi seluruh test suite (148+ contracts) dengan Exit Code 0, lint bersih, dan bundle sinkron.

---

## 2. Granular Technical Execution Plan (Todolist)

### [x] Chunk 1: Headless Engine Stream Discipline & Isolated Execution Harness
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `src/core/10_utils.sh`, buat fungsi kanonikal `tui_run_engine()`:
     ```bash
     tui_run_engine() {
         local action_name="$1"; shift
         local cmd=("$@")
         local run_log; run_log="$(get_runtime_log_file)"
         local err_log; err_log="$(get_runtime_dir)/err_${$}_${RANDOM}.log"
         : > "$err_log"

         local rc=0
         # Eksekusi dalam subshell terisolasi dengan stdin putus (< /dev/null)
         ( "${cmd[@]}" ) < /dev/null >> "$run_log" 2> "$err_log" || rc=$?

         if [ "$rc" -ne 0 ]; then
             local err_summary
             err_summary=$(tail -n 12 "$err_log" 2>/dev/null || echo "Unknown engine failure.")
             log_msg "ERROR" "ENGINE" "$action_name failed (exit code $rc)"
             tui_modal_notice "Engine Failure ($action_name)" "Operation returned Exit Code $rc.\n\nError Traces:\n$err_summary\n\nFull log:\n$run_log"
         fi
         rm -f "$err_log" 2>/dev/null || true
         return "$rc"
     }
     ```
  2. Di `src/runners/50_launcher.sh`:
     - Pastikan seluruh pre-flight log menggunakan logging yang dialihkan saat `[ "${GAMECTL_IN_ALT_SCREEN:-0}" -eq 1 ]`.
     - Kembalikan exit code 0 saat proses berhasil di-spawn di background, dan exit code 1 saat gagal.
- **Definition of Done (DoD)**:
  - 0 baris teks pre-flight bocor ke terminal scrollback saat dipanggil dari TUI.
  - Subshell terisolasi mencegah kontaminasi state atau variabel shell utama.

### [x] Chunk 2: Launcher Decoupling & In-Dashboard Process Management
- **Target Files**: `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `src/runners/50_launcher.sh`:
     - Lepaskan pemanggilan `game_controller_hud` dari fungsi `launch_game`.
     - Jadikan `launch_game` murni headless process launcher.
  2. Di `src/main.sh`:
     - Jalankan `game_controller_hud` HANYA jika dipanggil langsung via CLI terminal shell manual (`gamectl launch <dir>`).
  3. Di `src/tui/70_dashboard.sh`:
     - Di `library_menu()`:
       - Panggil launcher via `tui_run_engine "Launch $sel_title" launch_game "$sel_dir" "$sel_bin" "$sel_title"`.
       - Hilangkan modal notice sukses yang mengganggu; update status game di library menjadi `[RUNNING]` secara seamless.
       - Bila kursor berada pada game `[RUNNING]` dan pengguna menekan `Enter`, buka palet aksi proses terpadu (`View Live Logs`, `Stop Game (SIGTERM)`, `Force Kill (SIGKILL)`, `Return`).
     - Di `dashboard_menu()`:
       - Tambahkan metrik game aktif pada cockpit status overview.
       - Tambahkan hotkey `<Ctrl-P>` untuk langsung membuka daftar proses aktif tanpa keluar dari Dashboard.
- **Definition of Done (DoD)**:
  - Game diluncurkan mulus tanpa HUD memotong layar atau meminta konfirmasi ganda.
  - Manajemen proses game aktif terintegrasi penuh di dalam Library dan Dashboard Hub.

### [x] Chunk 3: Canonical TUI UI Primitives & Input Sanitization
- **Target Files**: `src/core/10_utils.sh`, `src/steam/25_identity.sh`, `src/steam/30_downloader.sh`, `src/runners/40_wrappers.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `src/core/10_utils.sh`, standarisasikan fungsi dialog kanonikal:
     - `tui_prompt_input <title> <header_text> [default_val]` (membungkus input prompt dengan border rounded dan cursor handling).
     - `tui_action_palette <title> <header_text> <options_tsv>` (viewport fullscreen terstandarisasi).
     - `tui_modal_notice <title> <message>` (menggunakan `printf "%s"` aman untuk mencegah interpretasi escape character liar).
  2. Refactor 12 pemanggilan ad-hoc `: | fzf` di `25_identity.sh`, `30_downloader.sh`, dan `40_wrappers.sh` ke primitif kanonikal.
  3. Hilangkan seluruh variasi parameter sembarang `--height=35%`, `--height=40%`, `--height=70%`, `--height=80%`.
- **Definition of Done (DoD)**:
  - 0 duplikasi hack `: | fzf --print-query` di seluruh modul sekunder.
  - Tampilan visual dialog konsisten 100% di seluruh aplikasi.
  - [ VERIFIED ] Lulus pengujian unit contract dan TUI Safety harness 151/151 Exit 0.

### [x] Chunk 4: SSoT DRM & Runtime Architecture Resolution
- **Target Files**: `src/core/10_utils.sh`, `src/steam/20_discovery.sh`, `src/tui/70_dashboard.sh`
- **Runtutan Eksekusi Teknis**:
  1. Implementasikan fungsi kanonikal di `src/core/10_utils.sh`:
     `resolve_game_drm_status <game_dir> [api_file] [bin_file]` yang mengembalikan status terstruktur (`GBE_FORK`, `VALVE_DLL`, `VALVE_SO`, `STANDALONE`).
  2. Konsolidasikan duplikasi evaluasi di:
     - `src/steam/20_discovery.sh` (Loop scan Steam Library)
     - `src/steam/20_discovery.sh` (Loop scan Custom Search Dirs)
     - `src/tui/70_dashboard.sh` (`preview_game`)
     - `src/steam/25_identity.sh` (`set_id` & `set_id_interactive`)
- **Definition of Done (DoD)**:
  - 100+ baris duplikasi kode heuristik DRM tereliminasi.
  - Perubahan deteksi emulator di masa depan hanya memerlukan modifikasi 1 baris di SSoT.
  - [ VERIFIED ] Lulus pengujian unit contract dan TUI Safety harness Exit 0.

### [ ] Chunk 5: Trap Scope Isolation & Terminal State Restoration Guard
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `src/runners/50_launcher.sh`:
     - Hapus `trap - INT TERM EXIT` di baris 697.
     - Pastikan cleanup lokal runner tidak menghapus trap pemulihan terminal milik TUI.
  2. Di `src/core/10_utils.sh`:
     - Jadikan `enter_tui_screen` dan `exit_tui_screen` sebagai single authoritative owner dari state terminal (termios, alternate screen `\033[?1049h`, kursor).
     - Lindungi `exit_tui_screen` dengan re-entrant guard agar idempotent saat dipanggil berulang kali.
- **Definition of Done (DoD)**:
  - Terminal tidak pernah rusak atau tertinggal dalam mode alternate screen saat keluar, error, atau menerima `SIGINT`/`SIGTERM`.

### [ ] Chunk 6: Dual-Mode Runtime Path SSoT Consolidation
- **Target Files**: `src/runners/40_wrappers.sh`, `src/steam/30_downloader.sh`, `src/core/10_utils.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `src/core/10_utils.sh`:
     - Tetapkan `get_desktop_runtime_dir()` untuk kebutuhan socket desktop Wayland/PulseAudio (`${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}`).
     - Tetapkan `get_runtime_dir()` untuk runtime privat gamectl (PID info, lock files, temporary logs).
  2. Di `src/runners/40_wrappers.sh`:
     - Gunakan `get_desktop_runtime_dir` saat melakukan mount bind socket desktop sistem ke bubblewrap sandbox.
  3. Di `src/steam/30_downloader.sh`:
     - Gunakan `get_runtime_dir` untuk staging directory manifest dan token sementara.
- **Definition of Done (DoD)**:
  - 0 hardcoded path manual `/run/user/` di luar fungsi resolver kanonikal.
  - Socket Wayland dan audio tetap utuh dan berfungsi normal di dalam sandbox wrapper.

### [ ] Chunk 7: Regression Harness, Contract Tests & Bundle Compilation
- **Target Files**: `tests/test_cli.sh`, `scripts/build.sh`, `bin/gamectl`
- **Runtutan Eksekusi Teknis**:
  1. Tambahkan test contracts di `tests/test_cli.sh`:
     - Contract: Stream isolation pada `tui_run_engine` (memastikan zero output ke stdout/stderr).
     - Contract: Headless launch returning correct PID/status tanpa interupsi UI.
     - Contract: SSoT DRM resolution contract untuk variasi artefak biner.
     - Contract: Dual-mode runtime path resolution (`get_desktop_runtime_dir` vs `get_runtime_dir`).
  2. Rebuild standalone executable bundle `bin/gamectl` via `./scripts/build.sh`.
  3. Jalankan `make lint` dan `make test`.
- **Definition of Done (DoD)**:
  - `make lint` lolos dengan Exit Code 0.
  - Seluruh test contracts lolos dengan Exit Code 0 (0 failed).
  - Executable `bin/gamectl` sinkron 100% dengan seluruh modular source.
