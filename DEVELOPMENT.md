# GAMECTL — DEVELOPER GUIDE & COMPILATION ARCHITECTURE

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
│   ├── 00_header.sh       # SSoT Constants, Tokyo Night ANSI styling palette, FZF base configuration
│   └── 10_utils.sh        # Decentralized LAN templates, remote host, save snapshots, binary discovery, ephemeral cache tier
├── steam/
│   ├── 20_discovery.sh    # Multi-path Steam root discovery, manifest scanning, active steam process guard, desktop launcher
│   ├── 25_identity.sh     # SteamID64 generation, active SteamID resolution, persona configuration, set-id
│   └── 30_downloader.sh   # Dynamic multi-drive library routing, dual-OS DepotDownloader negotiation, entitlement sync
├── runners/
│   ├── 40_wrappers.sh     # Windows runner, wineserver resolver, detect_dll_overrides, GE-Proton manager, manage_prefix
│   └── 50_launcher.sh     # Prefix isolation, normalized remote sync, P2P compatibility, PipeWire audio, wineserver guard
├── diagnostics/
│   └── 60_doctor.sh       # 7-layer health diagnostics, hardware audit, and cached query_protondb
├── tui/
│   └── 70_dashboard.sh    # Terminal previews with cache tier, interactive dashboard hub, library menu, Steam Store search
└── main.sh                # Subshell exports (export -f) and top-level CLI command dispatcher
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
for f in src/*/*.sh src/main.sh bin/gamectl scripts/build.sh; do bash -n "$f" || exit 1; done
```

### Run Comprehensive Regression & Integrity Test Suite
```bash
./tests/test_cli.sh
```

### Run System Health Diagnostics
```bash
bin/gamectl doctor
```

---

## 4. Steam Entitlement & ACF Adoption Subsystem

The Entitlement & ACF adoption engine (`src/steam/30_downloader.sh`, CLI: `gamectl entitle` / `adopt-steam` / `unlock`) enables zero-download integration with the official Steam client:
1. **Local File Adoption**: Directs Steam to recognize already existing standalone/offline game directories, avoiding duplicate downloads.
2. **Community Steam Input**: Activates Steam Input mapping, enabling native gyro, trackpad, and custom community controller layouts on handhelds (Steam Deck, ROG Ally, Legion Go).
3. **Vulkan Shader Pre-Caching**: Instructs Steam to pull and pre-compile official Vulkan pipeline shaders from Valve CDN, preventing runtime stutter during gameplay.
4. **Full DLC Activation**: Automatically resolves and registers DLC IDs via Steam Web API into `~/.config/SLSsteam/config.yaml` and creates atomic `appmanifest_<appid>.acf` manifests.

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
