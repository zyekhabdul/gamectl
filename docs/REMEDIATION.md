# REMEDIATION WORK PACKET: SYSTEMIC STANDARDIZATION & ARCHITECTURAL DECOUPLING

**Track**: Architecture Decoupling / Universal TUI Harness / SSoT Consolidation  
**Status**: [ COMPLETED & VERIFIED ] (All 7 Chunks + Critical Stability Audit Fixes Verified)  
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

### [x] Chunk 5: Trap Scope Isolation & Terminal State Restoration Guard
- **Target Files**: `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `src/runners/50_launcher.sh`:
     - Cabut penghapusan destruktif bare `trap - INT TERM EXIT` dengan `_disarm_launch_traps` yang ter-scope.
     - Pastikan cleanup lokal runner tidak menghapus atau menimpa trap pemulihan terminal milik TUI owner PID.
  2. Di `src/core/10_utils.sh` & `src/main.sh`:
     - Jadikan `enter_tui_screen`, `exit_tui_screen`, dan `install_tui_screen_traps` sebagai single authoritative owner dari state terminal (saved `stty`, alternate screen `\033[?1049h`, kursor, owner PID).
     - Lindungi `exit_tui_screen` dengan re-entrant & single-owner guard (`GAMECTL_TUI_EXITING`, `GAMECTL_TUI_OWNER_PID`) serta preservasi exit code asli pada trap `EXIT`.
- **Definition of Done (DoD)**:
  - Terminal tidak pernah rusak atau tertinggal dalam mode alternate screen saat keluar, error, atau menerima `SIGINT`/`SIGTERM`.
  - [ VERIFIED ] Lulus seluruh harness (`test_remediation.sh` 6/6, `test_cli.sh` 147/147, `test_tui_safety.py` + `test_standalone_safety.py` 32/32) dengan Exit 0.

### [x] Chunk 6: Dual-Mode Runtime Path SSoT Consolidation
- **Target Files**: `src/runners/40_wrappers.sh`, `src/steam/30_downloader.sh`, `src/core/10_utils.sh`, `src/main.sh`
- **Runtutan Eksekusi Teknis**:
  1. Di `src/core/10_utils.sh` & `src/main.sh`:
     - Tetapkan & ekspor `get_desktop_runtime_dir()` untuk kebutuhan socket desktop Wayland/PipeWire/Pulse (`${XDG_RUNTIME_DIR:-/run/user/$run_uid}`).
     - Tetapkan `get_runtime_dir()` untuk runtime privat gamectl (PID info, lock files, temporary logs).
  2. Di `src/runners/40_wrappers.sh`:
     - Gunakan `get_desktop_runtime_dir` dan `get_runtime_dir` saat melakukan mount bind socket desktop sistem ke bubblewrap sandbox (`--bind-try` rw untuk Wayland/audio socket, `--tmpfs "$desktop_runtime_dir"`).
  3. Pertahankan fallback terisolasi `src/steam/30_downloader.sh` agar tetap kompatibel saat modul disource mandiri.
- **Definition of Done (DoD)**:
  - 0 hardcoded path manual `/run/user/` di luar fungsi resolver kanonikal `get_desktop_runtime_dir`.
  - [ VERIFIED ] Lulus contract `test_dual_mode_runtime_paths_contract`.

### [x] Chunk 7: Regression Harness, Critical Stability Audit Fixes & Bundle Compilation
- **Target Files**: `tests/test_remediation.sh`, `Makefile`, `scripts/build.sh`, `bin/gamectl`, `src/core/10_utils.sh`, `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`, `src/steam/30_downloader.sh`, `src/steam/35_fixes.sh`, `src/runners/40_wrappers.sh`
- **Runtutan Eksekusi Teknis**:
  1. Perbaikan 4 temuan kritis stabilitas:
     - Preserve caller `errexit` di `tui_exec_action()` (tidak memaksa `set -e` aktif permanen pada shell TUI induk).
     - Hapus layer violation `check_fzf_status "$launch_rc"` di `library_menu()`.
     - Tutup inherited FD pada background watchdog `launch_game` (`</dev/null >/dev/null 2>&1 &`).
     - Eliminasi seluruh 17 flag `--height=...%` acak di seluruh tampilan FZF.
  2. Tambahkan test contracts di `tests/test_remediation.sh` dan integrasikan `test_remediation.sh` + `test_tui_ergonomics.sh` ke `Makefile` target `test:`.
  3. Rebuild standalone executable bundle `bin/gamectl` via `./scripts/build.sh`.
  4. Jalankan `make lint`, `make test`, dan seluruh Python safety suite (`test_tui_safety.py`, `test_standalone_safety.py`, `test_save_safety.py`).
- **Definition of Done (DoD)**:
  - `make lint` lolos dengan Exit Code 0.
  - Seluruh test contracts (`test_cli.sh`, `test_remediation.sh`, `test_tui_ergonomics.sh`, Python safety suites) lolos dengan Exit Code 0 (0 failed).
  - Executable `bin/gamectl` sinkron 100% dengan seluruh modular source.

---

# REMEDIATION WORK PACKET 2: STEAM CATALOG APP-TYPE SSoT & DLC GUARD

- **Track**: Remediation / Steam Catalog App-Type SSoT & Engine-Level DLC Guard
- **Status**: [ COMPLETED & VERIFIED ] [4/4 PACKETS]
- **Prasyarat**: Remediation Chunks 1–7 (COMPLETED) & WP40 Epic Adapter (COMPLETED, `76a0630`)
- **Basis**: `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`, `docs/REMEDIATION.md` (SoC), dan temuan empiris API Valve (`storesearch` vs `IStoreBrowseService/GetItems/v1` & `appdetails`)
- **Target Files**: `src/steam/31_manifests.sh`, `src/steam/30_downloader.sh`, `src/steam/32_steam_bridge.sh`, `src/tui/70_dashboard.sh`, `src/tui/71_previews.sh`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Tujuan & Invarian

1. **Single Source of Truth Klasifikasi Tipe (Anti-Monkeypatch)**:
   - Gunakan satu kosakata token kanonik (`GAME`, `DLC`, `DEMO`, `MOD`, `SOUNDTRACK`, `TOOL`, `APP`) dan satu resolver domain (`classify_steam_app_types` via batch `IStoreBrowseService/GetItems/v1` + `fetch_steam_app_details` / `resolve_steam_app_type` via `appdetails?filters=basic,platforms,genres`). Dilarang memakai heuristik judul string (`*DLC*`, `*Soundtrack*`).
2. **Right-Sized Standardization (YAGNI)**:
   - Standarisasi kosakata dan domain Steam sekarang; tunda perluasan kolom `ITEM_TYPE`/`PARENT_ID` pada kontrak lintas-store (`20_store_gog.sh`, `30_store_epic.sh`) sampai WP41 (`search_stores`) karena GOG (`mediaType=game`) dan Epic (`legendary list --json`) tidak mencampur DLC di output search.
3. **Backward Compatibility Cache & Test Contracts**:
   - Pertahankan cache key `steam_details_${appid}` (tidak memecah cache baru maupun merusak fixture offline `tests/test_cli.sh` / `tests/test_tui_ergonomics.sh`), dan pertahankan `--max-time 15` pada panggilan `storesearch` di `src/tui/70_dashboard.sh` dan `src/steam/32_steam_bridge.sh` (`tests/test_remediation.sh:1223-1224`).
4. **Engine-Level Guard + Offline Resilience**:
   - Proteksi DLC berlaku di engine headless `download_game()` (`--allow-dlc` opt-in) maupun TUI (`search_steam()` menawarkan redirect ke `parent_appid`); bila offline/tanpa metadata cache, tetap fallback aman (`APP`/lanjut normal tanpa blokir palsu).
5. **TUI Structured Fields & Sanitasi**:
   - `search_steam()` membawa `RAW_TYPE` dan `PARENT_APPID` di kolom TSV tersembunyi (`--with-nth=1,2,3,4`), seluruh field lolos `validate_tui_fields`, dan toggle filter `Tab` (`ALL -> GAME -> DLC -> ALL`) tidak bentrok dengan hotkey eksisting (`ctrl-a/u/s/d/f`).

---

## 2. Rencana Eksekusi Detail (Packet R2A - R2D)

### [x] Packet R2A: Steam App-Type SSoT & Metadata Helpers (`src/steam/31_manifests.sh`)
- **Target Files**: `src/steam/31_manifests.sh`
- **Langkah Teknis**:
  1. Tambah `format_app_type_badge <raw_type>` untuk merender token `[GAME]`, `[DLC]`, `[DEMO]`, `[MOD]`, `[OST]`, `[TOOL]`, `[APP]` secara konsisten.
  2. Tambah `classify_steam_app_types <appid1> [appid2 ...]` yang memanggil `IStoreBrowseService/GetItems/v1` dalam 1 batch HTTP (`--connect-timeout 5 --max-time 10`), memetakan enum Valve (`0->GAME`, `4->DLC`, `1->DEMO`, `2->MOD`, `6->APP`, `11->SOUNDTRACK`), memvalidasi output lewat `validate_tui_fields`, dan mengembalikan `<APPID>\t<TYPE>\t<PARENT_APPID>` dengan fallback aman `APP` saat offline/gagal.
  3. Tambah `fetch_steam_app_details <appid>` (`appdetails?appids=${appid}&filters=basic,platforms,genres` memakai cache key `steam_details_${appid}`) dan `resolve_steam_app_type <appid>` yang mengembalikan `<TYPE>\t<PARENT_APPID>\t<PARENT_NAME>` tanpa memaksa panggilan jaringan bila fixture cache lokal tidak memiliki field `type`.
- **Definition of Done (DoD)**:
  - Seluruh caller membaca kosakata tipe kanonik dan tuple terstruktur dari satu SSoT tanpa parser `appdetails`/`IStoreBrowseService` duplikat.

### [x] Packet R2B: TUI Catalog Badges, Filter Toggle & Preview Metadata
- **Target Files**: `src/tui/70_dashboard.sh`, `src/tui/71_previews.sh`, `src/steam/32_steam_bridge.sh`
- **Langkah Teknis**:
  1. Perbarui `search_steam()` (`70_dashboard.sh`) untuk memperkaya hasil `storesearch` via `classify_steam_app_types`, menyusun baris `APPID\tBADGE\tTITLE\tSTATUS\tRAW_TYPE\tPARENT_APPID` dengan `--with-nth=1,2,3,4`, serta menambah toggle filter `Tab` (`ALL -> GAME -> DLC -> ALL`) tanpa mengganggu `ctrl-a/u/s/d/f`.
  2. Saat user memilih item `DLC` yang memiliki `PARENT_APPID` untuk diunduh di `search_steam()`, tampilkan prompt pilihan untuk mengunduh Base Game (`PARENT_APPID`) yang sudah mencakup depot DLC.
  3. Perbarui `preview_search_game()` (`71_previews.sh`) memakai `fetch_steam_app_details` agar menampilkan baris `Type : [GAME]` atau `Type : [DLC] (Base: <name> • <parent_appid>)`.
  4. Perbarui `unlock_interactive()` (`32_steam_bridge.sh`) menampilkan badge tipe dari `classify_steam_app_types` pada picker adopsi.
- **Definition of Done (DoD)**:
  - Pengguna langsung membedakan `[GAME]` vs `[DLC]` pada list kiri dan preview kanan, serta terhindar dari unduhan DLC tunggal tanpa sengaja.

### [x] Packet R2C: Engine-Level DLC Guard (`src/steam/30_downloader.sh`)
- **Target Files**: `src/steam/30_downloader.sh`
- **Langkah Teknis**:
  1. Tambah flag opt-in `--allow-dlc` pada `download_game()`.
  2. Sebelum memulai manifest/download, periksa `resolve_steam_app_type "$appid"`: jika terverifikasi `DLC` dengan `PARENT_APPID` dan `--allow-dlc` tidak diberikan, gagalkan dengan pesan terstruktur ke `stderr` yang menyarankan `gamectl download <parent_appid>`.
  3. Bila offline atau metadata tidak tersedia (`UNKNOWN`/`APP`), lanjutkan eksekusi normal tanpa memblokir pengguna.
- **Definition of Done (DoD)**:
  - Baik jalur CLI (`gamectl download <dlc_appid>`) maupun TUI dilindungi satu guard domain yang konsisten dan aman offline.

### [x] Packet R2D: Offline Contract Tests, Rebuild & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `bin/gamectl`, `docs/REMEDIATION.md`
- **Langkah Teknis**:
  1. Tambah contract test di `tests/test_remediation.sh` dengan mock `IStoreBrowseService` dan `appdetails` offline untuk memverifikasi klasifikasi `[GAME]` vs `[DLC]`, `Tab` filter `ALL/GAME/DLC`, preview `Type` & `Base Game`, serta guard `download_game()` (`DLC` ditolak default, lolos dengan `--allow-dlc`, aman saat offline).
  2. Kompilasi ulang `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`), jalankan `STRICT_LINT=1 make lint` dan `make test`, serta tandai seluruh packet R2A–R2D selesai di `docs/REMEDIATION.md`.
- **Definition of Done (DoD)**:
  - Seluruh lint, bundle check, suite Bash (`test_cli.sh`, `test_remediation.sh`, dkk.), dan Python safety tests lulus Exit Code `0` tanpa melemahkan assertion eksisting.

---

# REMEDIATION WORK PACKET 2.1: STRUCTURAL SSoT HARDENING & TEST INVARIANT CLOSURE

- **Track**: Remediation / Structural SSoT Deduplication & Test Contract Closure
- **Status**: [ COMPLETED & VERIFIED ] [4/4 PACKETS]
- **Prasyarat**: Work Packet 2 R2A–R2D (`COMPLETED & VERIFIED`, `dbd262c..457001c`)
- **Basis**: Audit forensik DoD Packet R2, `docs/SOVEREIGN_ORIGINAL_PURPOSE.md`, dan prinsip anti-monkeypatch (SSoT + YAGNI)
- **Target Files**: `src/steam/31_manifests.sh`, `src/steam/30_downloader.sh`, `src/tui/70_dashboard.sh`, `src/tui/71_previews.sh`, `completions/gamectl.bash`, `tests/test_remediation.sh`, `docs/REMEDIATION.md`, `bin/gamectl`

---

## 1. Tujuan & Batas YAGNI

1. **Eliminasi Monkeypatch Duplikasi Preflight Provider**:
   - Satukan pengecekan cache/stash manifest + validasi kredensial provider gated (`luatools`, `hubcap`) ke satu fungsi domain `preflight_manifest_source <appid> <source>` di `src/steam/31_manifests.sh`, menggantikan logika duplikat di `download_game()` (`src/steam/30_downloader.sh`) dan `fetch_manifest()`.
2. **Eliminasi Duplikasi Parser JSON Steam di Layer TUI**:
   - Ekstrak satu parser SSoT `parse_steam_app_type_json <details_json>` di `src/steam/31_manifests.sh` untuk dipakai oleh `resolve_steam_app_type()` dan `preview_search_game()` (`src/tui/71_previews.sh`), serta arahkan `_prepare_download_target()` (`src/tui/70_dashboard.sh`) ke `resolve_steam_app_type` tanpa parser `jq` ad-hoc.
3. **Penutupan Celah Invarian Test 37**:
   - Ubah counter subshell mati `batch_calls` menjadi file counter + assert `== 1`, tambah sentinel zero-network untuk fixture cache lokal tanpa `.type` (`555555`), dan uji seluruh 3 cabang `_prepare_download_target` (`base`, `dlc` + `--allow-dlc`, `cancel`).
4. **Sinkronisasi Permukaan CLI & Spek**:
   - Tambahkan `--allow-dlc` dan `--os` ke `download_opts` di `completions/gamectl.bash` serta sinkronkan teks spek Packet 2 (`6->APP`, `Type : [GAME]`) dengan kosakata tertutup 7 token.
5. **Batas YAGNI Eksplisit**:
   - Pertahankan `steam_basic_${appid}` (`tests/test_cli.sh:2125`) dan `steam_basic_dlc_${appid}` secara terpisah; jangan menambah abstraksi wrapper di luar `preflight_manifest_source` dan `parse_steam_app_type_json`.

---

## 2. Rencana Eksekusi Detail (Packet R2.1A - R2.1D)

### [x] Packet R2.1A: SSoT Preflight Manifest Provider (`src/steam/31_manifests.sh`, `src/steam/30_downloader.sh`)
- **Target Files**: `src/steam/31_manifests.sh`, `src/steam/30_downloader.sh`
- **Langkah Teknis**:
  1. Tambahkan `preflight_manifest_source <appid> [source]` di `src/steam/31_manifests.sh` untuk memvalidasi kesiapan kredensial provider explicit (`luatools`, `hubcap`) saat arsip manifest lokal (`cache`/`stash`) belum ada, termasuk pesan error instruksional terstruktur.
  2. Ganti blok preflight duplikat di `download_game()` (`src/steam/30_downloader.sh`) dan `fetch_manifest()` (`src/steam/31_manifests.sh`) agar memanggil `preflight_manifest_source`.
- **Definition of Done (DoD)**:
  - Nol duplikasi path `manifests/${appid}.zip` atau pesan error auth `luatools`/`hubcap` di `30_downloader.sh`; `test_luatools_without_session_explains_download_failure` dan `test_hubcap.sh` tetap lulus 0 network call.

### [x] Packet R2.1B: SSoT App-Type JSON Parser & TUI Decoupling (`src/steam/31_manifests.sh`, `src/tui/71_previews.sh`, `src/tui/70_dashboard.sh`)
- **Target Files**: `src/steam/31_manifests.sh`, `src/tui/71_previews.sh`, `src/tui/70_dashboard.sh`
- **Langkah Teknis**:
  1. Tambahkan `parse_steam_app_type_json <details_json>` di `src/steam/31_manifests.sh` yang mengeluarkan TSV tervalidasi `<HAS_TYPE>\t<TYPE>\t<PARENT_APPID>\t<PARENT_NAME>` (1 pass `jq` + `normalize_steam_app_type` + `validate_tui_fields`).
  2. Panggil `parse_steam_app_type_json` dari `resolve_steam_app_type()` dan `preview_search_game()` (`src/tui/71_previews.sh`), sehingga `71_previews.sh` tidak mem-fork `jq` 3x untuk `.type`/`.fullgame` dan `parent_name` terjamin bersih dari `[\t\r\n]`.
  3. Di `_prepare_download_target()` (`src/tui/70_dashboard.sh`), resolusi `parent_id` & `parent_name` selalu melalui `resolve_steam_app_type "$sel_id"` (fallback ke `sel_parent` bila kosong), tanpa query `jq` ad-hoc di layer TUI.
- **Definition of Done (DoD)**:
  - Nol parser skema `.type` / `.fullgame` di `src/tui/`; semua field yang masuk ke `tui_action_palette` dan preview tervalidasi lewat satu SSoT.

### [x] Packet R2.1C: Shell Completion & Spec Parity (`completions/gamectl.bash`, `docs/REMEDIATION.md`)
- **Target Files**: `completions/gamectl.bash`, `docs/REMEDIATION.md`
- **Langkah Teknis**:
  1. Tambahkan `--allow-dlc` dan `--os` ke `download_opts` di `completions/gamectl.bash`.
  2. Sinkronkan 2 catatan spek Packet 2 di `docs/REMEDIATION.md` (`6->APP`, `Type : [GAME]`) dengan implementasi kosakata kanonik 7 token.
- **Definition of Done (DoD)**:
  - Tab-completion `gamectl download` sinkron dengan flag `download_game()`; dokumentasi bebas drift.

### [x] Packet R2.1D: Test Invariant Closure, Rebuild & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `bin/gamectl`, `docs/REMEDIATION.md`
- **Langkah Teknis**:
  1. Perbarui Test 37 di `tests/test_remediation.sh`:
     - Ganti `batch_calls` dengan file counter dan assert `[ "$(wc -l < "$t_dir/batch.calls")" -eq 1 ]`.
     - Tambah sentinel zero-network (`[ ! -e "$t_dir/unexpected_net" ]`) saat menguji `resolve_steam_app_type 555555`.
     - Tambahkan skenario cabang `dlc` (`--allow-dlc` diteruskan ke `download_game`) dan `cancel` (`download_game` tidak dipanggil) pada `_prepare_download_target`.
  2. Tambahkan assertion completion `--allow-dlc` di Test 38 (`tests/test_remediation.sh`).
  3. Rebuild `bin/gamectl` (`./scripts/build.sh && ./scripts/build.sh --check`), jalankan `STRICT_LINT=1 make lint` dan `make test`, tandai Packet R2.1A–R2.1D `[x]` / `[ COMPLETED & VERIFIED ]` di `docs/REMEDIATION.md`, dan bersihkan `.deb`.
- **Definition of Done (DoD)**:
  - Seluruh suite Bash (`test_cli.sh`, `test_remediation.sh`, `test_tui_ergonomics.sh`, `test_depot_filter.sh`, `test_hubcap.sh`), Python (`42/42`), lint, dan bundle check lulus Exit Code `0`.
