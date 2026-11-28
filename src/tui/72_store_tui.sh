# ==============================================================================
# Multi-Store TUI Views & Cross-Store Search Switcher (Split from 70_dashboard.sh)
# ==============================================================================

# Interactive Cross-Store Search & Download Switcher
search_stores_interactive() {
    local query="${1:-}" target_store="${2:-all}"
    [ -t 0 ] && [ -t 1 ] && command -v fzf >/dev/null 2>&1 || return 1
    if [ -z "$query" ]; then
        query=$(tui_prompt_input "gamectl :: Cross-Store Search" "Search across Steam, GOG, Epic & Amazon" "" "Search All > ") || return 0
        query=$(echo "$query" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$query" ] || return 0
    fi
    local raw_rows="" rows="" r_store r_id r_title r_plats r_status r_type r_parent
    raw_rows=$(store_search_all "$query" --store "$target_store" 2>/dev/null || true)
    if [ -z "$raw_rows" ]; then
        tui_modal_notice "Cross-Store Search" "No matches found across available stores for '$query'." || return $?
        return 0
    fi
    while IFS=$'\t' read -r r_store r_id r_title r_plats r_status r_type r_parent; do
        [ -n "$r_store" ] && [ -n "$r_id" ] || continue
        local badge; badge="$(format_app_type_badge "${r_type:-APP}")"
        rows+="${r_store}"$'\t'"${r_id}"$'\t'"${badge}"$'\t'"${r_title}"$'\t'"${r_plats}"$'\t'"${r_status}"$'\t'"${r_type}"$'\t'"${r_parent}"$'\n'
    done <<< "$raw_rows"

    export GAMECTL_PREVIEW_BIN="$SELF_BIN"
    local pick p_rc=0
    pick=$(printf '%s' "$rows" | fzf --delimiter=$'\t' --with-nth=1,2,3,4,5,6 \
        --border-label="  ╢ gamectl :: Cross-Store Catalog ($target_store) ╟  " --border-label-pos=2 \
        --header="Enter: Download via Store Adapter │ Esc: Return" --prompt="Cross-Store > " \
        --preview='"$GAMECTL_PREVIEW_BIN" --preview-search {2} {4} {6} {1}' \
        --preview-window=right:52%:border-rounded:wrap) || p_rc=$?
    [ "$p_rc" -eq 130 ] && return 0
    [ "$p_rc" -ne 0 ] && [ "$p_rc" -ne 1 ] && return "$p_rc"
    [ -n "$pick" ] || return 0

    IFS=$'\t' read -r r_store r_id _ r_title _ _ r_type r_parent <<< "$pick"
    local dest_dir; dest_dir="$(resolve_target_library_dir "$r_title")"
    if [ "$r_store" = "STEAM" ]; then
        local target_os; target_os="$(detect_app_platform_os "$r_id")"
        tui_exec_action "Steam Download ($r_title)" download_game "$r_id" "$dest_dir" "$r_title" --all --os "$target_os"
    else
        tui_exec_action "$r_store Download ($r_title)" store_dispatch "${r_store,,}" download "$r_id" "$dest_dir"
    fi
}

# Single SSoT for Game Library border label & header chrome (initial draw & live fzf transform)
_format_library_chrome() {
    local store_filter="${1:-ALL}"
    local explicit_banner="${2:-}"
    case "$store_filter" in
        ALL|STEAM|GOG|EPIC|AMAZON|STANDALONE) ;;
        *) store_filter="ALL" ;;
    esac

    local active_summary active_cnt=0 active_names="" sep=$'\x1f'
    active_summary=$(get_active_games_summary)
    IFS="$sep" read -r active_cnt active_names <<< "$active_summary"
    [[ "${active_cnt:-0}" =~ ^[0-9]+$ ]] || active_cnt=0

    GAMECTL_LIB_ACTIVE_CNT="$active_cnt"
    GAMECTL_LIB_LABEL="  ╢ gamectl :: Game Library [Store: $store_filter] ╟  "
    [ "$active_cnt" -gt 0 ] && GAMECTL_LIB_LABEL="  ╢ gamectl :: Game Library [Store: $store_filter] [Running: $active_cnt] ╟  "

    GAMECTL_LIB_HEADER="Enter: Launch/Manage │ Tab/Alt-S: Store │ Ctrl-I: Inject GBE │ Ctrl-F: Search │ Esc: Dashboard"
    if [ -n "$explicit_banner" ]; then
        GAMECTL_LIB_HEADER+=$'\n'"$explicit_banner"
    elif [ "$active_cnt" -gt 0 ]; then
        GAMECTL_LIB_HEADER+=$'\n'"[RUNNING ($active_cnt)] $active_names — Press Enter on a running game to Stop / View Logs"
    else
        local ex_row="" ex_pid="" ex_title="" ex_dir="" ex_log="" ex_hint="" ex_ts=""
        if ex_row=$(get_last_game_exit_event 15 2>/dev/null); then
            IFS="$sep" read -r ex_pid ex_title ex_dir ex_log ex_hint ex_ts <<< "$ex_row"
            if [ -n "$ex_hint" ]; then
                GAMECTL_LIB_HEADER+=$'\n'"[CRASHED] $ex_title exited — $ex_hint"
            elif [ -n "$ex_title" ]; then
                GAMECTL_LIB_HEADER+=$'\n'"[EXITED] $ex_title exited"
            fi
        fi
    fi
}

# Emit fzf transform() action string synchronizing library items, preview, label & header
tui_library_sync_actions() {
    local store_filter="${1:-ALL}"
    case "$store_filter" in
        ALL|STEAM|GOG|EPIC|AMAZON|STANDALONE) ;;
        *) store_filter="ALL" ;;
    esac
    _format_library_chrome "$store_filter" ""
    printf 'reload("$GAMECTL_PREVIEW_BIN" --list-formatted --store "%s")+refresh-preview+change-border-label(%s)+change-header:%s' \
        "$store_filter" "$GAMECTL_LIB_LABEL" "$GAMECTL_LIB_HEADER"
}

# Compute active store filter tokens using Installed-or-Authenticated pruning (Packet 43A)
get_visible_store_filters() {
    local -A store_counts=()
    local _id _title _st _dir _bin c_store
    if declare -F scan_installed_games >/dev/null 2>&1; then
        while IFS=$'\t' read -r _id _title _st _dir _bin c_store; do
            [[ "$_id" == \#* ]] && continue
            [ -n "$_dir" ] || continue
            c_store="${c_store:-STANDALONE}"
            c_store="${c_store^^}"
            store_counts["$c_store"]=$(( ${store_counts["$c_store"]:-0} + 1 ))
        done < <(scan_installed_games 2>/dev/null || true)
    fi

    printf '%s\n' "ALL"

    local has_steam_lib=0
    if [ "${store_counts[STEAM]:-0}" -gt 0 ]; then
        has_steam_lib=1
    elif declare -F get_steam_libraries >/dev/null 2>&1; then
        local slib
        while IFS= read -r slib; do
            if [ -n "$slib" ] && [ -d "$slib" ]; then
                has_steam_lib=1
                break
            fi
        done < <(get_steam_libraries 2>/dev/null || true)
    fi
    [ "$has_steam_lib" -eq 1 ] && printf '%s\n' "STEAM"

    if [ "${store_counts[GOG]:-0}" -gt 0 ] || \
       { declare -F _gog_resolve_cli >/dev/null 2>&1 && _gog_resolve_cli >/dev/null 2>&1 && \
         declare -F _gog_auth_session_present >/dev/null 2>&1 && _gog_auth_session_present; }; then
        printf '%s\n' "GOG"
    fi

    # Keep EPIC hidden when only gamectl-core binary exists without games or active auth
    if [ "${store_counts[EPIC]:-0}" -gt 0 ] || \
       { declare -F store_epic_available >/dev/null 2>&1 && store_epic_available >/dev/null 2>&1 && \
         declare -F _epic_auth_session_present >/dev/null 2>&1 && _epic_auth_session_present; }; then
        printf '%s\n' "EPIC"
    fi

    if [ "${store_counts[AMAZON]:-0}" -gt 0 ] || \
       { declare -F store_amazon_available >/dev/null 2>&1 && store_amazon_available >/dev/null 2>&1 && \
         declare -F _amazon_auth_session_present >/dev/null 2>&1 && _amazon_auth_session_present; }; then
        printf '%s\n' "AMAZON"
    fi

    if [ "${store_counts[STANDALONE]:-0}" -gt 0 ]; then
        printf '%s\n' "STANDALONE"
    fi
}

# Cycle to the next visible store filter token wrapping back to ALL
get_next_visible_store_filter() {
    local current="${1:-ALL}"
    local -a visible=()
    local item
    while IFS= read -r item; do
        [ -n "$item" ] && visible+=("$item")
    done < <(get_visible_store_filters)

    [ "${#visible[@]}" -gt 0 ] || { printf '%s\n' "ALL"; return 0; }

    local i idx=-1
    for i in "${!visible[@]}"; do
        if [ "${visible[$i]}" = "$current" ]; then
            idx="$i"
            break
        fi
    done

    if [ "$idx" -lt 0 ]; then
        printf '%s\n' "ALL"
    else
        local next_idx=$(( (idx + 1) % ${#visible[@]} ))
        printf '%s\n' "${visible[$next_idx]}"
    fi
}

# Build visible store picker TSV rows for Alt-S palette (Packet 43A)
build_visible_store_palette() {
    local s_tok=""
    while IFS= read -r s_tok; do
        [ -n "$s_tok" ] && _store_filter_label_row "$s_tok"
    done < <(get_visible_store_filters)
}

# Reset active store filter back to ALL if no longer visible (Packet 43A)
validate_visible_store_filter() {
    local current="${1:-ALL}" item=""
    [ "$current" = "ALL" ] && { printf '%s\n' "ALL"; return 0; }
    while IFS= read -r item; do
        [ "$item" = "$current" ] && { printf '%s\n' "$current"; return 0; }
    done < <(get_visible_store_filters)
    printf '%s\n' "ALL"
}
