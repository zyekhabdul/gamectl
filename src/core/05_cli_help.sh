# ==============================================================================
# gamectl - CLI Usage & Help Output Module (Split from src/main.sh)
# ==============================================================================

print_cli_help() {
    cat <<'EOF'
gamectl - Sovereign TUI Game Manager & Launcher (Zero-Bloat)

Usage:
  gamectl [menu]      Open Master Dashboard Hub TUI (alias: dashboard)
  gamectl library     Open Game Library TUI directly (alias: list-ui)
  gamectl config [set <k> <v>|get <k>|list]
                      Open global configuration menu or read/write settings (~/.config/gamectl/config)
  gamectl doctor      Run 8-layer system & GPU health diagnostics (alias: audit)
  gamectl stores [list|status]
                      Inspect registered store adapters and offline readiness
  gamectl gog <status|auth|search|download|sync|install-offline> [args...]
                      GOG adapter (gogdl/lgogdownloader or native offline extractor)
  gamectl install-gog <setup.exe|installer.sh> [target_dir] [--title <name>] [--no-prefix]
                      Extract DRM-free GOG offline installer without login & setup prefix (alias: import)
  gamectl epic <status|auth|search|download|sync|launch> [args...]
                      Epic Games adapter (native gamectl-core engine or legendary fallback)
  gamectl amazon <status|auth|search|download|sync> [args...]
                      Optional Amazon Prime Gaming adapter (delegates to nile)
  gamectl auth [status|gog|epic|amazon|luatools] [args...]
                      Unified offline auth status and native CLI login delegation
  gamectl search-stores <query> [--store <all|steam|gog|epic|amazon>]
                      Cross-store catalog search with canonical app-type taxonomy
  gamectl launch <dir> [bin] [title] [--hud] [--gamemode] [--gamescope] [--fsr] [--glthread] [--scope|--no-scope] [--prime|--no-prime] [--sandbox|--no-sandbox]
                      Launch game with isolated prefix and runtime wrapper options
  gamectl configure-wrappers <dir> [title]
                      Configure per-game wrappers (GameMode/MangoHud/Gamescope FSR/MesaGL)
  gamectl dev-profile <dir> [status|basic|full|off]
                      Inspect or toggle developer profiler (WINEDEBUG/VK_LOADER_DEBUG/GBE log)
  gamectl scan-saves <dir>
                      Discover savegame directories inside a Wine/Proton prefix (read-only)
  gamectl collect-saves <dir>
                      Collect discovered Wine prefix saves into <dir>/saves/_prefix_saves/
  gamectl restore-prefix-saves <dir>
                      Restore staged Wine prefix saves back into <dir>/pfx/drive_c/users/
  gamectl download <appid> [dir] [title] [--source <auto|...>] [--allow-dlc] [--standalone|--sls] [--raw|--inject-only] [--no-lan]
                      Download game via native Valve CDN (default: Pure Standalone zero-client)
  gamectl lan-pull <appid|title> [peer] [--manifest-only] [--target <dir>] [--dry-run]
                      Pull game assets or manifests from a companion LAN peer via SSH/rsync
  gamectl peers [list|add <host>|remove <host>]
                      Manage companion LAN peer hosts (~/.config/gamectl/peers)
  gamectl downloads   Monitor active & recent downloads (Interactive TUI)
  gamectl download-status
                      Display active download tasks across Steam & Standalone engines
  gamectl fetch-manifest <appid> [dest] [source]
                      Harvest manifest archive across Hubcap/Ryuu/Sushi/LuaTools providers
  gamectl auth-status Display current LuaTools authentication session & auto-refresh status
  gamectl login-luatools <code|token|file>
                      Authenticate standalone LuaTools provider (6-char code, refresh token, or json)
  gamectl deploy-manifest <appid> [manifest_zip] [title]
                      Deploy manifest & stplug-in keys into SLSsteam & Steam depotcache
  gamectl entitle <appid> [title]
                      Adopt local assets, Steam Input & shaders via Steam entitlement & ACF (aliases: unlock, adopt-steam)
  gamectl unlock <appid> [title] (Alias for entitle)
  gamectl inject <dir> [appid] [--no-sync|--all]
                      Inject offline LAN runtime & saves; --all explicitly syncs Steam
  gamectl setup-gbe [--yes] [--force] [--linux-only|--win-only] [--dest <dir>]
                      Auto-download & provision Goldberg Emulator templates into ~/.local/share/gbe-fork/
  gamectl setup-runtime [--yes] [--force] [--dry-run] [--source <file|url>] [--dest <dir>]
                      Provision standalone Steam Runtime (Scout) into ~/.local/share/gamectl/runtime/
  gamectl mod-overrides <dir>
                      Setup P2P multiplayer compatibility & mod DLL overrides (alias: onlinefix)
  gamectl onlinefix <dir> (Alias for mod-overrides)
  gamectl fix-check <appid>
                      Query available community, Denuvo, & Online-Fix bypasses (Public)
  gamectl fix-install <appid> [dir] [--type online|generic] [--yes] [--restart]
                      Download, verify, backup, & deploy Online-Fix/bypass directly to game
  gamectl fix-revert <dir|appid> [--dry-run]
                      Safely revert game fix and restore pristine vanilla files from snapshot
  gamectl restart-steam
                      Graceful Steam client hot-reload (SLSsteam & Game Mode supervisor)
  gamectl proton-list List local & latest upstream GE-Proton releases
  gamectl proton-install [tag|latest] Headless GE-Proton installer
  gamectl proton-remove <tag> Safely remove an installed GE-Proton version
  gamectl pfx <dir> [action] [args...] [--dry-run]
                      Wine prefix Swiss Army knife (winecfg/regedit/cmd/shell/kill/clean/winetricks)
  gamectl protondb <appid|dir>
                      Query ProtonDB community rating & launch recommendations
  gamectl make-desktop <dir> [title]
                      Generate FreeDesktop .desktop application shortcut
  gamectl add-to-steam <dir> [title]
                      Register standalone game as non-Steam shortcut in Steam Deck Game Mode
  gamectl fetch-art <dir|appid> [appid]
                      Download official Steam capsule, banner, hero, & logo artwork
  gamectl set-id <player> [steamid] [dir] [--broadcast <ip>] [--global]
                      Configure LAN player name & SteamID for offline co-op
  gamectl fetch-dlc <dir> [appid] Fetch & generate steam_settings/DLC.txt
  gamectl harvest-dlc <appid> [dir]
                      Harvest & unpack multi-depot DLC manifests across CDN providers
  gamectl sync-steam <appid> [title] [dir] Sync Steam Client & SLSsteam entitlements
  gamectl get-resolution Print detected native display resolution
  gamectl get-gamescope-args Print dynamically scaled Gamescope FSR parameters
  gamectl get-steam-root   Print detected active Steam root directory
  gamectl get-steam-libraries Print all detected Steam library folders
  gamectl detect-gpu       Audit and print detected secondary discrete GPU vendor
  gamectl check-scope      Check if cgroups v2 / systemd-run user scope isolation is supported
  gamectl check-sandbox    Check if bubblewrap (bwrap) rootless security sandbox is available
  gamectl search [query]   Search Store catalog (Steam + Multi-Store) & ProtonDB
  gamectl --search         Search Store catalog (interactive TUI prompt)
  gamectl --list      Print detected installed games list
  gamectl list-formatted  Print formatted games list with ANSI badges
  gamectl detect-steamstub <bin>
                      Audit SteamStub (.bind ELF & PE markers) and print forensic diagnostics
  gamectl unpack-stub <bin>
                      Unpack SteamStub DRM binary (Linux ELF .bind or Windows PE)
  gamectl --sync <dir> [title] [host]   Push saves to remote companion host (alias: sync)
  gamectl sync-pull <dir> [title] [host] Pull saves from remote companion host (alias: --sync-pull)
  gamectl backup <dir>        Create manual savegame backup snapshot (alias: --backup)
  gamectl restore <dir> [slot]  Restore savegame snapshot from recovery slot (1-3)
  gamectl logs        View centralized runtime activity logs
  gamectl --help      Show this help documentation
  gamectl --version   Print active version
EOF
}
