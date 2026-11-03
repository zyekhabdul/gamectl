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

    local commands="download downloads unlock inject fetch-dlc sync-steam ensure-downloader --search --list --sync --backup --help --version -h -v"
    local download_opts="--raw --inject-only --all --foreground -f"
    local inject_opts="--all --no-sync"

    # Complete top-level subcommands
    if [ "$cword" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    # Subcommand-specific completions
    local subcmd="${words[1]}"
    case "$subcmd" in
        download|--download)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$download_opts" -- "$cur") )
            elif declare -F _filedir >/dev/null 2>&1; then
                _filedir -d 2>/dev/null || _filedir
            fi
            return 0
            ;;
        inject|--inject)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$inject_opts" -- "$cur") )
            elif declare -F _filedir >/dev/null 2>&1; then
                _filedir -d 2>/dev/null || _filedir
            fi
            return 0
            ;;
        fetch-dlc|--fetch-dlc|--sync|--backup)
            if declare -F _filedir >/dev/null 2>&1; then
                _filedir -d 2>/dev/null || _filedir
            fi
            return 0
            ;;
        sync-steam|--sync-steam)
            if [ "$cword" -eq 4 ] && declare -F _filedir >/dev/null 2>&1; then
                _filedir -d 2>/dev/null || _filedir
            fi
            return 0
            ;;
        *)
            ;;
    esac
}

complete -F _gamectl_completions gamectl
complete -F _gamectl_completions game
