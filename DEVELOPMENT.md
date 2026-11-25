# GAMECTL — DEVELOPER GUIDE & COMPILATION ARCHITECTURE

Tujuan yang mengikat: [pengganti Steam yang ringan, standalone, dan stabil jangka panjang](docs/SOVEREIGN_ORIGINAL_PURPOSE.md).
Alur inti tidak boleh bergantung pada Steam Client, SLSsteam, atau hook pola memori client. Integrasi lama bukan syarat untuk memperbaiki atau menilai kesiapan alur mandiri.

## 1. Source-to-Bundle Architecture

`gamectl` adheres strictly to a deterministic **Source-to-Bundle** design pattern:
- Source code is developed modularly inside `src/` (each module scoped to 150-600 lines for maintainability).
- The native bundling script [`scripts/build.sh`](file:///home/aomiqaza/Projects/gamectl/scripts/build.sh) concatenates and validates all modules into a single standalone executable at [`bin/gamectl`](file:///home/aomiqaza/Projects/gamectl/bin/gamectl).
- Strategic Advantages:
  - **Zero Dependency at Runtime**: The compiled executable does not depend on external library files or project directory paths on target systems.
  - **Maximum Portability**: The standalone binary can be symlinked or installed to `~/.local/bin` or `/usr/bin` without losing module context.
  - **Instant Subshell Performance**: Fast subshells (`fzf --preview`) execute instantly with zero multi-file parsing overhead.

---

## 2. Modular Architecture (`src/`)

```text
src/
├── core/
│   ├── 00_header.sh            # SSoT Constants, Tokyo Night ANSI styling palette, FZF base configuration
│   ├── 10_utils.sh             # GBE template resolver, atomic config/KV helpers, zip audit, ephemeral cache tier
│   ├── 12_tui_primitives.sh    # Zero-flicker FZF dialogs, tty input flush, tui_run_engine, screen lifecycle
│   ├── 14_saves.sh             # 3-slot savegame snapshot rotation, rollback recovery, Wine prefix save collector
│   └── 16_steamstub.sh         # SteamStub (.bind ELF & PE) forensic detector and unpacker
├── steam/
│   ├── 20_discovery.sh         # Multi-path Steam & standalone scanner, active process guard, desktop launcher
│   ├── 25_identity.sh          # SteamID64 generation, active SteamID resolution, persona configuration, set-id
│   ├── 30_downloader.sh        # Standalone native CDN downloader, depot OS filtering, local library routing
│   ├── 31_manifests.sh         # Multi-provider manifest harvester, DLC extractor, LuaTools auth session
│   ├── 32_steam_bridge.sh      # Explicit opt-in Steam Client & SLSsteam compatibility bridge
│   └── 35_fixes.sh             # Community & Online-Fix harvester, backup snapshot, atomic revert
├── stores/
│   ├── 00_store_interface.sh   # Unified store adapter registry, capability probe & store_dispatch()
│   ├── 10_store_steam.sh       # Built-in Steam/Standalone adapter wrapping CDN downloader & offline DLC sync
│   ├── 20_store_gog.sh         # Optional DRM-free GOG adapter (gogdl / lgogdownloader) & gamectl gog CLI
│   └── 30_store_epic.sh        # Optional Epic Games adapter (legendary) & gamectl epic CLI
├── runners/
│   ├── 40_wrappers.sh          # Wrapper config loader, developer profiler, wrapper builder, global settings
│   ├── 41_proton_prefix.sh     # Windows runner, wineserver resolver, DLL overrides, GE-Proton manager, manage_prefix
│   ├── 42_graphics_isolation.sh # Vulkan/GPU capability probe, Gamescope args, cgroups v2 scope, Bubblewrap sandbox
│   ├── 50_launcher.sh          # Process HUD, launch_game lifecycle, PipeWire audio, wineserver guard, cli_launch
│   ├── 51_remote_sync.sh       # SSH/Rsync & Rclone save synchronization and companion pull helpers
│   └── 52_inject_runtime.sh    # Offline GBE Fork injector and mod/OnlineFix DLL override setup
├── diagnostics/
│   └── 60_doctor.sh            # 8-layer system & GPU health diagnostics and cached query_protondb
├── tui/
│   ├── 70_dashboard.sh         # Interactive dashboard hub, library menu, Steam Store search, remote sync palette
│   └── 71_previews.sh          # Read-only FZF preview renderers (game, dashboard, store search, logs)
└── main.sh                     # Subshell exports (export -f) and top-level CLI command dispatcher
```

---

## 3. Compilation & Quality Verification Workflow

### Compile to Standalone Binary
```bash
./scripts/build.sh
```

### Verify Source vs Binary Synchronization (CI / Pre-commit Gate)
```bash
./scripts/build.sh --check
```

### Syntax Verification Across All Modules
```bash
make lint
```

This checks each source module, bundled executable, installer, build and packaging
script, regression test, and Bash completion separately, stopping on syntax errors.

### Run Comprehensive Regression & Integrity Test Suite
```bash
./tests/test_cli.sh
```

### Run System Health Diagnostics
```bash
bin/gamectl doctor
```

---

## 4. Legacy Steam Bridge Compatibility (Explicit Opt-In)

These legacy commands (`gamectl entitle` / `adopt-steam` / `unlock`) integrate with an external Steam Client only when explicitly requested. They are not the gamectl runtime, a standalone dependency, a recovery fallback, or evidence of standalone readiness:
1. **Local File Adoption**: Directs Steam to recognize already existing standalone/offline game directories, avoiding duplicate downloads.
2. **Community Steam Input**: Activates Steam Input mapping, enabling native gyro, trackpad, and custom community controller layouts on handhelds (Steam Deck, ROG Ally, Legion Go).
3. **Vulkan Shader Pre-Caching**: Instructs Steam to pull and pre-compile official Vulkan pipeline shaders from Valve CDN, preventing runtime stutter during gameplay.
4. **Full DLC Activation (Steam Client Bridge)**: When running optional Steam adoption, automatically resolves and registers DLC IDs via Steam Web API into `~/.config/SLSsteam/config.yaml` and creates atomic `appmanifest_<appid>.acf` manifests.

---

## 5. Global Ecosystem & Multi-Drive Hardening Architecture

1. **Unified Wineserver Resolution (`get_wineserver_bin`)**:
   Automatically detects embedded `wineserver` executables from active Proton releases (`files/bin/wineserver`, `dist/bin/wineserver`, `bin/wineserver`) and local GE-Proton installations. Operates with 100% independence from host package availability on immutable/Proton-only gaming distros (Bazzite, SteamOS, ChimeraOS).

2. **Dual-OS DepotDownloader Negotiation (`detect_app_platform_os`)**:
   Interrogates Steam Store metadata for target AppIDs. When `platforms.windows == true && platforms.linux == false`, automatically routes downloads with `-os windows`, resolving the "no depots found" error for Windows-exclusive titles.

3. **Dynamic Multi-Drive Library Routing (`resolve_target_library_dir`)**:
   Scans configured paths in `~/.config/gamectl/libraries`, `$GAMECTL_LIBRARY_DIRS`, and `$HOME/Games`. Dynamically measures available storage using `df -PB 1M` and routes installations to the drive partition with the largest free capacity.

4. **Active Steam Process Guardrail (`check_steam_active`)**:
   Verifies whether the `steam` client is active prior to mutating binary `shortcuts.vdf` or `appmanifest_*.acf` files, preventing memory lock conflicts and silent client overwrites.

5. **Normalized Secondary Drive Remote Sync (`sync_save_remote`)**:
   Normalizes game directory paths stored on secondary drives (`/mnt/*`, `/media/*`) into clean remote relative paths (`Games/<Title>/saves/`), preventing malformed path creation on remote companion hosts.

6. **Ephemeral High-Throughput JSON Cache Tier (`fetch_cached_json`)**:
   Implements disk-backed TTL-controlled (default 3600s) atomic JSON caching for Steam Store details and ProtonDB summaries at `${XDG_CACHE_HOME:-$HOME/.cache}/gamectl/`, eliminating network latency and fzf preview stutter.

---

## 6. Linux Kernel Process Isolation, Hybrid PRIME & Security Sandboxing

1. **cgroups v2 / systemd-run Scope Isolation (`check_systemd_scope_support`)**:
   Envelops game processes in transient user scopes (`systemd-run --user --scope --unit="gamectl-${safe_title}-${BASHPID}"`). Binds all child daemons (`winedevice.exe`, `explorer.exe`, crash reporters) to a dedicated cgroups v2 slice, eliminating PID 1 orphan reparenting and ensuring 100% clean teardown on exit or kill.

2. **Automated PRIME dGPU Hybrid Offloading (`detect_dgpu_vendor`)**:
   Inspects `/sys/bus/pci/devices/*/class` for secondary 3D controllers and discrete VGA endpoints. On hybrid dual-GPU systems, `--prime` automatically injects `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only` for NVIDIA and `DRI_PRIME=1` for AMD/Intel Arc.

3. **Rootless Bubblewrap Security Sandboxing (`build_sandbox_command`)**:
   Provides an opt-in rootless sandbox (`--sandbox`) utilizing `bwrap`. Mounts `$HOME` as an ephemeral tmpfs while exposing only the game directory (rw), system runtimes (ro), and display/audio sockets (Wayland/PipeWire/PulseAudio), shielding sensitive personal files (`~/.ssh`, `~/.gnupg`, browser data, `.env`) from third-party code.

4. **Single-Pass Library Scanner Optimization (`scan_installed_games`)**:
   Eliminates hundreds of subshell forks via native bash regex parsing of Steam ACF manifests and built-in path expansion. Caches discovered library states in `${XDG_RUNTIME_DIR:-/tmp/gamectl-$UID}/scancache.tab` with automated mtime invalidation, delivering sub-millisecond game listing in TUI menus.
