# Export functions for subshells in fzf
export -f get_runtime_dir strip_ansi preview_game sync_save_remote sync_to_companion sync_to_tuf pull_save_remote pull_from_companion pull_from_tuf backup_save restore_save inject_game fetch_dlc setup_gbe_templates download_game ensure_downloader resolve_depot_dl_bin resolve_target_library_dir resolve_standalone_library_dir detect_steamstub_drm detect_steamstub_type resolve_unpacked_binary find_steamless_cli unpack_steamstub_pe setup_steam_interceptor diagnose_steamstub cli_unpack_stub harvest_dlc_manifests detect_app_platform_os sync_steam list_downloads list_downloads_interactive unlock_game unlock_interactive entitle_game entitle_interactive adopt_steam get_remote_host get_gbe_template find_game_binary find_runner get_wineserver_bin launch_game game_controller_hud is_haswell_gpu get_native_resolution get_default_gamescope_args get_steam_root get_steam_primary_apps get_steam_libraries build_wrapper_command configure_wrappers configure_global doctor_audit cli_launch generate_steamid64 resolve_active_steamid get_game_persona set_id set_id_interactive preview_dashboard dashboard_menu scan_installed_games detect_dll_overrides setup_onlinefix proton_list proton_install proton_remove manage_prefix query_protondb create_desktop_entry get_steam_grid_dir fetch_steam_artwork get_steam_shortcuts_vdf add_steam_shortcut check_steam_active fetch_cached_json check_systemd_scope_support detect_dgpu_vendor build_sandbox_command manifest_has_payload_magic validate_manifest_zip fetch_manifest get_sls_root get_sls_manifests_dir get_steam_stplug_in_dir get_steam_depotcache_dir deploy_sls_manifest trigger_steam_install find_app_acf format_bytes parse_acf_download_state check_game_fixes resolve_game_install_dir audit_proton_compatibility detect_fix_custom_launcher install_game_fix revert_game_fix restart_steam_client clean_stale_locks get_compat_dir get_valid_luatools_token is_valid_lua_manifest library_menu login_luatools luatools_status search_steam invalidate_scan_cache flush_tty_input enter_tui_screen exit_tui_screen tui_modal_notice get_runtime_log_file log_msg log_info log_warn log_error view_logs_interactive preview_search_game preview_download get_depot_dl_progress preview_log_entry preview_process_log preview_adopt_candidate

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
    setup-gbe|gbe-setup|gbe-install|install-gbe)
        setup_gbe_templates "${@:2}"
        ;;
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
            echo "Usage: gamectl unpack-stub <binary.exe>"
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
            echo "Usage: gamectl download <appid> [dir] [title] [--source <auto|...>] [--raw|--inject-only|--all|--standalone|--sls]"
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
        login_luatools "${2:-}"
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
            backup_save "$2"
        else
            echo "Usage: gamectl backup <game_dir>"
            exit 1
        fi
        ;;
    --restore|restore|restore-save)
        if [ -n "${2:-}" ]; then
            restore_save "$2" "${3:-1}"
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
        view_logs_interactive
        exit_tui_screen
        ;;
    --sync|sync|sync-remote|sync-companion|sync-tuf)
        if [ -n "${2:-}" ]; then
            sync_save_remote "$2" "${3:-Game}" "${4:-}" "${@:5}"
        else
            echo "Usage: gamectl --sync <game_dir> [title] [remote_host] [--dry-run]"
            exit 1
        fi
        ;;
    --sync-pull|sync-pull|pull-remote|pull-companion|pull-tuf)
        if [ -n "${2:-}" ]; then
            pull_save_remote "$2" "${3:-Game}" "${4:-}" "${@:5}"
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
        echo "gamectl v1.4.0 (sovereign native TUI)"
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
  gamectl download <appid> [dir] [title] [--source <auto|...>] [--standalone|--sls] [--raw|--inject-only]
                      Download game via native Valve CDN (default: Pure Standalone zero-client)
  gamectl downloads   Monitor active & recent downloads (Interactive TUI)
  gamectl download-status
                      Display active download tasks across Steam & Standalone engines
  gamectl fetch-manifest <appid> [dest] [source]
                      Harvest manifest archive across Ryuu/Sushi/LuaTools providers
  gamectl auth-status Display current LuaTools authentication session & auto-refresh status
  gamectl login-luatools <code|token|file>
                      Authenticate standalone LuaTools provider (6-char code, refresh token, or json)
  gamectl deploy-manifest <appid> [manifest_zip] [title]
                      Deploy manifest & stplug-in keys into SLSsteam & Steam depotcache
  gamectl entitle <appid> [title]
                      Adopt local assets, Steam Input & shaders via Steam entitlement & ACF (aliases: unlock, adopt-steam)
  gamectl unlock <appid> [title] (Alias for entitle)
  gamectl inject <dir> [appid] [--no-sync|--all]
                      Inject decentralized LAN runtime & portable saves
  gamectl setup-gbe [--yes] [--force] [--linux-only|--win-only] [--dest <dir>]
                      Auto-download & provision Goldberg Emulator templates into ~/.local/share/gbe-fork/
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
  gamectl unpack-stub <bin.exe>
                      Unpack Windows PE SteamStub DRM binary via Steamless CLI
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
