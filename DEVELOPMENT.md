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
│   └── 10_utils.sh        # Decentralized LAN templates, remote host, save snapshots, binary discovery
├── steam/
│   ├── 20_discovery.sh    # Multi-path Steam root discovery, manifest scanning, and desktop launcher generation
│   ├── 25_identity.sh     # SteamID64 generation, active SteamID resolution, persona configuration, set-id
│   └── 30_downloader.sh   # Asset fetching, multi-arch DepotDownloader engine, downloads monitor, entitlement sync
├── runners/
│   ├── 40_wrappers.sh     # Windows runner, detect_dll_overrides, GE-Proton manager, manage_prefix (pfx)
│   └── 50_launcher.sh     # Prefix isolation, P2P compatibility (setup_onlinefix), PipeWire audio, wineserver guard
├── diagnostics/
│   └── 60_doctor.sh       # 7-layer health diagnostics, hardware audit, and query_protondb
├── tui/
│   └── 70_dashboard.sh    # Terminal previews, interactive dashboard hub, library menu, Steam Store search
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
