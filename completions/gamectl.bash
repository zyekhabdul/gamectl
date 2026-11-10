# ==============================================================================
# gamectl & game - Bash Completion Script
# ==============================================================================

_gamectl_completions() {
    local cur prev words cword
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion || return
    else
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi

    local commands="menu dashboard library list-ui config configure doctor audit launch run configure-wrappers set-id set-id-interactive generate-steamid get-gamescope-args get-resolution get-steam-root get-steam-libraries steam-libs download downloads entitle adopt-steam unlock inject fetch-dlc sync-steam ensure-downloader detect-gpu check-scope check-sandbox list list-formatted search logs fix-check check-fix fix-install install-fix apply-fix fix-revert revert-fix restart-steam reload-steam fetch-manifest manifest deploy-manifest deploy-sls harvest-dlc dlc-manifests fetch-dlc-manifests login-luatools auth-luatools auth-status luatools-status detect-steamstub steamstub check-stub unpack-stub unpack steamless setup-gbe gbe-setup gbe-install install-gbe backup backup-save restore restore-save sync sync-remote sync-companion sync-tuf sync-pull pull-remote pull-companion pull-tuf mod-overrides onlinefix onlinefix-setup detect-overrides dll-overrides proton-list proton-install proton-remove pfx prefix protondb pdb make-desktop desktop-entry fetch-art fetch-artwork get-art get-steam-grid add-to-steam add-steam get-steam-shortcuts --help --version -h -v --list --list-formatted --search --logs --sync --sync-pull --backup --restore --download --downloads --inject --fetch-dlc --sync-steam --dashboard --preview --preview-dashboard --preview-search"
    local download_opts="--raw --inject-only --all --foreground -f --standalone --sls --source"
    local inject_opts="--all --no-sync"
    local launch_opts="--hud --no-hud --mangohud --no-mangohud --gamemode --no-gamemode --gamescope --no-gamescope --fsr --no-fsr --glthread --no-glthread --scope --no-scope --prime --no-prime --sandbox --no-sandbox"
    local set_id_opts="--broadcast --global"

    _complete_path() {
        if declare -F _filedir >/dev/null 2>&1; then
            _filedir -d 2>/dev/null || _filedir
        else
            local matches=()
            mapfile -t matches < <(compgen -d -- "$cur")
            if [ ${#matches[@]} -eq 0 ]; then
                mapfile -t matches < <(compgen -f -- "$cur")
            fi
            COMPREPLY=("${matches[@]}")
        fi
    }

    # Complete top-level subcommands
    if [ "$cword" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    # Subcommand-specific completions
    local subcmd="${words[1]}"
    case "$subcmd" in
        launch|run|--launch)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$launch_opts" -- "$cur") )
            else
                _complete_path
            fi
            return 0
            ;;
        configure-wrappers|set-id-interactive|backup|backup-save|--backup|fetch-art|fetch-artwork|get-art|make-desktop|desktop-entry|add-to-steam|add-steam|shortcut-steam|mod-overrides|onlinefix|onlinefix-setup|detect-overrides|dll-overrides)
            _complete_path
            return 0
            ;;
        detect-steamstub|steamstub|check-stub|unpack-stub|unpack|steamless)
            _complete_path
            return 0
            ;;
        restore|restore-save|--restore)
            if [ "$cword" -eq 2 ]; then
                _complete_path
            elif [ "$cword" -eq 3 ]; then
                COMPREPLY=( $(compgen -W "1 2 3" -- "$cur") )
            fi
            return 0
            ;;
        sync|--sync|sync-remote|sync-companion|sync-tuf|sync-pull|--sync-pull|pull-remote|pull-companion|pull-tuf)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--dry-run -n" -- "$cur") )
            else
                _complete_path
            fi
            return 0
            ;;
        pfx|prefix)
            if [ "$cword" -eq 2 ]; then
                _complete_path
            elif [ "$cword" -eq 3 ]; then
                COMPREPLY=( $(compgen -W "winecfg regedit cmd shell kill clean winetricks" -- "$cur") )
            elif [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--dry-run -n" -- "$cur") )
            fi
            return 0
            ;;
        fix-revert|revert-fix)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--dry-run -n" -- "$cur") )
            else
                _complete_path
            fi
            return 0
            ;;
        fix-install|install-fix|apply-fix)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--type --fix-id --yes -y --restart" -- "$cur") )
            elif [ "$prev" = "--type" ]; then
                COMPREPLY=( $(compgen -W "online generic voices38 all" -- "$cur") )
            elif [ "$cword" -eq 3 ]; then
                _complete_path
            fi
            return 0
            ;;
        setup-gbe|gbe-setup|gbe-install|install-gbe)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--yes -y --force -f --linux-only --win-only --dest" -- "$cur") )
            fi
            return 0
            ;;
        fetch-manifest|manifest|harvest-dlc|dlc-manifests|fetch-dlc-manifests)
            if [ "$prev" = "--source" ] || [ "$cword" -eq 4 ]; then
                COMPREPLY=( $(compgen -W "auto ryuu sushi luatools" -- "$cur") )
            elif [ "$cword" -eq 3 ]; then
                _complete_path
            fi
            return 0
            ;;
        set-id)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$set_id_opts" -- "$cur") )
            elif [ "$cword" -eq 3 ] && [[ "$cur" == a* || "$cur" == r* ]]; then
                COMPREPLY=( $(compgen -W "auto random" -- "$cur") )
            else
                _complete_path
            fi
            return 0
            ;;
        download|--download)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$download_opts" -- "$cur") )
            elif [ "$prev" = "--source" ]; then
                COMPREPLY=( $(compgen -W "auto ryuu sushi luatools" -- "$cur") )
            elif [ "$cword" -eq 3 ]; then
                _complete_path
            fi
            return 0
            ;;
        inject|--inject)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$inject_opts" -- "$cur") )
            else
                _complete_path
            fi
            return 0
            ;;
        fetch-dlc|--fetch-dlc)
            _complete_path
            return 0
            ;;
        sync-steam|--sync-steam)
            if [ "$cword" -eq 4 ]; then
                _complete_path
            fi
            return 0
            ;;
        proton-remove)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--yes -y" -- "$cur") )
            fi
            return 0
            ;;
        *)
            ;;
    esac
}

complete -F _gamectl_completions gamectl
complete -F _gamectl_completions game
