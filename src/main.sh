# Minimal subshell exports: previews dispatch via "$GAMECTL_PREVIEW_BIN" --preview*; keep only contract-pinned functions.
export -f pull_save_remote remote_sync_interactive manage_game_fixes_interactive preview_fix_entry

# Top-level Menu
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
case "${1:-}" in
    proton-list|proton)
        proton_list
        ;;
    proton-install)
        proton_install "${2:-latest}" "${@:3}"
        ;;
    proton-remove)
        if [ -n "${2:-}" ]; then
            proton_remove "$2" "${@:3}"
        else
            echo "Usage: gamectl proton-remove <tag> [-y|--yes]"
            exit 1
        fi
        ;;
    setup-gbe|gbe-setup|gbe-install|install-gbe) setup_gbe_templates "${@:2}" ;;
    setup-runtime|runtime-setup|install-runtime) setup_native_runtime "${@:2}" ;;
    mod-overrides|onlinefix|onlinefix-setup)
        if [ -n "${2:-}" ]; then
            setup_onlinefix "$2" "${@:3}"
        else
            echo "Usage: gamectl mod-overrides <game_dir> [--yes|-y] (alias: onlinefix)"
            exit 1
        fi
        ;;
    fix-check|check-fix)
        if [ -n "${2:-}" ]; then
            check_game_fixes "$2" "${@:3}"
        else
            echo "Usage: gamectl fix-check <appid>"
            exit 1
        fi
        ;;
    fix-install|install-fix|apply-fix)
        if [ -n "${2:-}" ]; then
            install_game_fix "$2" "${@:3}"
        else
            echo "Usage: gamectl fix-install <appid> [game_dir] [--type online|generic|voices38|all] [--fix-id <id>] [--yes|-y] [--restart]"
            exit 1
        fi
        ;;
    fix-revert|revert-fix)
        if [ -n "${2:-}" ]; then
            revert_game_fix "$2" "${@:3}"
        else
            echo "Usage: gamectl fix-revert <game_dir|appid> [--dry-run]"
            exit 1
        fi
        ;;
    fix-interactive|fixes|fix-menu)
        manage_game_fixes_interactive "${2:-}" "${3:-}" "${4:-}"
        ;;
    restart-steam|reload-steam)
        restart_steam_client "${@:2}"
        ;;
    detect-overrides|dll-overrides)
        if [ -n "${2:-}" ]; then
            detect_dll_overrides "$2" "${3:-}"
        else
            echo "Usage: gamectl detect-overrides <game_dir> [existing_overrides]"
            exit 1
        fi
        ;;
    pfx|prefix)
        if [ -n "${2:-}" ]; then
            manage_prefix "$2" "${3:-}" "${@:4}"
        else
            echo "Usage: gamectl pfx <game_dir> [winecfg|regedit|cmd|shell|kill|clean|winetricks] [args...]"
            exit 1
        fi
        ;;
    protondb|pdb)
        if [ -n "${2:-}" ]; then
            query_protondb "$2"
        else
            echo "Usage: gamectl protondb <appid|game_dir>"
            exit 1
        fi
        ;;
    make-desktop|desktop-entry)
        if [ -n "${2:-}" ]; then
            create_desktop_entry "$2" "${3:-}"
        else
            echo "Usage: gamectl make-desktop <game_dir> [title]"
            exit 1
        fi
        ;;
    fetch-art|fetch-artwork|get-art)
        if [ -n "${2:-}" ]; then
            fetch_steam_artwork "$2" "${3:-}"
        else
            echo "Usage: gamectl fetch-art <game_dir|appid> [appid]"
            exit 1
        fi
        ;;
    get-steam-grid) get_steam_grid_dir ;;
    add-to-steam|add-steam|shortcut-steam)
        if [ -n "${2:-}" ]; then
            add_steam_shortcut "$2" "${3:-}"
        else
            echo "Usage: gamectl add-to-steam <game_dir> [title]"
            exit 1
        fi
        ;;
    get-steam-shortcuts) get_steam_shortcuts_vdf ;;
    dashboard|menu|--dashboard)
        dashboard_menu
        ;;
    library|list-ui)
        library_menu true
        ;;
    config|config-global|configure)
        if [ "${2:-}" = "set" ] && [ -n "${3:-}" ]; then
            set_config_value "$3" "${4:-}"
            echo "[SUCCESS] Configuration updated: $3=${4:-}"
        elif [ "${2:-}" = "get" ] && [ -n "${3:-}" ]; then
            get_config_value "$3" "${4:-}"
        elif [ "${2:-}" = "list" ] || [ "${2:-}" = "show" ]; then
            if [ -f "$HOME/.config/gamectl/config" ]; then
                cat "$HOME/.config/gamectl/config"
            fi
        else
            configure_global
        fi
        ;;
    doctor|audit)
        doctor_audit
        ;;
    stores|store)
        stores_cli "${2:-status}" "${@:3}"
        ;;
    gog)
        gog_cli "${2:-status}" "${@:3}"
        ;;
    epic)
        epic_cli "${2:-status}" "${@:3}"
        ;;
    amazon)
        amazon_cli "${2:-status}" "${@:3}"
        ;;
    auth)
        auth_hub_cli "${2:-status}" "${@:3}"
        ;;
    search-stores|search_stores)
        store_search_all "${@:2}"
        ;;
    check-scope|systemd-scope)
        if check_systemd_scope_support; then
            echo "[INFO] cgroups v2 / systemd-run user scope isolation is supported and active."
            exit 0
        else
            echo "[WARN] cgroups v2 / systemd-run user scope isolation is not supported on this host."
            exit 1
        fi
        ;;
    detect-gpu|gpu-detect|dgpu)
        vend="$(detect_dgpu_vendor)"
        echo "[INFO] Detected secondary discrete GPU vendor: $vend"
        if [ "$vend" != "none" ]; then
            exit 0
        else
            exit 1
        fi
        ;;
    check-sandbox|sandbox-check)
        if command -v bwrap >/dev/null 2>&1; then
            echo "[INFO] bubblewrap (bwrap) is installed and available for security sandboxing."
            exit 0
        else
            echo "[WARN] bubblewrap (bwrap) is not found in PATH."
            exit 1
        fi
        ;;
    --preview-dashboard)
        preview_dashboard "${2:-1}" "${3:-}"
        ;;
    --preview-search)
        preview_search_game "${2:-}" "${3:-}" "${4:-}"
        ;;
    --preview-download)
        preview_download "${2:-}" "${3:-}" "${4:-}"
        ;;
    --preview-log)
        preview_log_entry "${2:-}"
        ;;
    --preview-process-log)
        preview_process_log "${2:-}" "${3:-}"
        ;;
    --preview-adopt)
        preview_adopt_candidate "${2:-}" "${3:-}"
        ;;
    --preview-fix)
        preview_fix_entry "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}"
        ;;
    --tui-library-sync)
        tui_library_sync_actions "${2:-ALL}"
        ;;
    set-id)
        if [ -n "${2:-}" ]; then
            set_id "${@:2}"
        else
            echo "Usage: gamectl set-id <player_name> [steamid] [game_dir] [--broadcast <ip>] [--global]"
            exit 1
        fi
        ;;
    generate-steamid)
        generate_steamid64
        ;;
    get-gamescope-args)
        get_default_gamescope_args
        ;;
    get-resolution)
        get_native_resolution
        ;;
    get-steam-root)
        get_steam_root
        ;;
    get-steam-libraries|steam-libs)
        get_steam_libraries
        ;;
    get-wineserver)
        get_wineserver_bin "${2:-}"
        ;;
    resolve-library|get-target-library)
        resolve_target_library_dir "${2:-game}"
        ;;
    resolve-standalone-library)
        resolve_standalone_library_dir "${2:-}" "${3:-}"
        ;;
    detect-steamstub|steamstub|check-stub)
        if [ -n "${2:-}" ]; then
            diagnose_steamstub "$2"
        else
            echo "Usage: gamectl detect-steamstub <binary>"
            exit 2
        fi
        ;;
    unpack-stub|unpack|steamless)
        if [ -n "${2:-}" ]; then
            cli_unpack_stub "$2"
        else
            echo "Usage: gamectl unpack-stub <binary>"
            exit 2
        fi
        ;;
    detect-os)
        detect_app_platform_os "${2:-}"
        ;;
    check-steam|check-steam-active)
        check_steam_active "${2:-Manual check}"
        ;;
    cache-json|fetch-cached-json)
        fetch_cached_json "${2:-}" "${3:-}" "${4:-3600}"
        ;;
    set-id-interactive)
        if [ -n "${2:-}" ]; then
            set_id_interactive "$2" "${3:-}"
        else
            echo "Usage: gamectl set-id-interactive <game_dir> [title]"
            exit 1
        fi
        ;;
    launch|run|--launch)
        if [ -n "${2:-}" ]; then
            cli_launch "${@:2}"
        else
            echo "Usage: gamectl launch <game_dir> [binary] [title] [--hud] [--gamemode] [--gamescope] [--fsr]"
            exit 1
        fi
        ;;
    configure-wrappers)
        if [ -n "${2:-}" ]; then
            configure_wrappers "$2" "${3:-}"
        else
            echo "Usage: gamectl configure-wrappers <game_dir> [title]"
            exit 1
        fi
        ;;
    dev-profile)
        if [ -n "${2:-}" ]; then
            configure_dev_profile "$2" "${3:-status}"
        else
            echo "Usage: gamectl dev-profile <game_dir> [status|basic|full|off]" >&2
            exit 1
        fi
        ;;
    scan-saves|discover-saves)
        if [ -n "${2:-}" ]; then
            discover_prefix_saves "$2"
        else
            echo "Usage: gamectl scan-saves <game_dir>" >&2
            exit 1
        fi
        ;;
    collect-saves)
        if [ -n "${2:-}" ]; then
            collect_prefix_saves "$2"
        else
            echo "Usage: gamectl collect-saves <game_dir>" >&2
            exit 1
        fi
        ;;
    restore-prefix-saves)
        if [ -n "${2:-}" ]; then
            restore_prefix_saves "$2"
        else
            echo "Usage: gamectl restore-prefix-saves <game_dir>" >&2
            exit 1
        fi
        ;;
    inject|--inject)
        if [ -n "${2:-}" ]; then
            inject_game "$2" "${3:-}" "${4:---no-sync}"
        else
            echo "Usage: gamectl inject <game_dir> [appid] [--no-sync|--all]"
            exit 1
        fi
        ;;
    fetch-dlc|--fetch-dlc)
        if [ -n "${2:-}" ]; then
            fetch_dlc "$2" "${3:-}"
        else
            echo "Usage: gamectl fetch-dlc <game_dir> [appid]"
            exit 1
        fi
        ;;
    download|--download)
        if [ -n "${2:-}" ]; then
            download_game "$2" "${@:3}"
        else
            echo "Usage: gamectl download <appid> [dir] [title] [--source <auto|...>] [--os <linux|windows|macos|all>] [--raw|--inject-only|--all|--standalone|--sls]"
            exit 1
        fi
        ;;
    unlock|entitle|adopt-steam|--unlock|--entitle)
        if [ -n "${2:-}" ]; then
            unlock_game "$2" "${3:-}"
        else
            if [ -t 0 ]; then
                unlock_interactive
            else
                echo "Usage: gamectl entitle <appid> [title] (aliases: unlock, adopt-steam)"
                exit 1
            fi
        fi
        ;;
    processes|running|hud|ps)
        if [ ! -t 0 ] || [ ! -t 1 ]; then
            run_dir="$(get_runtime_dir)"
            if [ -d "$run_dir/active_games" ]; then
                for inf in "$run_dir/active_games"/*.info; do
                    [ -f "$inf" ] || continue
                    a_pid=$(grep -E '^PID=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
                    a_title=$(grep -E '^TITLE=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
                    a_dir=$(grep -E '^DIR=' "$inf" 2>/dev/null | head -n 1 | cut -d'=' -f2-)
                    if [ -n "$a_pid" ] && is_pid_running "$a_pid"; then
                        printf "%s\t%s\t%s\n" "$a_pid" "$a_title" "$a_dir"
                    fi
                done
            fi
        else
            enter_tui_screen
            manage_active_processes_interactive
            exit_tui_screen
        fi
        ;;
    downloads|--downloads|download-status|--download-status)
        if [ "${1:-}" = "download-status" ] || [ "${1:-}" = "--download-status" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
            list_downloads
        else
            enter_tui_screen
            list_downloads_interactive
            exit_tui_screen
        fi
        ;;
    sync-steam|--sync-steam)
        if [ -n "${2:-}" ]; then
            sync_steam "$2" "${3:-}" "${4:-}"
        else
            echo "Usage: gamectl sync-steam <appid> [title] [game_dir]"
            exit 1
        fi
        ;;
    deploy-manifest|deploy-sls)
        if [ -n "${2:-}" ]; then
            deploy_sls_manifest "$2" "${3:-}" "${4:-}"
        else
            echo "Usage: gamectl deploy-manifest <appid> [manifest_zip] [title]"
            exit 1
        fi
        ;;
    fetch-manifest|manifest)
        if [ -n "${2:-}" ]; then
            fetch_manifest "$2" "${3:-}" "${4:-auto}"
        else
            echo "Usage: gamectl fetch-manifest <appid> [dest_file] [source]"
            exit 1
        fi
        ;;
    harvest-dlc|dlc-manifests|fetch-dlc-manifests)
        if [ -n "${2:-}" ]; then
            harvest_dlc_manifests "$2" "${3:-.}" "${4:-auto}"
        else
            echo "Usage: gamectl harvest-dlc <appid> [stage_dir] [source]"
            exit 1
        fi
        ;;
    login-luatools|auth-luatools)
        if [ -n "${2:-}" ]; then
            login_luatools "${2:-}"
        else
            if [ -t 0 ] && [ -t 1 ]; then
                login_luatools_interactive
            else
                login_luatools ""
            fi
        fi
        ;;
    auth-status|luatools-status)
        luatools_status
        ;;
    ensure-downloader)
        ensure_downloader
        ;;
    --preview)
        preview_game "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        ;;
    --backup|backup|backup-save)
        if [ -n "${2:-}" ]; then
            backup_save "$2" || exit $?
        else
            echo "Usage: gamectl backup <game_dir>"
            exit 1
        fi
        ;;
    --restore|restore|restore-save)
        if [ -n "${2:-}" ]; then
            restore_save "$2" "${3:-1}" || exit $?
        else
            echo "Usage: gamectl restore <game_dir> [slot_num]"
            exit 1
        fi
        ;;
    search|--search)
        is_standalone=true
        q_arg="${2:-}"
        if [ "$q_arg" = "--no-dashboard" ]; then
            q_arg=""
            is_standalone=false
        elif [ "${3:-}" = "--no-dashboard" ]; then
            is_standalone=false
        fi
        search_steam "$q_arg" "$is_standalone"
        ;;
    logs|--logs)
        enter_tui_screen
        log_rc=0
        view_logs_interactive || log_rc=$?
        exit_tui_screen
        [ "$log_rc" -ne 0 ] && exit "$log_rc"
        ;;
    --sync|sync|sync-remote|sync-companion|sync-tuf)
        if [ -n "${2:-}" ]; then
            sync_save_remote "${@:2}"
        else
            echo "Usage: gamectl --sync <game_dir> [title] [remote_host] [--dry-run]"
            exit 1
        fi
        ;;
    --sync-pull|sync-pull|pull-remote|pull-companion|pull-tuf)
        if [ -n "${2:-}" ]; then
            pull_save_remote "${@:2}"
        else
            echo "Usage: gamectl sync-pull <game_dir> [title] [remote_host] [--dry-run]"
            exit 1
        fi
        ;;
    --list|list)
        scan_installed_games "${@:2}"
        ;;
    list-formatted|--list-formatted)
        scan_installed_games --formatted "${@:2}"
        ;;
    --version|-v)
        echo "gamectl v1.5.0 (sovereign native TUI)"
        ;;
    --help|-h)
        cat <<EOF
gamectl - Sovereign TUI Game Manager & Launcher (Zero-Bloat)

Usage:
  gamectl [menu]      Open Master Dashboard Hub TUI (alias: dashboard)
  gamectl library     Open Game Library TUI directly (alias: list-ui)
  gamectl config [set <k> <v>|get <k>|list]
                      Open global configuration menu or read/write settings (~/.config/gamectl/config)
  gamectl doctor      Run 8-layer system & GPU health diagnostics (alias: audit)
  gamectl stores [list|status]
                      Inspect registered store adapters and offline readiness
  gamectl gog <status|auth|search|download|sync> [args...]
                      Optional DRM-free GOG adapter (delegates to gogdl / lgogdownloader)
  gamectl epic <status|auth|search|download|sync|launch> [args...]
                      Optional Epic Games adapter (delegates to legendary)
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
  gamectl download <appid> [dir] [title] [--source <auto|...>] [--allow-dlc] [--standalone|--sls] [--raw|--inject-only]
                      Download game via native Valve CDN (default: Pure Standalone zero-client)
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
  gamectl search [query]   Search Steam Store catalog & audit ProtonDB rating
  gamectl --search         Search Steam Store catalog (interactive TUI prompt)
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
        ;;
    *)
        dashboard_menu
        ;;
esac
fi
