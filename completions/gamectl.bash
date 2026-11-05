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

    local commands="menu dashboard library list-ui config configure doctor audit launch run configure-wrappers set-id set-id-interactive generate-steamid get-gamescope-args get-resolution get-steam-root get-steam-libraries steam-libs download downloads unlock inject fetch-dlc sync-steam ensure-downloader list-formatted --list-formatted --search --list --sync sync sync-companion --backup mod-overrides onlinefix proton-list proton-install proton-remove pfx prefix protondb pdb make-desktop fetch-art fetch-artwork get-steam-grid --help --version -h -v"
    local download_opts="--raw --inject-only --all --foreground -f"
    local inject_opts="--all --no-sync"
    local launch_opts="--hud --no-hud --mangohud --no-mangohud --gamemode --no-gamemode --gamescope --no-gamescope --fsr --no-fsr --glthread --no-glthread"
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
        configure-wrappers|set-id-interactive)
            _complete_path
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
            else
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
        fetch-dlc|--fetch-dlc|--sync|--backup)
            _complete_path
            return 0
            ;;
        sync-steam|--sync-steam)
            if [ "$cword" -eq 4 ]; then
                _complete_path
            fi
            return 0
            ;;
        *)
            ;;
    esac
}

complete -F _gamectl_completions gamectl
complete -F _gamectl_completions game
