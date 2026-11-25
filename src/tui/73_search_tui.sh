# ==============================================================================
# Live Steam Store Search & Actionable TUI Picker (Split from 70_dashboard.sh)
# ==============================================================================

# Live Steam Search View (Actionable TUI Search)
search_steam() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo "[ERROR] Interactive Steam search requires a terminal (TTY)." >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "[ERROR] fzf is required for interactive mode but was not found in PATH." >&2
        return 127
    fi

    local query="${1:-}"
    local standalone="${2:-false}"
    [ "$standalone" = "true" ] && enter_tui_screen
    flush_tty_input
    if [ -z "$query" ]; then
        local fzf_rc=0
        # Input primitive canonicalized via tui_prompt_input (: | fzf wrapper)
        query=$(tui_prompt_input "gamectl :: Steam Store Search" "Type game title to search (Enter: Search │ Esc: Cancel)" "" "Search Store > ") || fzf_rc=$?
        [ "$fzf_rc" -eq 130 ] && return 0
        if [ "$fzf_rc" -ne 0 ]; then
            [ "$standalone" = "true" ] && exit_tui_screen
            return "$fzf_rc"
        fi
        query=$(echo "$query" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$query" ]; then
            [ "$standalone" = "true" ] && exit_tui_screen
            return 0
        fi
    fi

    log_msg "INFO" "STORE" "Searching '$query' on Steam Store API..."
    local encoded_query
    encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
    local raw_results
    raw_results=$(curl -s --connect-timeout 5 --max-time 15 "https://store.steampowered.com/api/storesearch/?term=${encoded_query}&l=english&cc=US" 2>/dev/null)

    local items
    items=$(printf '%s' "$raw_results" | store_search_items) || {
        echo "[ERROR] Invalid Steam search catalog." >&2
        return 1
    }

    if [ -z "$items" ]; then
        log_msg "WARN" "STORE" "Game '$query' not found on Steam Store API."
        tui_modal_notice "Steam Store Search" "Game '$query' was not found on Steam Store." || return $?
        [ "$standalone" = "true" ] && exit_tui_screen
        return 0
    fi

    # Build list with local installed status across all libraries via scan_installed_games
    local results=""
    local type_filter="ALL"
    declare -A installed_by_id=()
    declare -A installed_by_title=()
    declare -A installed_dir=()
    declare -A item_type_map=()
    declare -A item_parent_map=()

    _classify_current_items() {
        item_type_map=()
        item_parent_map=()
        local -a batch_ids=()
        local c_id c_name
        while IFS=$'\t' read -r c_id c_name; do
            c_id="${c_id//[[:space:]]/}"
            [[ "$c_id" =~ ^[0-9]+$ ]] && batch_ids+=("$c_id")
        done <<< "$items"
        [ "${#batch_ids[@]}" -eq 0 ] && return 0

        local c_out c_type c_parent
        c_out=$(classify_steam_app_types "${batch_ids[@]}" 2>/dev/null || true)
        while IFS=$'\t' read -r c_id c_type c_parent; do
            [ -n "$c_id" ] || continue
            item_type_map["$c_id"]="${c_type:-APP}"
            item_parent_map["$c_id"]="${c_parent:-}"
        done <<< "$c_out"
    }

    _refresh_search_results() {
        results=""
        installed_by_id=()
        installed_by_title=()
        installed_dir=()

        local sc_id sc_name sc_st sc_dir sc_bin
        while IFS=$'\t' read -r sc_id sc_name sc_st sc_dir sc_bin; do
            sc_id="${sc_id//[[:space:]]/}"
            sc_name="${sc_name#"${sc_name%%[![:space:]]*}"}"
            sc_name="${sc_name%"${sc_name##*[![:space:]]}"}"
            sc_dir="${sc_dir//$'\r'/}"
            if [ -n "$sc_id" ] && [ "$sc_id" != "STANDALONE" ]; then
                installed_by_id["$sc_id"]=1
                installed_dir["$sc_id"]="$sc_dir"
            fi
            if [ -n "$sc_name" ]; then
                local clean_title="${sc_name,,}"
                installed_by_title["$clean_title"]=1
                [ -z "${installed_dir["$clean_title"]:-}" ] && installed_dir["$clean_title"]="$sc_dir"
            fi
        done < <(scan_installed_games --refresh)

        while IFS=$'\t' read -r appid name; do
            [ -z "$appid" ] && continue
            local is_installed=0
            local clean_name="${name,,}"
            if [[ -v installed_by_id["$appid"] ]] || [[ -v installed_by_title["$clean_name"] ]]; then
                is_installed=1
            fi
            local status="${UI_DIM}[NOT INSTALLED]${UI_RST}"
            [ "$is_installed" -eq 1 ] && status="${UI_GREEN}[INSTALLED]    ${UI_RST}"
            local raw_type="${item_type_map[$appid]:-APP}"
            local parent_appid="${item_parent_map[$appid]:-}"
            local type_badge
            type_badge="$(format_app_type_badge "$raw_type")"
            validate_tui_fields "$appid" "$name" "$raw_type" "$parent_appid" || continue
            results+="${appid}"$'\t'"${type_badge}"$'\t'"${name}"$'\t'"${status}"$'\t'"${raw_type}"$'\t'"${parent_appid}"$'\n'
        done <<< "$items"
    }

    _filtered_search_results() {
        if [ "$type_filter" = "ALL" ]; then
            printf '%s' "$results"
        else
            printf '%s' "$results" | awk -F'\t' -v tf="$type_filter" '$5 == tf'
        fi
    }

    _classify_current_items
    _refresh_search_results

    export GAMECTL_PREVIEW_BIN="$SELF_BIN"

    while true; do
        flush_tty_input
        local fzf_out fzf_rc=0
        local fzf_header="Enter: Actions │ Tab: Type ($type_filter) │ Alt-S: All Stores │ Ctrl-F: New Search │ Esc: Dashboard"
        fzf_out=$(_filtered_search_results | fzf \
            --delimiter=$'\t' \
            --with-nth=1,2,3,4 \
            --expect=tab,alt-s,ctrl-a,ctrl-u,ctrl-s,ctrl-d,ctrl-f \
            --bind="tab:accept,alt-s:accept,ctrl-a:accept,ctrl-u:accept,ctrl-s:accept,ctrl-d:accept,ctrl-f:accept" \
            --border-label="  ╢ gamectl :: Steam Store Catalog [Type: $type_filter] ╟  " \
            --border-label-pos=2 \
            --header="$fzf_header" \
            --prompt="Filter Results > " \
            --preview='"$GAMECTL_PREVIEW_BIN" --preview-search {1} {3} {4}' \
            --preview-window=right:52%:border-rounded:wrap \
        ) || fzf_rc=$?

        [ "$fzf_rc" -eq 130 ] && break
        if [ "$fzf_rc" -ne 0 ] && [ "$fzf_rc" -ne 1 ]; then
            echo "[ERROR] Steam search catalog failed (fzf exit code $fzf_rc)." >&2
            return "$fzf_rc"
        fi
        [ -z "$fzf_out" ] && continue

        local trigger_key selection
        trigger_key=$(echo "$fzf_out" | sed -n '1p')
        selection=$(echo "$fzf_out" | sed -n '2,$p')

        if [ "$trigger_key" = "tab" ]; then
            case "$type_filter" in
                ALL)  type_filter="GAME" ;;
                GAME) type_filter="DLC" ;;
                *)    type_filter="ALL" ;;
            esac
            continue
        fi

        if [ "$trigger_key" = "alt-s" ]; then
            search_stores_interactive "$query" || true
            _refresh_search_results
            continue
        fi

        if [ "$trigger_key" = "ctrl-f" ]; then
            local new_q n_rc=0
            new_q=$(tui_prompt_input "gamectl :: Steam Store Search" "Type game title to search (Enter: Search │ Esc: Keep Current List)" "" "Search Store > ") || n_rc=$?
            if [ "$n_rc" -eq 130 ]; then
                continue
            fi
            if [ "$n_rc" -ne 0 ]; then
                return "$n_rc"
            fi
            new_q=$(echo "$new_q" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -z "$new_q" ]; then
                continue
            fi

            log_msg "INFO" "STORE" "Searching '$new_q' on Steam Store API..."
            local new_encoded_query
            new_encoded_query=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$new_q")
            local new_raw_results
            new_raw_results=$(curl -s --connect-timeout 5 --max-time 15 "https://store.steampowered.com/api/storesearch/?term=${new_encoded_query}&l=english&cc=US" 2>/dev/null)
            local new_items
            new_items=$(printf '%s' "$new_raw_results" | store_search_items) || true

            if [ -z "$new_items" ]; then
                log_msg "WARN" "STORE" "Game '$new_q' not found on Steam Store API."
                tui_modal_notice "Steam Store Search" "Game '$new_q' was not found on Steam Store." || true
                continue
            fi

            query="$new_q"
            items="$new_items"
            type_filter="ALL"
            _classify_current_items
            _refresh_search_results
            continue
        fi

        [ -z "$selection" ] && continue

        local sel_id="" sel_name="" sel_status="" sel_type="" sel_parent=""
        local _c1="" _c2="" _c3="" _c4="" _c5="" _c6=""
        IFS=$'\t' read -r _c1 _c2 _c3 _c4 _c5 _c6 <<< "$selection"
        if [ -n "$_c4" ]; then
            sel_id="$_c1"
            sel_name="$_c3"
            sel_status="$_c4"
            sel_type="$_c5"
            sel_parent="$_c6"
        else
            sel_id="$_c1"
            sel_name="$_c2"
            sel_status="$_c3"
        fi

        local gdir=""
        local clean_sel_name="${sel_name,,}"
        if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
            if [ -n "${installed_dir["$sel_id"]:-}" ] && [ -d "${installed_dir["$sel_id"]}" ]; then
                gdir="${installed_dir["$sel_id"]}"
            elif [ -n "${installed_dir["$clean_sel_name"]:-}" ] && [ -d "${installed_dir["$clean_sel_name"]}" ]; then
                gdir="${installed_dir["$clean_sel_name"]}"
            elif [ -d "$HOME/Games/$sel_name" ]; then
                gdir="$HOME/Games/$sel_name"
            fi
        fi

        # Resolve optimal destination library and target OS platform for uninstalled games
        local dest_dir target_os="linux"
        local -a dl_extra_args=()
        if [[ ! "$sel_status" =~ INSTALLED ]] || [[ "$sel_status" =~ NOT ]]; then
            dest_dir="$(resolve_target_library_dir "$sel_name")"
            target_os="$(detect_app_platform_os "$sel_id")"
        fi

        _prepare_download_target() {
            dl_extra_args=()
            [ "$sel_type" = "DLC" ] || return 0

            local parent_id="" parent_name=""
            if declare -F resolve_steam_app_type >/dev/null 2>&1; then
                local r_info="" r_type=""
                r_info=$(resolve_steam_app_type "$sel_id" 2>/dev/null || true)
                IFS=$'\t' read -r r_type parent_id parent_name <<< "$r_info"
            fi
            [[ "$parent_id" =~ ^[0-9]+$ ]] || parent_id="$sel_parent"
            [[ "$parent_id" =~ ^[0-9]+$ ]] || return 0

            local dlc_choice="" dlc_rc=0
            local base_label="${parent_name:-AppID $parent_id}"
            dlc_choice=$(tui_action_palette \
                "DLC Selected" \
                "AppID $sel_id ($sel_name) is a DLC. Base game downloads already include associated DLC depots." \
                "$(printf 'base\tDownload Base Game (%s • %s) [Recommended]\ndlc\tDownload DLC Only (%s • %s) [--allow-dlc]\ncancel\tCancel / Return\n' "$base_label" "$parent_id" "$sel_name" "$sel_id")" \
                "" \
                "DLC Action > ") || dlc_rc=$?
            [ "$dlc_rc" -eq 130 ] && return 130
            if [ "$dlc_rc" -ne 0 ] && [ "$dlc_rc" -ne 1 ]; then
                return "$dlc_rc"
            fi
            local dlc_opt="${dlc_choice%%$'\t'*}"
            case "$dlc_opt" in
                base)
                    sel_id="$parent_id"
                    sel_name="${parent_name:-AppID_${parent_id}}"
                    dest_dir="$(resolve_target_library_dir "$sel_name")"
                    target_os="$(detect_app_platform_os "$sel_id")"
                    dl_extra_args=()
                    return 0
                    ;;
                dlc)
                    dl_extra_args=("--allow-dlc")
                    return 0
                    ;;
                *)
                    return 130
                    ;;
            esac
        }

        # Direct hotkey triggers
        if [ "$trigger_key" = "ctrl-a" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-A>: Injecting standalone GBE for $sel_name ($sel_id)"
                tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$gdir" "$sel_id"
            else
                local prep_rc=0
                _prepare_download_target || prep_rc=$?
                [ "$prep_rc" -eq 130 ] && continue
                [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-A>: Starting All-in-One Download for $sel_name ($target_os)"
                tui_exec_action "All-in-One Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
            fi
        elif [ "$trigger_key" = "ctrl-u" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-U>: Synchronizing Steam Entitlement & ACF for $sel_name ($sel_id)"
                tui_exec_action "Synchronize Steam Entitlement ($sel_name)" sync_steam "$sel_id" "$sel_name" "$gdir"
            else
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-U>: Adopting Steam Entitlement & ACF for $sel_name ($sel_id)"
                tui_exec_action "Adopt Steam Entitlement ($sel_name)" unlock_game "$sel_id" "$sel_name"
            fi
        elif [ "$trigger_key" = "ctrl-s" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-S>: Injecting Standalone GBE Fork for $sel_name ($sel_id)"
                tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$gdir" "$sel_id" --no-sync
            else
                local prep_rc=0
                _prepare_download_target || prep_rc=$?
                [ "$prep_rc" -eq 130 ] && continue
                [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-S>: Starting Standalone Download for $sel_name ($target_os)"
                tui_exec_action "Standalone Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --inject-only --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
            fi
        elif [ "$trigger_key" = "ctrl-d" ]; then
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                local gbin
                gbin=$(find_game_binary "$gdir" 2>/dev/null || echo "")
                if [ -n "$gbin" ]; then
                    local launch_rc=0
                    tui_run_engine "Launch $sel_name" launch_game "$gdir" "$gbin" "$sel_name" || launch_rc=$?
                    if [ "$launch_rc" -eq 10 ]; then
                        break
                    fi
                else
                    log_msg "ERROR" "LAUNCH" "Binary executable not found in $gdir for $sel_name"
                    tui_modal_notice "Executable Not Found" "Binary executable not found in directory:\n$gdir" || return $?
                fi
            else
                local prep_rc=0
                _prepare_download_target || prep_rc=$?
                [ "$prep_rc" -eq 130 ] && continue
                [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                log_msg "INFO" "HOTKEY" "Shortcut <Ctrl-D>: Starting Live Stream Download for $sel_name ($target_os)"
                tui_exec_action "Live Stream Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
            fi
        else
            # Enter key: Open Modal Action Palette
            if [[ "$sel_status" =~ INSTALLED ]] && [[ ! "$sel_status" =~ NOT ]]; then
                local action_palette
                action_palette=$(cat <<EOF
1	Launch Game Directly
2	Inject GBE Fork Only (Standalone ./saves & DLC.txt)
3	Inject GBE + Sync Steam Client (All-in-One Full DLC)
4	Sync to Steam Client Entitlement Only (ACF & Steam Input)
5	Check Community Fixes & Online-Fix Catalog
6	Cancel / Return
EOF
)
                local action_sel action_rc=0
                action_sel=$(echo "$action_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=2 \
                    --border-label="  ╢ Action Palette: $sel_name ╟  " \
                    --border-label-pos=2 \
                    --header="ACTION PALETTE (Enter: Execute │ Esc: Return)" \
                    --prompt="Action > " \
                    --reverse 2>/dev/null) || action_rc=$?
                check_fzf_status "$action_rc" || return $?
                [ "$action_rc" -eq 130 ] && continue

                local act_opt
                act_opt=$(echo "$action_sel" | awk -F'\t' '{print $1}')

                case "$act_opt" in
                    1)
                        local gbin
                        gbin=$(find_game_binary "$gdir" 2>/dev/null || echo "")
                        if [ -n "$gbin" ]; then
                            local launch_rc=0
                            tui_run_engine "Launch $sel_name" launch_game "$gdir" "$gbin" "$sel_name" || launch_rc=$?
                            if [ "$launch_rc" -eq 10 ]; then
                                break
                            fi
                        else
                            log_msg "ERROR" "LAUNCH" "Binary executable not found in $gdir for $sel_name"
                            tui_modal_notice "Executable Not Found" "Binary executable not found in directory:\n$gdir" || return $?
                        fi
                        ;;
                    2)
                        tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$gdir" "$sel_id" --no-sync
                        ;;
                    3)
                        tui_exec_action "Inject GBE + Steam Sync ($sel_name)" inject_game "$gdir" "$sel_id" --all
                        ;;
                    4)
                        tui_exec_action "Synchronize Steam Entitlement ($sel_name)" sync_steam "$sel_id" "$sel_name" "$gdir"
                        ;;
                    5)
                        manage_game_fixes_interactive "$sel_id" "$sel_name" "$gdir" || return $?
                        ;;
                    *)
                        ;;
                esac
            else
                local not_installed_palette
                not_installed_palette=$(cat <<EOF
1	[Sovereign Standalone] Download & Auto-Provision via CDN (Zero-Steam GBE)
2	[Steam Client Bridge] Adopt files & DLC to Steam Client (Requires Steam)
3	[Offline GBE] Inject GBE LAN runtime (Steam-free)
4	[Fixes & OnlineFix] Check Community Fixes & Online-Fix Catalog
5	Cancel / Return
EOF
)
                local pkg_sel pkg_rc=0
                pkg_sel=$(echo "$not_installed_palette" | fzf \
                    --delimiter=$'\t' \
                    --with-nth=2 \
                    --border-label="  ╢ Action Palette: $sel_name ╟  " \
                    --border-label-pos=2 \
                    --header="PACKAGE SELECTION (Enter: Execute │ Esc: Return)" \
                    --prompt="Package > " \
                    --reverse 2>/dev/null) || pkg_rc=$?
                check_fzf_status "$pkg_rc" || return $?
                [ "$pkg_rc" -eq 130 ] && continue

                local opt
                opt=$(echo "$pkg_sel" | awk -F'\t' '{print $1}')
                case "$opt" in
                    1)
                        local prep_rc=0
                        _prepare_download_target || prep_rc=$?
                        [ "$prep_rc" -eq 130 ] && continue
                        [ "$prep_rc" -ne 0 ] && return "$prep_rc"
                        tui_exec_action "Sovereign Standalone Download ($sel_name)" download_game "$sel_id" "$dest_dir" "$sel_name" --all --os "$target_os" ${dl_extra_args[@]+"${dl_extra_args[@]}"}
                        ;;
                    2)
                        tui_exec_action "Adopt Steam Entitlement ($sel_name)" unlock_game "$sel_id" "$sel_name"
                        ;;
                    3)
                        tui_exec_action "Inject Standalone GBE ($sel_name)" inject_game "$dest_dir" "$sel_id" --no-sync
                        ;;
                    4)
                        manage_game_fixes_interactive "$sel_id" "$sel_name" "" || return $?
                        ;;
                    *)
                        ;;
                esac
            fi
        fi
        _refresh_search_results
    done

    flush_tty_input
    [ "$standalone" = "true" ] && exit_tui_screen
    return 0
}
