# Changelog

All notable changes to `gamectl` are documented in this file according to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- **Dynamic auto-prune multi-store TUI (`Tab` & `Alt-S`)**: Library filter cycles only through stores that have installed games or active authenticated sessions (`Installed-or-Authenticated` pruning), keeping unconfigured `EPIC`/`GOG`/`AMAZON` tabs hidden.
- **GOG offline installer importer (`gamectl install-gog` / `gamectl import`)**: Extracts DRM-free `.exe` (`innoextract`) and `.sh` (MojoSetup) installers without web login, audits symlinks against traversal, initializes `$GAME_DIR/saves/` and Wine prefixes, and registers `[GOG]` library metadata.
- **P2P LAN mesh (`gamectl lan-pull` & `gamectl peers`)**: Manages companion SSH peers (`~/.config/gamectl/peers`), pulls manifests or installed games over `rsync`/SSH (excluding `pfx/`), and provides automatic LAN fallback when external Steam manifest providers return 404.
- **MIT Rust core crate (`crates/gamectl-core/`, `gamectl-core`)**: Separate MIT-licensed native engine implementing Epic OAuth2, library/assets resolution, binary (`0x44BEC00C`) and JSON manifest parsing, parallel chunk downloading (`0xB1FE3AA2`), and `epic_installed.json` tracking with `legendary` fallback preserved.
- **Store catalog preview metadata & Linux runtime hardening**: Extended Steam `appdetails` and cached Epic metadata previews, subdirectory Linux binary discovery (`Priority 5a`), and `GLIBC_TUNABLES=glibc.rtld.execstack=2` guard in `launch_game`.

### Changed
- Extracted CLI usage output from `src/main.sh` into `src/core/05_cli_help.sh`, dropping `src/main.sh` below the 600 LOC budget cap and removing its legacy ceiling.

## [1.5.0] - 2026-11-26

### Added
- **Standalone CDN downloader (`gamectl download`)**: the native Rust helper `gamectl-depot-dl` streams depots from Valve CDN without Steam Client. Standalone mode is the default (`--standalone`; legacy bridge only via `--sls`). Includes platform depot filtering (`--os linux|windows`), `+x` for downloaded Linux ELFs, full DLC manifest resolution (`harvest-dlc`), Hubcap/Ryuu/Sushi/LuaTools manifest providers, and download telemetry (`downloads`, `download-status`).
- **Optional multi-store adapters**: `gamectl stores [list|status]`, `gamectl gog` (gogdl / lgogdownloader), `gamectl epic` (legendary, including `launch`), and `gamectl amazon` (nile). External CLIs are optional; when one is missing, `doctor` reports `[OPT]` instead of a warning. The scanner tags installed GOG/Epic/Amazon games with their store and stops listing them a second time as `STANDALONE`.
- **Unified auth hub (`gamectl auth [status|gog|epic|amazon|luatools]`)**: shows session status for every store without network access and hands login to each store's own CLI. gamectl never stores or prints secrets.
- **Cross-store search (`gamectl search-stores <query> [--store all|steam|gog|epic|amazon]`)**: validated 7-column TSV with canonical item types (`GAME`, `DLC`, `DEMO`, `MOD`, `SOUNDTRACK`, `TOOL`, `APP`), plus a cross-store switcher in the search TUI.
- **Library store filter**: `Tab` cycles `ALL -> STEAM -> GOG -> EPIC -> AMAZON -> STANDALONE`; `Alt-S` opens a store picker. `Ctrl-S` remains the remote sync palette.
- **Steam catalog types and DLC guard**: `[GAME]`/`[DLC]` badges and a `Tab` type filter in Steam search. `gamectl download` refuses DLC AppIDs, suggests the base game, and accepts `--allow-dlc` to override. With no network, downloads continue without the type check.
- **Standalone Steam Runtime (`gamectl setup-runtime`)**: installs Steam Runtime (Scout) into `~/.local/share/gamectl/runtime/steam-runtime` after SHA-256 verification and a tar traversal/link audit, using a staged install with rollback. Native Linux launches look for a runtime in this order: `GAMECTL_STEAM_RUNTIME_RUN`, the standalone runtime, then an existing Steam install. Opt out with `native_runtime=host` or `GAMECTL_NATIVE_RUNTIME=host`. `doctor` audits the runtime.
- **GBE Fork provisioning**: `gamectl setup-gbe` installs emulator templates. Injection generates `steam_settings/steam_interfaces.txt` from the original Steamworks library, and launch is blocked (hard-stop) for unshielded Steamworks binaries.
- **SteamStub tooling**: `detect-steamstub` and `unpack-stub` for Windows PE and 32/64-bit Linux ELF `.bind` binaries.
- **Save recovery and sync**: `restore <dir> [slot]`, `sync-pull`, Wine prefix save discovery (`scan-saves`, `collect-saves`, `restore-prefix-saves`), custom remote base paths, an optional rclone backend, and `--dry-run` for `pfx clean`, `fix-revert`, and sync.
- **Diagnostics**: `doctor` layer 8 (sandbox and process isolation), a Vulkan/multilib audit, capability-based DXVK vs WineD3D selection, and `dev-profile` for WINEDEBUG/Vulkan loader/GBE logging.
- **Live TUI process sync**: the library refreshes when a launched game exits (fzf `--listen` socket events), shows running/crash badges, and reports missing ELF shared libraries and crash log hints when a game fails to start.
- **Centralized runtime logs**: `gamectl logs` and an in-dashboard activity log viewer.

### Changed
- Standalone operation is the architectural default. Steam Client / SLSsteam bridge commands (`entitle`, `sync-steam`, `deploy-manifest`, `restart-steam`, `inject --all`) run only when explicitly requested.
- Split the sources into domain modules under a LOC budget (`scripts/check_loc_budget.sh`, at most 600 lines per new module). `make lint` runs ShellCheck in parallel, and `STRICT_LINT=1` fails when ShellCheck is missing.
- Packaging: the `.deb` is built for the native architecture (amd64/arm64); Arch packages target `x86_64`/`aarch64` and build `gamectl-depot-dl` from locked Cargo sources; Nix builds it with `buildRustPackage`; the PyPI wheel contains only Python and the Bash bundle, with no native ELF.
- `gamectl-depot-dl`: upgraded to `zip` 9.x and patched `rustls`, `tokio`, and `zstd` releases (OSV audit: 0 vulnerable crates). Added retries with exponential backoff, CDN server rotation, and a file-handle limit to prevent `EMFILE`.

### Fixed
- Make the standalone project purpose authoritative, remove unsupported readiness/performance claims, and stop treating optional bridge YAML or Steam lock cleanup as standalone requirements.
- Keep GBE injection and OnlineFix setup offline by default; Steam synchronization requires an explicit bridge action or `inject --all`.
- Preserve original libraries on injection failures, verify installed template bytes before launch, and propagate standalone provisioning errors.
- Keep game tracking and process scopes active until the launched process exits.
- Reject unsupported save recovery slots and path-like slot arguments before modifying current saves.
- Load the core logging utilities in downloader regression fixtures, matching the bundled application's module dependencies.
- Make `make lint` validate every shell file individually, including tests and shell completions. Previously, Bash parsed only the first file and treated the remaining paths as script arguments.
- Stage and verify save restores before replacing live saves, and refuse to restore while the game is running.
- Remote sync now reports transfer and backup failures, resolves remote home paths correctly, and makes no local changes during `--dry-run`.
- Check PID liveness safely when processes become zombies, and guard against stale library selections after a game exits.
- Detect multi-arch Linux launch targets by ELF class and shebang scripts.
- Restore terminal state on exit, errors, and signals, and show captured TUI action output with the real exit code.

## [1.4.0] - 2026-11-07

### Added
- **Automated Game Fix Harvester (`gamectl fix-check`, `gamectl fix-install`)**:
  - Direct integration with LuaTools API (`/api/denuvo/fixes?appid=...`) and Cloudflare R2 presigned S3 downloads.
  - Public unauthenticated querying for game fix availability across 1,861 catalogued titles.
  - Prioritized ranking engine: Online-Fix (`online-fix`) > Voices38 (`voices38-crack`) > Generic (`generic`).
  - Automatic game directory resolution from Steam `appmanifest_<appid>.acf`.
  - Zip-Slip security audit defending against path traversal attacks in third-party archives.
  - Steam Play (Proton) compatibility audit warning when Windows DLL fixes are applied to native Linux titles.
  - Custom crack launcher detection (`Launcher.exe`) with recommended Steam Launch Options.
  - Automated post-extraction chaining to `setup_onlinefix` (Spacewar 480 entitlement, PlayerName sync, WINEDLLOVERRIDES).
- **Atomic Revert Engine (`gamectl fix-revert`)**:
  - Automatically snapshots original files to `.gamectl_fix_backup/` before extraction.
  - Purges fix-introduced DLLs/artifacts and restores original vanilla binaries on demand.
- **Graceful Steam Client Hot-Reload (`gamectl restart-steam`, `--restart` flag)**:
  - Supervisor-aware graceful restart supporting Steam Deck Game Mode (`steam-launcher.service` / `gamescope-session`) and desktop SLSsteam wrapper (`~/.local/share/SLSsteam/path/steam`).
  - Flush writes (`sync`), SIGTERM graceful teardown with timeout, and clean process relaunch.

## [1.3.0] - 2026-11-07

### Added
- **SLSsteam Native CDN Downloader**: Complete migration to native Steam client downloading directly from official Valve CDN at uncapped line speeds.
- **Multi-Provider Manifest Harvester (`fetch-manifest`)**: Parallel and fallback scraping across Ryuu direct mirror, Sushi repository, and Lua.tools managed API with binary magic (`0xd017f671`) verification.
- **SLSsteam Stplug-in & Manifest Linker (`deploy-manifest`)**: Automatic deployment of `.manifest` files into `~/.config/SLSsteam/manifests/` and `~/.local/share/Steam/depotcache/`, `.preferred_<depot>` pinning, and synthesis of `stplug-in/<appid>.lua` with AES-256 decryption keys.
- **Real-Time ACF Telemetry & Interactive Monitor (`gamectl downloads`)**: Live parsing of Steam `appmanifest_<appid>.acf` StateFlags (Downloading, Paused, Installed) and byte progress tracking with human-readable formatting.
- **Sovereign LuaTools Token Auto-Refresh**: Background Supabase token renewal (`expires_at <= now + 60s`) stored in `~/.config/gamectl/lua_tools_auth.json` with Cloudflare WAF header bypass (`User-Agent: discord(dot)gg/luatools`).
- **Raw Lua Manifest Encapsulation**: Automatic wrapping of raw text `.lua` stplugin scripts into standardized `${appid}.zip` archives on the fly.
- **Standalone Authentication CLI**: Subcommands `gamectl auth-status` and `gamectl login-luatools <code|token|file>` allowing login without Lumen or browser extensions.
- **TUI Dashboard Cockpit Indicators**: Dynamic SLSsteam integration and Steam Client runtime status badges in the main cockpit.

### Removed
- **Legacy DepotDownloader Deprecation**: Completely eliminated .NET DepotDownloader binary downloader, background forks, and pgrep monitor loops (-544 lines).

---

## [1.2.1] - 2026-11-06

### Added
- Multi-Platform packaging automation (`packaging/scripts/build-all.sh`) supporting Debian (`.deb`), Arch Linux (`PKGBUILD` + `.SRCINFO`), and PyPI wheel distribution.
- Automated PyPI publishing via GitHub Actions Trusted Publishing (OIDC).
- Dual-Engine Windows Support RFC (`docs/RFC_WINDOWS_SUPPORT.md`) specifying pure PowerShell (`.ps1`) architecture.

### Fixed
- ZSH subshell preview variable collisions in TUI dialogs.
- Stdin sanitization and decoupling of fzf menu loop exit codes (zero-match Enter resilience).

---

## [1.2.0] - 2026-11-06

### Added
- **Linux Kernel Process Isolation**: Transient cgroup v2 units via `systemd-run --user --scope` (`--scope`).
- **Hybrid PRIME GPU Offloading**: Automated discrete GPU vendor detection (`--prime`) for NVIDIA and AMD/Intel.
- **Rootless Bubblewrap Sandboxing**: Bwrap security profile (`--sandbox`) shielding `$HOME` secrets (`~/.ssh`, `~/.gnupg`, cookies).
- **Optimized Library Scanner**: Single-pass regex ACF parser with runtime disk cache.

---

## [1.0.0] - 2026-11-05

### Added
- Initial sovereign release of `gamectl` TUI game manager and launcher.
- 7-layer health diagnostics engine (`gamectl doctor`).
- 3-slot rotating savegame disaster guard.
- Decentralized LAN emulator and DLC injector (`gamectl inject`).
- Isolated Windows runner prefix manager (`gamectl pfx`).
