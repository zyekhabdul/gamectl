# Export functions for subshells in fzf
export -f preview_game sync_save_remote sync_to_companion sync_to_tuf backup_save inject_game fetch_dlc download_game ensure_downloader resolve_target_library_dir detect_app_platform_os sync_steam list_downloads list_downloads_interactive unlock_game unlock_interactive entitle_game entitle_interactive adopt_steam get_remote_host get_gbe_template find_game_binary find_runner get_wineserver_bin launch_game game_controller_hud is_haswell_gpu get_native_resolution get_default_gamescope_args get_steam_root get_steam_primary_apps get_steam_libraries build_wrapper_command configure_wrappers configure_global doctor_audit cli_launch generate_steamid64 resolve_active_steamid get_game_persona set_id set_id_interactive preview_dashboard dashboard_menu scan_installed_games detect_dll_overrides setup_onlinefix proton_list proton_install proton_remove manage_prefix query_protondb create_desktop_entry get_steam_grid_dir fetch_steam_artwork get_steam_shortcuts_vdf add_steam_shortcut check_steam_active fetch_cached_json check_systemd_scope_support detect_dgpu_vendor build_sandbox_command manifest_has_payload_magic validate_manifest_zip fetch_manifest get_sls_root get_sls_manifests_dir get_steam_stplug_in_dir get_steam_depotcache_dir deploy_sls_manifest

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
    mod-overrides|onlinefix|onlinefix-setup)
        if [ -n "${2:-}" ]; then
            setup_onlinefix "$2" "${@:3}"
        else
            echo "Usage: gamectl mod-overrides <game_dir> [--yes|-y] (alias: onlinefix)"
            exit 1
        fi
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
    get-steam-grid)
        get_steam_grid_dir
        ;;
    add-to-steam|add-steam|shortcut-steam)
        if [ -n "${2:-}" ]; then
            add_steam_shortcut "$2" "${3:-}"
        else
            echo "Usage: gamectl add-to-steam <game_dir> [title]"
            exit 1
        fi
        ;;
    get-steam-shortcuts)
        get_steam_shortcuts_vdf
        ;;
    dashboard|menu|--dashboard)
        dashboard_menu
        ;;
    library|list-ui)
        library_menu true
        ;;
    config|config-global|configure)
        configure_global
        ;;
    doctor|audit)
        doctor_audit
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
    inject|--inject)
        if [ -n "${2:-}" ]; then
            inject_game "$2" "${3:-}" "${4:-all}"
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
            echo "Usage: gamectl download <appid> [dir] [title] [--raw|--inject-only|--all] [--foreground|-f] [--os <linux|windows|all>]"
            exit 1
        fi
        ;;
    unlock|add-steam|entitle|adopt-steam|--unlock|--entitle)
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
    downloads|--downloads)
        if [ -t 0 ]; then
            list_downloads_interactive
        else
            list_downloads
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
    ensure-downloader)
        ensure_downloader
        ;;
    --preview)
        preview_game "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        ;;
    --backup)
        if [ -n "${2:-}" ]; then
            backup_save "$2"
        fi
        ;;
    --search)
        search_steam
        ;;
    --sync|sync|sync-remote|sync-companion|sync-tuf)
        if [ -n "${2:-}" ]; then
            sync_save_remote "$2" "${3:-Game}" "${4:-}"
        else
            echo "Usage: gamectl --sync <game_dir> [title] [remote_host]"
        fi
        ;;
    --list)
        scan_installed_games
        ;;
    list-formatted|--list-formatted)
        scan_installed_games --formatted
        ;;
    --version|-v)
        echo "gamectl v1.2.1 (sovereign native TUI)"
        ;;
    --help|-h)
        cat <<EOF
gamectl - Sovereign TUI Game Manager & Launcher (Zero-Bloat)

Usage:
  gamectl [menu]      Open Master Dashboard Hub TUI (alias: dashboard)
  gamectl library     Open Game Library TUI directly (alias: list-ui)
  gamectl config      Open global configuration menu (~/.config/gamectl/) (alias: configure)
  gamectl doctor      Run 7-layer system & GPU health diagnostics (alias: audit)
  gamectl launch <dir> [bin] [title] [--hud] [--gamemode] [--gamescope] [--fsr] [--glthread] [--scope|--no-scope] [--prime|--no-prime] [--sandbox|--no-sandbox]
                      Launch game with isolated prefix and runtime wrapper options
  gamectl configure-wrappers <dir> [title]
                      Configure per-game wrappers (GameMode/MangoHud/Gamescope FSR/MesaGL)
  gamectl download <appid> [dir] [title] [--raw|--inject-only|--all] [-f] [--os <linux|windows|all>]
                      Headless game downloader via DepotDownloader
  gamectl downloads   Monitor active & recent download processes
  gamectl entitle <appid> [title]
                      Adopt local assets, Steam Input & shaders via Steam entitlement & ACF (aliases: unlock, adopt-steam)
  gamectl unlock <appid> [title] (Alias for entitle)
  gamectl inject <dir> [appid] [--no-sync|--all]
                      Inject decentralized LAN runtime & portable saves
  gamectl mod-overrides <dir>
                      Setup P2P multiplayer compatibility & mod DLL overrides (alias: onlinefix)
  gamectl onlinefix <dir> (Alias for mod-overrides)
  gamectl proton-list List local & latest upstream GE-Proton releases
  gamectl proton-install [tag|latest] Headless GE-Proton installer
  gamectl proton-remove <tag> Safely remove an installed GE-Proton version
  gamectl pfx <dir> [action] [args...]
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
  gamectl sync-steam <appid> [title] [dir] Sync Steam Client & SLSsteam entitlements
  gamectl get-resolution Print detected native display resolution
  gamectl get-gamescope-args Print dynamically scaled Gamescope FSR parameters
  gamectl get-steam-root   Print detected active Steam root directory
  gamectl get-steam-libraries Print all detected Steam library folders
  gamectl detect-gpu       Audit and print detected secondary discrete GPU vendor
  gamectl check-scope      Check if cgroups v2 / systemd-run user scope isolation is supported
  gamectl check-sandbox    Check if bubblewrap (bwrap) rootless security sandbox is available
  gamectl --search    Search Steam Store catalog & audit ProtonDB rating
  gamectl --list      Print detected installed games list
  gamectl list-formatted  Print formatted games list with ANSI badges
  gamectl --sync <dir> [title] [host]  Sync saves to remote companion host
  gamectl --backup <dir>        Create manual savegame backup snapshot
  gamectl --help      Show this help documentation
  gamectl --version   Print active version
EOF
        ;;
    *)
        dashboard_menu
        ;;
esac
fi
