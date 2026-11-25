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

    local pick p_rc=0
    pick=$(printf '%s' "$rows" | fzf --delimiter=$'\t' --with-nth=1,2,3,4,5,6 \
        --border-label="  ╢ gamectl :: Cross-Store Catalog ($target_store) ╟  " --border-label-pos=2 \
        --header="Enter: Download via Store Adapter │ Esc: Return" --prompt="Cross-Store > ") || p_rc=$?
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
