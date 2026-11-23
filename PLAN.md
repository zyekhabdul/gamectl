# WORK PACKET 30: PRODUCTION GRAPHICS NEGOTIATION, PROTON CONTRACT & RUNTIME OBSERVABILITY

- **Track**: Production Hardening / Generalized Hardware Negotiation / TUI Observability
- **Status**: IN PROGRESS [1/4 PACKETS]
- **Basis**: Empiris dari `/run/user/1000/game_Downwellexe.log` (`HRESULT 0x887a0002` / `DXGI_ERROR_NOT_FOUND`, `protonfixes` `IndexError`, multilib PE32, dan audit visual TUI).
- **Target Files**: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/diagnostics/60_doctor.sh`, `src/tui/70_dashboard.sh`, `src/main.sh`, `tests/test_remediation.sh`, `bin/gamectl`

---

## 1. Rencana Eksekusi Detail (Packet A - D)

### [x] Packet A: Capability-Based Graphics Renderer SSoT (`DXVK` vs `WineD3D`)
- **Target Files**: `src/runners/40_wrappers.sh`, `src/runners/50_launcher.sh`, `src/main.sh`
- **Langkah Teknis**:
  1. Di `src/runners/40_wrappers.sh`, implementasikan fungsi kanonikal `detect_vulkan_capability()` dengan 2-tier probe tanpa hardcode vendor tunggal:
     - **Tier 1 (Runtime Probe)**: Jika `vulkaninfo --summary` tersedia, periksa apakah ada physical GPU non-CPU (`PHYSICAL_DEVICE_TYPE_DISCRETE_GPU` / `INTEGRATED_GPU`) dengan `apiVersion >= 1.1`.
     - **Tier 2 (Kernel/ICD Fallback — zero dependency)**: Periksa `/usr/share/vulkan/icd.d/*.json` dan `/etc/vulkan/icd.d/*.json` serta driver aktif (`/sys/class/drm/card*/device`, `lspci`):
       - Kosong atau hanya software rasterizer (`lvp_icd`) -> `OPENGL_ONLY`.
       - Hanya driver legacy/incomplete (`intel_hasvk` untuk Gen 7/7.5 tanpa dGPU, kernel module `radeon`, atau `nouveau`) -> `VULKAN_LEGACY`.
       - Hardware Vulkan ICD modern (`intel_icd` Gen 8+, `radeon_icd` / `amdgpu`, `nvidia_icd`) -> `VULKAN_READY`.
     - Kembalikan token terstruktur: `VULKAN_READY` | `VULKAN_LEGACY` | `OPENGL_ONLY`.
  2. Buat helper `resolve_graphics_renderer <mode> <prime_active>` (`auto` | `dxvk` | `wined3d`) yang mengembalikan `dxvk` atau `wined3d`:
     - `dxvk` -> paksa `PROTON_USE_WINED3D=0`.
     - `wined3d` -> paksa `PROTON_USE_WINED3D=1`.
     - `auto` -> `dxvk` jika `VULKAN_READY` atau `prime_active=1`; `wined3d` jika `VULKAN_LEGACY` / `OPENGL_ONLY`.
  3. Tambahkan konfigurasi `renderer=auto|dxvk|wined3d` ke hierarki `build_wrapper_command()` (`~/.config/gamectl/wrappers` -> `$gdir/.wrappers` -> env `GAMECTL_RENDERER` / `PROTON_USE_WINED3D` -> CLI `--wined3d` / `--dxvk`) dan ekspor `GAMECTL_ACTIVE_RENDERER`.
  4. Tambahkan opsi toggle **Graphics Renderer (`Auto` / `DXVK` / `WineD3D`)** di menu interaktif `configure_wrappers()` (`<CTRL-O>`).
  5. Di `src/runners/50_launcher.sh`, terapkan `PROTON_USE_WINED3D=1` secara otomatis saat `GAMECTL_ACTIVE_RENDERER=wined3d` (menghormati override eksplisit user di env).
  6. Ekspor `detect_vulkan_capability` dan `resolve_graphics_renderer` di `src/main.sh`.
- **Definition of Done (DoD)**:
  - Mesin tanpa Vulkan penuh (Haswell, VM, no-ICD, legacy driver) otomatis memakai WineD3D/OpenGL tanpa `HRESULT 0x887a0002`.
  - Mesin modern (AMD/NVIDIA/Intel Gen 8+) tetap memakai DXVK secara default.
  - User dapat menimpa renderer lewat CLI (`--wined3d`/`--dxvk`), env, atau menu `<CTRL-O>`.
  - [ VERIFIED ] `make lint` & `make test` (`test_cli.sh` 147/147, `test_remediation.sh` 11/11, `test_tui_ergonomics.sh` 3/3) lulus Exit 0.

### [ ] Packet B: Normalisasi Kontrak Environment Proton & `umu-run`
- **Target Files**: `src/runners/50_launcher.sh`
- **Langkah Teknis**:
  1. Di blok launch `*proton*` dan `umu-run` (`src/runners/50_launcher.sh` baris 624-650):
     - Ekspor kontrak environment standar secara konsisten:
       - `STEAM_COMPAT_APP_ID="$appid"`
       - `SteamAppId="$appid"`
       - `SteamGameId="$appid"`
       - `GAMEID="umu-${appid}"` (atau `umu-default` saat `$appid = "0"`)
     - Cegah crash Python `IndexError` di `protonfixes/fix.py` (`re.findall(r'\d+', STEAM_COMPAT_DATA_PATH)[-1]`) pada direktori standalone tanpa digit AppID:
       - Jika `STEAM_COMPAT_DATA_PATH` tidak mengandung angka dan `$appid = "0"` (atau `PROTONFIXES_DISABLE` belum diset pada jalur direktori non-numerik tanpa kompatibilitas), set `PROTONFIXES_DISABLE="${PROTONFIXES_DISABLE:-1}"` agar tidak memuntahkan traceback ke log runtime.
- **Definition of Done (DoD)**:
  - Peluncuran game standalone lewat GE-Proton bebas dari Python traceback `protonfixes` `IndexError` pada log runtime.
  - Identitas `SteamAppId` dan `SteamGameId` selalu tersedia di dalam prefix Windows.

### [ ] Packet C: Graphics/Multilib Audit (`doctor`), Crash Telemetry Hint & TUI Polish
- **Target Files**: `src/diagnostics/60_doctor.sh`, `src/runners/50_launcher.sh`, `src/tui/70_dashboard.sh`
- **Langkah Teknis**:
  1. **Upgrade `doctor_audit()` (`src/diagnostics/60_doctor.sh` baris 205-228)**:
     - Ganti pengecekan sempit `is_haswell_gpu` dengan output terstruktur dari `detect_vulkan_capability()`: tampilkan tier Vulkan (`VULKAN_READY` / `VULKAN_LEGACY` / `OPENGL_ONLY`) dan renderer default aktif (`DXVK` / `WineD3D`).
     - Tambahkan pemeriksaan **32-bit Multilib Readiness** (`/usr/lib32/libGL.so.1` atau `/usr/lib/i386-linux-gnu/libGL.so.1`) untuk memastikan game Windows PE32 tidak gagal diam-diam.
  2. **Crash Telemetry Hint (`src/tui/70_dashboard.sh` & `src/runners/50_launcher.sh`)**:
     - Inspeksi ringan tail log game terakhir (`$log_file`) pada `preview_game()` dan `game_controller_hud()` untuk pola error umum (`DXGI_ERROR`, `0x887a0002`, `Vulkan support is incomplete`, `err:module:import_dll`).
     - Bila terdeteksi, tampilkan 1 baris `[HINT]` singkat dan actionable (misal: `Graphics API error -> coba Renderer: WineD3D (<CTRL-O>)`).
  3. **Polish Visual TUI (`src/tui/70_dashboard.sh`)**:
     - Baris 234: ubah `Ctrl-X (Fixes)` menjadi `Community Fixes` (hilangkan redundansi pill `CTRL-X`).
     - Baris 58: ringkas deskripsi status running (`(Active in background)`) dan singkat tampilan path `Runner` agar tidak patah baris di terminal 80-120 kolom.
     - Tambahkan baris `Renderer : Auto (WineD3D|DXVK)` di panel `RUNTIME WRAPPERS & PERFORMANCE` pada `preview_game()`.
- **Definition of Done (DoD)**:
  - `gamectl doctor` menampilkan tier Vulkan, renderer default, dan status library 32-bit secara lintas-distro.
  - Panel preview & HUD menampilkan hint perbaikan otomatis saat log mengandung kegagalan DXGI/Vulkan/DLL.
  - Panel preview TUI bebas dari redundansi teks shortcut dan wrapping rusak.

### [ ] Packet D: Regression Contracts, Bundle Sync & Full Verification
- **Target Files**: `tests/test_remediation.sh`, `bin/gamectl`
- **Langkah Teknis**:
  1. Tambahkan contract tests deterministik di `tests/test_remediation.sh`:
     - `test_graphics_capability_and_renderer_contract`: uji `resolve_graphics_renderer` untuk semua kombinasi (`auto`/`dxvk`/`wined3d` x `VULKAN_READY`/`VULKAN_LEGACY`/`OPENGL_ONLY` x `prime=0/1`) serta CLI flag `--wined3d` / `--dxvk`.
     - `test_proton_env_contract`: uji ekspor `SteamAppId`, `SteamGameId`, `GAMEID`, dan `PROTONFIXES_DISABLE` pada jalur Proton standalone.
     - `test_doctor_multilib_and_tui_polish_contract`: uji output `doctor_audit` melaporkan Vulkan tier & multilib 32-bit, serta `preview_game` menampilkan `Community Fixes` dan info `Renderer`.
  2. Kompilasi bundle via `./scripts/build.sh`.
  3. Eksekusi gerbang verifikasi mesin: `make lint && make test` serta `python3 -m unittest tests/test_tui_safety.py tests/test_standalone_safety.py tests/test_save_safety.py`.
- **Definition of Done (DoD)**:
  - `make lint` Exit Code 0.
  - `make test` (`test_cli.sh`, `test_remediation.sh`, `test_tui_ergonomics.sh`) dan seluruh Python safety suites lulus Exit Code 0 (0 failures).
  - `bin/gamectl` sinkron 100% dengan source (`./scripts/build.sh --check` Exit 0).
