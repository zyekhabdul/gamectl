# Export functions for subshells in fzf
export -f preview_game sync_save_remote sync_to_companion sync_to_tuf backup_save inject_game fetch_dlc download_game ensure_downloader sync_steam list_downloads list_downloads_interactive unlock_game unlock_interactive get_remote_host get_gbe_template find_game_binary find_runner launch_game game_controller_hud is_haswell_gpu get_native_resolution get_default_gamescope_args get_steam_root get_steam_primary_apps get_steam_libraries build_wrapper_command configure_wrappers configure_global doctor_audit cli_launch generate_steamid64 resolve_active_steamid get_game_persona set_id set_id_interactive preview_dashboard dashboard_menu scan_installed_games

# Top-level Menu
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
case "${1:-}" in
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
            echo "Usage: gamectl download <appid> [dir] [title] [--raw|--inject-only|--all] [--foreground|-f]"
            exit 1
        fi
        ;;
    unlock|add-steam|--unlock)
        if [ -n "${2:-}" ]; then
            unlock_game "$2" "${3:-}"
        else
            if [ -t 0 ]; then
                unlock_interactive
            else
                echo "Usage: gamectl unlock <appid> [title]"
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
        echo "gamectl v1.2.0 (sovereign native TUI)"
        ;;
    --help|-h)
        cat <<EOF
gamectl - Sovereign TUI Game Manager & Launcher (Zero-Bloat)

Usage:
  gamectl [menu]      Open Master Dashboard Hub TUI (alias: dashboard)
  gamectl library     Open Game Library TUI directly (alias: list-ui)
  gamectl config      Open global configuration menu (~/.config/gamectl/) (alias: configure)
  gamectl doctor      Run 7-layer system & GPU health diagnostics (alias: audit)
  gamectl launch <dir> [bin] [title] [--hud] [--gamemode] [--gamescope] [--fsr] [--glthread]
                      Launch game with isolated prefix and runtime wrapper options
  gamectl configure-wrappers <dir> [title]
                      Configure per-game wrappers (GameMode/MangoHud/Gamescope FSR/MesaGL)
  gamectl download <appid> [dir] [title] [--raw|--inject-only|--all] [-f]
                      Headless game downloader via DepotDownloader
  gamectl downloads   Monitor active & recent download processes
  gamectl unlock <appid> [title]
                      Zero-download Steam Client & SLSsteam Full DLC entitlement
  gamectl inject <dir> [appid] [--no-sync|--all]
                      Inject GBE Fork standalone & portable saves
  gamectl set-id <player> [steamid] [dir] [--broadcast <ip>] [--global]
                      Configure LAN player name & SteamID for offline co-op
  gamectl fetch-dlc <dir> [appid] Fetch & generate steam_settings/DLC.txt
  gamectl sync-steam <appid> [title] [dir] Sync Steam Client & SLSsteam entitlements
  gamectl get-resolution Print detected native display resolution
  gamectl get-gamescope-args Print dynamically scaled Gamescope FSR parameters
  gamectl get-steam-root   Print detected active Steam root directory
  gamectl get-steam-libraries Print all detected Steam library folders
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
