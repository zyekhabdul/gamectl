<div align="center">

# gamectl

### Sovereign TUI Game Manager & Launcher for Linux Purists

*A lightweight, standalone Steam replacement designed for long-term maintenance.*

[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20SteamDeck-blue?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/zyekhabdul/gamectl)
[![Shell](https://img.shields.io/badge/Shell-POSIX%20Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://github.com/zyekhabdul/gamectl)
[![PyPI](https://img.shields.io/badge/PyPI-gamectl-3775A9?style=for-the-badge&logo=pypi&logoColor=white)](https://pypi.org/project/gamectl/)
[![License](https://img.shields.io/badge/License-MIT-purple?style=for-the-badge)](LICENSE)
[![Display](https://img.shields.io/badge/Compositor-Wayland%20%7C%20X11-orange?style=for-the-badge&logo=wayland&logoColor=white)](https://github.com/zyekhabdul/gamectl)
[![Packaging](https://img.shields.io/badge/Packaging-Arch%20PKGBUILD%20%7C%20Universal-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)](packaging/arch/PKGBUILD)

```bash
# Turnkey Instant Installation
curl -fsSL https://raw.githubusercontent.com/zyekhabdul/gamectl/main/install.sh | bash
```

[Quickstart](#quick-installation) • [Project purpose](docs/SOVEREIGN_ORIGINAL_PURPOSE.md) • [Core Capabilities](#core-capabilities) • [Keyboard Shortcuts](#keyboard-shortcuts-reference) • [CLI Reference](#cli-command-reference) • [Ecosystems](#supported-ecosystems--handhelds) • [Architecture](docs/ARCHITECTURE.md)

</div>

---

```text
╭─ GAMECTL SOVEREIGN COCKPIT ──────────────────┬─ RUNTIME INSPECTION ──────────────────────────────╮
│ [GBE_FORK]  Hades II                         │ AppID     : 1145360 (Hades II)                    │
│ [VALVE_DLL] Balatro                          │ Arch      : Windows PE32+ (x86_64)                │
│ [STANDALONE] Dead Cells                      │ Runner    : GE-Proton9-25 (~/.local/share/Steam/) │
│ [GBE_FORK]  Factorio                         │ Prefix    : Isolated ($GAME_DIR/pfx)              │
│ [STANDALONE] Slay the Spire                  │ Wrappers  : GameMode: ON │ MangoHud: ON │ FSR: OFF│
│ [VALVE_SO]  Celeste                          │ Audio     : PipeWire 256/48000 (Low Latency)      │
│ [GBE_FORK]  Hollow Knight: Silksong          │ Saves     : 3-Slot Disaster Guard (slot1/slot2)   │
│ [STANDALONE] Terraria                        │ Sandbox   : Bubblewrap (bwrap: ~/.ssh shielded)   │
│ [VALVE_DLL] Elden Ring                       │ Isolation : cgroups v2 (systemd-run scope)        │
╰──────────────────────────────────────────────┴───────────────────────────────────────────────────╯
```

**gamectl** is a Steam replacement for managing, downloading, and launching supported games. Its goals are low resource use, standalone operation, and long-term stability. The core workflow does not require Steam Client or SLSsteam.

It uses a native CLI/TUI, isolated runtime prefixes, local multiplayer configuration, and savegame snapshots. Follow [the project purpose](docs/SOVEREIGN_ORIGINAL_PURPOSE.md) when changing code or agent memory; legacy Steam bridge commands are not an implementation target or a fix for standalone failures.

---

## Performance and Verification

Low memory use and fast startup are design goals. Publish measured values only with the command, environment, revision, and scope that produced them. Passing local tests does not prove compatibility with every game or long-term runtime stability.

---

## Supported Ecosystems & Handhelds

| Ecosystem / Platform | Target Architecture | Support Level | Integration Details |
| :--- | :--- | :--- | :--- |
| **Arch Linux / EndeavourOS** | x86_64 | **Native Tier 1** | Standalone binary & `packaging/arch/PKGBUILD` AUR recipe |
| **Steam Deck (SteamOS)** | AMD Van Gogh (x86_64) | **Native Tier 1** | Desktop Mode TUI + Steam Deck Game Mode (`shortcuts.vdf` + artwork) |
| **Bazzite / ChimeraOS** | Immutable Linux | **Native Tier 1** | Rootless turnkey installation to `~/.local/bin/` |
| **Debian / Ubuntu / Linux Mint** | x86_64 | **Verified** | Standard package dependencies via APT |
| **Fedora / Nobara** | x86_64 | **Verified** | Standard package dependencies via DNF |
| **Wayland (Niri / Sway / Hyprland)** | Wayland socket pass-through | **Verified** | Full Gamescope FSR & dynamic `$WAYLAND_DISPLAY` binding |
| **X11 (i3 / bspwm / XFCE)** | Native X11 | **Verified** | Automatic `$XAUTHORITY` and DISPLAY detection |
| **Handheld PCs (ROG Ally, Legion Go)** | AMD Phoenix / Z1 Extreme | **Verified** | Low-overhead execution freeing maximum VRAM for 3D shaders |

---

## Core Capabilities

- **Small Native Runtime**: Bash, `fzf`, `jq`, and a native Rust downloader; no embedded browser runtime.
- **Dynamic Multi-Library & Multi-Store Discovery**: Automatically scans Steam (`libraryfolders.vdf` + ACF), optional GOG (`gogdl`/`lgogdownloader`), Epic (`legendary`), Amazon (`nile`), Lutris, and standalone directories (`~/Games/`, `~/.config/gamectl/libraries`, `GAMECTL_LIBRARY_DIRS`) without duplicate entries.
- **Split-Pane Live Inspection & Event-Driven Exit Sync**: Left pane lists your library with ANSI status badges (`[RUNNING]`, `[CRASHED]`, `[EXITED]`); `fzf --listen` refreshes automatically when a game exits, surfaces missing ELF shared libraries and crash hints, and guards against stale selections.
- **Standalone Steam Runtime (Scout) & Native Fallback (`gamectl setup-runtime`)**: Provisions Valve's Steam Runtime into `~/.local/share/gamectl/runtime/steam-runtime` with SHA-256 verification and tar traversal/link checks. Native Linux launches prioritize the standalone runtime before Steam installs (opt out with `native_runtime=host` or `GAMECTL_NATIVE_RUNTIME=host`).
- **cgroups v2 Process Tree Isolation (`gamectl launch --scope`)**: Encapsulates game execution in a dedicated systemd user scope (`gamectl-<title>-<pid>`), terminating all background helpers (`winedevice.exe`, `explorer.exe`, crash reporters) atomically on exit with zero zombie processes.
- **Automated PRIME Hybrid dGPU Offload (`gamectl launch --prime`)**: Auto-probes `/sys/bus/pci/devices/` and routes rendering to secondary discrete NVIDIA (`__NV_PRIME_RENDER_OFFLOAD=1`), AMD, or Intel Arc (`DRI_PRIME=1`) controllers without manual environment variable hacking.
- **Rootless Bubblewrap Security Sandbox (`gamectl launch --sandbox`)**: Mounts host root as read-only and shields private directories (`~/.ssh`, `~/.gnupg`, browser cookies, and `.env` credentials) inside a hardened tmpfs namespace while transparently passing Wayland/X11 and PipeWire audio sockets.
- **Disaster-Proof Savegame Snapshots**: Automatically creates a 3-slot rotating backup (`slot1`, `slot2`, `slot3`) before each game launch, safeguarding your save states against crashes and dirty shutdowns.
- **Decentralized LAN Steam Emulator (`gamectl inject`, `gamectl setup-gbe`)**: Auto-provisions GBE Fork templates, generates `steam_settings/steam_interfaces.txt` from original Steamworks binaries, redirects saves to `./saves`, generates `steam_settings/DLC.txt`, and guards against unshielded Steamworks or SteamStub binaries (`detect-steamstub` / `unpack-stub`).
- **Isolated Windows Runner & Prefix Engine**: Discovers installed Windows compatibility runners (`umu-run` -> `GE-Proton` / Steam `Proton` -> `wine`) and maintains strictly isolated prefixes in `$GAME_DIR/pfx`, keeping host `~/.wine` pristine.
- **Modular Performance Wrappers**: On-the-fly toggle for `gamemoderun`, `mangohud`, `gamescope` dynamic FSR upscaling, and Mesa multithreaded GL via interactive dialogs (`<Ctrl-O>`) or CLI flags.
- **LAN Multi-Identity & SteamID Manager (`gamectl set-id`)**: Generates deterministic 17-digit SteamID64 tokens and distinct LAN gamer tags to prevent co-op network collisions, with custom peer discovery (`custom_broadcasts.txt`).
- **Standalone CDN Downloader (`gamectl download`)**: Uses manifest providers and native Rust streaming (`gamectl-depot-dl`) without requiring Steam Client, enforcing an engine-level DLC guard (`--allow-dlc` to opt in). Missing manifests, keys, or failed provisioning produce errors instead of switching clients.
- **Optional Multi-Store Adapters & Unified Auth Hub (`gamectl auth`, `gamectl search-stores`)**: Integrates optional GOG (`gogdl`/`lgogdownloader`), Epic (`legendary`), and Amazon (`nile`) CLIs alongside Steam/Standalone, with offline-safe session checks and cross-store search (`GAME`/`DLC`/`DEMO`/`MOD`/`SOUNDTRACK`/`TOOL`/`APP`).
- **Mod DLL Overrides & Local P2P Configuration (`gamectl mod-overrides`)**: Detects mod loaders and local compatibility files and prepares `WINEDLLOVERRIDES` without registering Steam entitlements.
- **Headless GE-Proton Release Manager (`gamectl proton-*`)**: Fetches upstream GitHub releases, streams tarball installation directly into `~/.local/share/Steam/compatibilitytools.d/`, and prunes older versions safely.
- **Wine Prefix Swiss Army Knife (`gamectl pfx`) & Wineserver Guard**: Dedicated maintenance toolkit (`winecfg`, `regedit`, `cmd`, `shell`, `winetricks`, `kill`, `clean`) with deterministic wineserver teardown (`wineserver -w` / `-k`) to eliminate registry lock contention.
- **Real-Time PipeWire Audio Scheduling**: Exports optimal quantum buffer configurations (`PIPEWIRE_LATENCY="256/48000"`, `PULSE_LATENCY_MSEC=60`) to prevent audio crackling and buffer starvation during high CPU spikes.
- **One-Key Multi-Node Sync (`<Ctrl-S>`)**: Synchronizes portable save states to secondary handhelds or remote servers over SSH/Rsync with pre-flight network checks.
- **Multi-Store Catalog & ProtonDB Compatibility Audit**: Fast online search across Steam and Multi-Store adapters (GOG/Epic/Amazon) with essential metadata (estimated size, release date, price, DLC count) and live ProtonDB Linux compatibility tier ratings (Native, Platinum, Gold, Silver, Bronze, Borked).

---

## Keyboard Shortcuts Reference

The interactive TUI library navigation provides instantaneous single-keystroke operations:

| Shortcut | Action Description |
| :--- | :--- |
| `<ENTER>` | Launch Game (or open Running Process Controller if `[RUNNING]`) |
| `<Tab>` | Cycle Store Filter (`ALL -> STEAM -> GOG -> EPIC -> AMAZON -> STANDALONE`) |
| `<Alt-S>` | Open Store Filter Picker (Library) / Switch to Cross-Store Search (Search) |
| `<Ctrl-O>` | Configure Runtime Wrappers (GameMode / MangoHud / Gamescope FSR / Mesa GL) |
| `<Ctrl-P>` | Configure LAN Multiplayer Gamer Tag & SteamID64 Persona (Process HUD on Dashboard) |
| `<Ctrl-I>` | Inject Decentralized LAN Runtime & Portable Saves |
| `<Ctrl-S>` | Sync Portable Savegame to Remote Companion Host via SSH / Rclone |
| `<Ctrl-B>` / `<Ctrl-R>` | Create Manual Save Snapshot (`Ctrl-B`) / Restore Snapshot Slot (`Ctrl-R`) |
| `<Ctrl-F>` / `<Ctrl-X>` | Search Store Catalog & ProtonDB (`Ctrl-F`) / Community Fixes (`Ctrl-X`) |
| `<Ctrl-D>` / `<Ctrl-L>` | Create Desktop Entry (`Ctrl-D`) / View Activity Logs (`Ctrl-L`) |
| `<ESC>` / `<Ctrl-C>` | Return to Master Dashboard Hub / Exit |

---

## Multi-Platform Installation

### Option 1: Turnkey One-Liner (Universal Linux & Steam Deck)
```bash
curl -fsSL https://raw.githubusercontent.com/zyekhabdul/gamectl/main/install.sh | bash
```

### Option 2: Arch Linux (AUR & AUR-Git)
```bash
# Release package:
yay -S gamectl
# or development branch (VCS):
paru -S gamectl-git
```

### Option 3: Debian / Ubuntu (.deb Package)
```bash
# Build and install Debian package:
make pkg-deb
sudo dpkg -i packaging/debian/gamectl_1.5.0_amd64.deb
sudo apt install -f
```

### Option 4: Homebrew Tap (Linux & macOS)
```bash
brew tap zyekhabdul/tap
brew install gamectl
```

### Option 5: Nix Flake (NixOS / Declarative)
```bash
# Run directly without installation:
nix run github:zyekhabdul/gamectl

# Or add to your NixOS flake inputs:
# inputs.gamectl.url = "github:zyekhabdul/gamectl";
```

### Option 6: Python Package (pipx & pip)
```bash
# Recommended for modern Linux (PEP 668):
pipx install gamectl

# Or inside standard virtualenv:
pip install gamectl
```

### Option 7: Manual Source Clone & Turnkey Installer
```bash
git clone git@github.com:zyekhabdul/gamectl.git
cd gamectl
./install.sh
```

The turnkey installer automatically executes:
1. Compiles or symlinks standalone binary `gamectl` and shorthand alias `game` to `~/.local/bin/`.
2. Scaffolds configuration directory and templates in `~/.config/gamectl/`.
3. Installs shell completion script to `~/.local/share/bash-completion/completions/gamectl`.
4. Registers FreeDesktop entry `gamectl.desktop` for Wayland/X11 application launchers (rofi, fuzzel, wofi, dmenu).
5. Verifies runtime availability of manifest harvesting tools (curl, jq, zip, unzip) and compatibility templates.

---

## CLI Command Reference

`gamectl` is fully operational as both an interactive TUI and a scriptable CLI tool:

### 1. Interactive TUI Navigation
```bash
gamectl               # Launch Master Dashboard Hub TUI
gamectl library       # Open Game Library TUI directly (alias: list-ui)
gamectl config        # Open global configuration editor (alias: configure)
gamectl doctor        # Run 8-layer system & GPU health diagnostics (alias: audit)
gamectl logs          # View centralized runtime activity logs
```

### 2. Launching Games
```bash
# Launch with MangoHud and GameMode enabled:
gamectl launch "$HOME/Games/DeadCells" --hud --gamemode

# Launch Windows executable with Gamescope FSR upscaling:
gamectl launch "$HOME/Games/WindowsGame" game.exe --gamescope --fsr

# Launch with cgroups v2 process tree isolation (systemd-run scope):
gamectl launch "$HOME/Games/HeavyGame" --scope

# Launch with automated PRIME hybrid discrete GPU offloading (NVIDIA / AMD / Intel Arc):
gamectl launch "$HOME/Games/3DGame" --prime

# Launch inside rootless Bubblewrap (bwrap) security sandbox (shielding ~/.ssh, ~/.gnupg, cookies):
gamectl launch "$HOME/Games/UntrustedGame" --sandbox

# Configure per-game wrapper persistence:
gamectl configure-wrappers "$HOME/Games/DeadCells"
```

### 3. Linux Kernel Isolation & Hardware Diagnostics
```bash
# Detect discrete secondary GPU vendor on hybrid laptop/desktop systems:
gamectl detect-gpu

# Check if systemd-run user scope cgroups v2 isolation is supported:
gamectl check-scope

# Check if Bubblewrap rootless sandbox profile is available:
gamectl check-sandbox
```

### 4. P2P Multiplayer Compatibility & Mod DLL Overrides
```bash
# Setup local P2P compatibility and DLL overrides without Steam registration:
gamectl mod-overrides "$HOME/Games/CoopGame"

# Backward-compatible command alias:
gamectl onlinefix "$HOME/Games/CoopGame"

# Optional Steam Client bridge, only when deliberately requested:
gamectl sync-steam 480 Spacewar "$HOME/Games/CoopGame"
```

`gamectl inject <dir> [appid]` prepares the offline runtime without syncing Steam.
Use `gamectl inject <dir> <appid> --all` to explicitly request Steam synchronization.
Injection and standalone provisioning return an error when a required template or file operation fails.

### 5. GE-Proton Release Manager
```bash
# Query installed local releases vs latest upstream releases on GitHub:
gamectl proton-list

# Install latest GE-Proton release (or specify version tag):
gamectl proton-install latest
gamectl proton-install GE-Proton9-25

# Safely remove an obsolete GE-Proton version:
gamectl proton-remove GE-Proton8-26
```

### 6. Wine Prefix Swiss Army Knife (`pfx`)
```bash
# Open interactive prefix management menu:
gamectl pfx "$HOME/Games/MyGame"

# Execute Windows utilities inside the isolated prefix:
gamectl pfx "$HOME/Games/MyGame" winecfg
gamectl pfx "$HOME/Games/MyGame" regedit
gamectl pfx "$HOME/Games/MyGame" cmd
gamectl pfx "$HOME/Games/MyGame" shell
gamectl pfx "$HOME/Games/MyGame" winetricks d3dx9 vcrun2022

# Teardown stuck wineserver processes gracefully (DEFECT-02):
gamectl pfx "$HOME/Games/MyGame" kill

# Reset prefix with automatic savegame backup:
gamectl pfx "$HOME/Games/MyGame" clean -y
```

### 7. Decentralized LAN Steam Runtime & Portable Saves
```bash
# Prepare the standalone LAN runtime and portable saves without Steam sync:
gamectl inject "$HOME/Games/Limbo" 48000

# Provision Goldberg templates and standalone Steam Runtime (Scout):
gamectl setup-gbe
gamectl setup-runtime

# Inspect or unpack SteamStub DRM binaries (Windows PE & Linux ELF .bind):
gamectl detect-steamstub "$HOME/Games/MyGame/game.bin"
gamectl unpack-stub "$HOME/Games/MyGame/game.bin"

# Inject standalone LAN runtime only (zero Steam client sync):
gamectl inject "$HOME/Games/Limbo" 48000 --no-sync

# Configure LAN player persona and SteamID64:
gamectl set-id "PlayerTwo" auto "$HOME/Games/Valheim"
gamectl set-id "Alice" 76561198123456789 "$HOME/Games/Valheim" --broadcast "192.168.1.50"
gamectl set-id "MyGamerTag" auto --global
```

### 8. Headless Asset Downloader Engine
```bash
# Download supported game files and prepare the standalone runtime:
gamectl download 48000 "$HOME/Games/Limbo" "LIMBO"

# Allow downloading a DLC AppID explicitly (otherwise blocked with base-game hint):
gamectl download 123456 "$HOME/Games/MyGame" --allow-dlc

# Download game assets only without injection:
gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" --raw

# Run download in foreground (live stream logs):
gamectl download 48000 "$HOME/Games/Limbo" "LIMBO" -f

# Monitor active and completed download tasks:
gamectl downloads
gamectl download-status
```

### 8a. Multi-Store Adapters, Unified Auth & Cross-Store Search
```bash
# Inspect registered stores (steam, gog, epic, amazon) and offline auth state:
gamectl stores status
gamectl auth status

# Delegate authentication to native optional store CLIs or LuaTools:
gamectl auth gog        # or: gamectl gog auth
gamectl auth epic       # or: gamectl epic auth
gamectl auth amazon     # or: gamectl amazon auth
gamectl auth luatools <code|token|session.json>

# Search across all available stores (or filter to one store):
gamectl search-stores "Hollow Knight"
gamectl search-stores "Cyberpunk" --store gog

# Store-specific CLI commands (optional CLIs: gogdl/lgogdownloader, legendary, nile):
gamectl gog <status|auth|search|download|sync>
gamectl epic <status|auth|search|download|sync|launch>
gamectl amazon <status|auth|search|download|sync>
```

### 9. Legacy Steam Bridge Commands (Explicit Opt-In)
These compatibility commands target an external Steam Client. They are outside the standalone workflow, are not required for gamectl readiness, and must not be used as a recovery fallback or as a reason to install Steam/SLSsteam:

```bash
# Entitle AppID, adopt local assets, and register full DLC into Steam:
gamectl entitle 1145360 "Hades II"     # Aliases: unlock, adopt-steam

# Synchronize installed standalone game files with Steam client:
gamectl sync-steam 427520 "Factorio" "$HOME/Games/Factorio"
```

### 10. ProtonDB Compatibility Audit & Shortcuts
```bash
# Query ProtonDB rating by AppID:
gamectl protondb 105600

# Query ProtonDB rating by game directory:
gamectl protondb "$HOME/Games/Terraria"

# Generate FreeDesktop .desktop application launcher:
gamectl make-desktop "$HOME/Games/Terraria" "Terraria"
```

### 11. Automated Game Fixes & Steam Lifecycle Engine
Directly queries community bypasses and Online-Fixes from LuaTools API & Cloudflare R2, extracts them with zip-slip safety audits, creates atomic rollback snapshots, and hooks Spacewar 480 automatically:

```bash
# Query available community fixes & Online-Fix bypasses (Public, zero auth required):
gamectl fix-check 470220

# Download, verify, backup, and deploy Online-Fix directly to game directory:
gamectl fix-install 470220 "$HOME/Games/UNO" --type online --yes

# Auto-resolve game directory from Steam libraries and restart Steam client:
gamectl fix-install 470220 --restart

# Revert deployed game fix and restore original pristine vanilla files:
gamectl fix-revert "$HOME/Games/UNO"

# Gracefully hot-reload running Steam client (Steam Deck Game Mode & Client Bridge):
gamectl restart-steam
```

### 12. Multi-Node Savegame Synchronization
```bash
# Synchronize local savegame snapshots to configured remote companion host:
gamectl --sync "$HOME/Games/Terraria" "Terraria"
gamectl sync-pull "$HOME/Games/Terraria" "Terraria"

# Create or restore savegame snapshot slots (1-3) and inspect Wine prefix saves:
gamectl --backup "$HOME/Games/Terraria"
gamectl restore "$HOME/Games/Terraria" 1
gamectl scan-saves "$HOME/Games/WindowsGame"
```

---

## Configuration & Environment Variables

`gamectl` respects XDG Base Directory standards and standard Linux configuration paths:

| File / Variable | Description |
| :--- | :--- |
| `~/.config/gamectl/libraries` | Plaintext list of custom game library search paths (one per line). |
| `~/.config/gamectl/wrappers` | Global default wrapper preferences (`gamemode=1`, `hud=1`, `gamescope=0`). |
| `~/.config/gamectl/remote_host` | Hostname or IP of companion remote sync node (`user@hostname`). |
| `~/.config/gamectl/persona` | Global default player gamer tag and SteamID64. |
| `GAMECTL_LIBRARY_DIRS` | Environment variable to inject extra library search paths dynamically. |
| `GAMECTL_RUNTIME_DIR` | Override standalone Steam Runtime directory (default `~/.local/share/gamectl/runtime/steam-runtime`). |
| `GAMECTL_NATIVE_RUNTIME` | Set to `host` / `off` to bypass Steam Runtime wrapper for native Linux games. |
| `XDG_RUNTIME_DIR/gamectl-$UID/` | Ephemeral runtime directory for active game tracking, exit events, and locks. |

---

## Project Structure

```text
gamectl/
├── bin/
│   └── gamectl          # Monolithic standalone compiled executable (source-to-bundle)
├── completions/
│   └── gamectl.bash     # Shell autocompletion script (Bash / Zsh)
├── crates/depot-dl/     # Native Rust Valve CDN downloader (gamectl-depot-dl)
├── docs/
│   ├── ARCHITECTURE.md  # Deep dive into headless Linux game management architecture
│   └── GUIDE.md         # Operational handbook, prefix isolation, and disaster recovery
├── packaging/
│   ├── arch/            # Arch Linux PKGBUILD & AUR recipes
│   └── debian/          # Debian .deb packaging script
├── scripts/
│   ├── build.sh         # Source-to-bundle deterministic compilation script
│   ├── build-depot-dl.sh # Native Rust Steam CDN depot downloader compiler
│   └── check_loc_budget.sh # Module LOC budget & legacy ratchet guard
├── src/
│   ├── core/            # Constants, utils, TUI primitives, saves, SteamStub, process runtime
│   ├── diagnostics/     # 8-layer system health audit and ProtonDB client
│   ├── runners/         # Wrappers, Proton/Wine prefix & runtime provisioners, launcher, sync, GBE
│   ├── steam/           # Multi-path discovery, identity, CDN downloader, manifests, fixes
│   ├── stores/          # Store interface registry & Steam/GOG/Epic/Amazon adapters
│   ├── tui/             # Master dashboard hub, preview cards, multi-store & Steam search
│   └── main.sh          # Subshell exports and CLI command dispatcher
├── tests/
│   └── test_cli.sh      # Comprehensive regression & integrity harness (50+ tests)
├── gamectl.desktop      # FreeDesktop application launcher entry
├── install.sh           # Turnkey installation script
└── README.md            # Project manifesto, benchmarks, and command dictionary
```

---

## Community & Stargazers

If `gamectl` freed your RAM, eliminated background browser bloat, or improved your Linux gaming workflow, consider starring the repository on GitHub!

[![Star History Chart](https://api.star-history.com/svg?repos=zyekhabdul/gamectl&type=Date)](https://star-history.com/#zyekhabdul/gamectl&Date)

- **Issues & Discussions**: Found an edge-case or want to propose an optimization? Open an issue on GitHub.
- **Contributions**: Packaging recipes (Nix, Flatpak, Void, Alpine) and hardware profiles are welcome via Pull Requests.

---

## License & Legal Notice

`gamectl` (Bash TUI/CLI, runtime wrappers, and packaging scripts) is distributed under the **MIT License**. See [LICENSE](LICENSE) for details.

The companion native Rust depot downloader binary `gamectl-depot-dl` ([crates/depot-dl/](crates/depot-dl/)) is derived from `steam-depot-downloader-mod` and distributed separately under **GPL-2.0-only** (see [crates/depot-dl/Cargo.toml](crates/depot-dl/Cargo.toml)).

`gamectl` is an independent open-source utility designed for managing standalone local game files and compatibility runners on Linux. It does not distribute, host, or bypass proprietary encryption on copyrighted game software. All trademarks and brand names belong to their respective owners.
