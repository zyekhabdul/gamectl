# Changelog

All notable changes to `gamectl` are documented in this file according to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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
