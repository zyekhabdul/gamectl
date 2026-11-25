# ==============================================================================
# Unified Store Interface & Adapter Registry (Multi-Store Phase 1)
# ==============================================================================

# Print registered store adapter identifiers, one per line.
store_list_registered() {
    printf '%s\n' "steam" "gog" "epic" "amazon"
}

# Print store adapters that are offline-ready on this host.
store_list_available() {
    local store_name=""
    while IFS= read -r store_name; do
        [ -n "$store_name" ] || continue
        if declare -F "store_${store_name}_available" >/dev/null 2>&1; then
            if "store_${store_name}_available" >/dev/null 2>&1; then
                printf '%s\n' "$store_name"
            fi
        fi
    done < <(store_list_registered)
}

# Validate and dispatch an operation to a registered store adapter.
store_dispatch() {
    local store="${1:-}"
    local op="${2:-}"
    if [ -z "$store" ] || [ -z "$op" ]; then
        echo "Usage: store_dispatch <store> <op> [args...]" >&2
        return 1
    fi
    shift 2

    if [[ ! "$store" =~ ^[a-z0-9_]+$ ]]; then
        echo "[ERROR] Invalid store identifier: $store" >&2
        return 1
    fi

    if ! store_list_registered | grep -Fxq "$store"; then
        echo "[ERROR] Unsupported or unregistered store: $store" >&2
        return 1
    fi

    case "$op" in
        available|status|search|list_installed|download|sync)
            ;;
        *)
            echo "[ERROR] Unsupported store operation: $op (supported: available, status, search, list_installed, download, sync)" >&2
            return 1
            ;;
    esac

    local handler="store_${store}_${op}"
    if ! declare -F "$handler" >/dev/null 2>&1; then
        echo "[ERROR] Store adapter '$store' does not implement '$op' ($handler)" >&2
        return 1
    fi

    "$handler" "$@"
}

# CLI entrypoint for `gamectl stores [list|status]`
stores_cli() {
    local action="${1:-status}"
    local store_name=""
    case "$action" in
        list)
            while IFS= read -r store_name; do
                [ -n "$store_name" ] || continue
                if store_dispatch "$store_name" available >/dev/null 2>&1; then
                    printf '%-12s\t[AVAILABLE]\n' "$store_name"
                else
                    printf '%-12s\t[UNAVAILABLE]\n' "$store_name"
                fi
            done < <(store_list_registered)
            ;;
        status)
            while IFS= read -r store_name; do
                [ -n "$store_name" ] || continue
                store_dispatch "$store_name" status
            done < <(store_list_registered)
            ;;
        *)
            echo "Usage: gamectl stores [list|status]" >&2
            return 1
            ;;
    esac
}

# Unified headless authentication hub across all stores (never stores plaintext secrets).
auth_hub_cli() {
    local action="${1:-status}"
    [ $# -gt 0 ] && shift
    case "$action" in
        status)
            local lua_status="unconfigured"
            local lumen_auth="${XDG_DATA_HOME:-$HOME/.local/share}/Lumen/luatools/backend/data/lua_tools_auth.json"
            if [ -s "$HOME/.config/gamectl/lua_tools_auth.json" ] || [ -s "$lumen_auth" ]; then
                lua_status="session present"
            fi
            local hubcap_status="unconfigured"
            if declare -F get_hubcap_api_key >/dev/null 2>&1 && [ -n "$(get_hubcap_api_key 2>/dev/null || true)" ]; then
                hubcap_status="configured"
            fi
            printf 'store=steam\n  luatools : %s\n  hubcap   : %s\n' "$lua_status" "$hubcap_status"
            local s
            for s in gog epic amazon; do
                store_dispatch "$s" status
            done
            ;;
        gog)    gog_cli auth "$@" ;;
        epic)   epic_cli auth "$@" ;;
        amazon) amazon_cli auth "$@" ;;
        luatools)
            if [ $# -gt 0 ]; then
                login_luatools "$@"
            elif [ -t 0 ] && [ -t 1 ] && declare -F login_luatools_interactive >/dev/null 2>&1; then
                login_luatools_interactive
            else
                echo "Usage: gamectl auth luatools <code|token|session.json>" >&2
                return 1
            fi
            ;;
        --help|-h|help)
            echo "Usage: gamectl auth [status|gog|epic|amazon|luatools] [args...]"
            ;;
        *)
            echo "[ERROR] Unknown auth target '$action'. Usage: gamectl auth [status|gog|epic|amazon|luatools] [args...]" >&2
            return 1
            ;;
    esac
}

# Cross-store search aggregator returning validated 7-col TSV:
# STORE<TAB>APP_ID<TAB>TITLE<TAB>PLATFORMS<TAB>STATUS<TAB>ITEM_TYPE<TAB>PARENT_APPID
store_search_all() {
    local query="" target="all"
    while [ $# -gt 0 ]; do
        case "$1" in
            --store)
                [ -n "${2:-}" ] || { echo "[ERROR] --store requires a store name." >&2; return 1; }
                target="${2,,}"; shift 2 ;;
            --store=*)
                target="${1#*=}"; target="${target,,}"; shift ;;
            --help|-h)
                echo "Usage: gamectl search-stores <query> [--store <all|steam|gog|epic|amazon>]"
                return 0 ;;
            *)
                [ -z "$query" ] && query="$1" || query="$query $1"
                shift ;;
        esac
    done
    [ -n "$query" ] || { echo "[ERROR] Usage: gamectl search-stores <query> [--store <all|steam|gog|epic|amazon>]" >&2; return 1; }

    local -a targets=()
    if [ "$target" = "all" ]; then
        local avail_s
        while IFS= read -r avail_s; do
            [ -n "$avail_s" ] && targets+=("$avail_s")
        done < <(store_list_available)
    else
        store_list_registered | grep -Fxq "$target" || { echo "[ERROR] Unsupported store '$target'." >&2; return 1; }
        store_dispatch "$target" available >/dev/null 2>&1 || { echo "[ERROR] Store '$target' is unavailable on this host." >&2; return 1; }
        targets=("$target")
    fi

    local -a raw_rows=() steam_ids=()
    local st out line r_store r_id r_title r_plats r_status
    for st in "${targets[@]}"; do
        out=$(store_dispatch "$st" search "$query" 2>/dev/null || true)
        [ -n "$out" ] || continue
        while IFS=$'\t' read -r r_store r_id r_title r_plats r_status; do
            [ -n "$r_store" ] && [ -n "$r_id" ] || continue
            raw_rows+=("${r_store}"$'\t'"${r_id}"$'\t'"${r_title}"$'\t'"${r_plats}"$'\t'"${r_status}")
            [ "$r_store" = "STEAM" ] && [[ "$r_id" =~ ^[0-9]+$ ]] && steam_ids+=("$r_id")
        done <<< "$out"
    done
    [ "${#raw_rows[@]}" -gt 0 ] || { echo "[ERROR] Cross-store search returned no results for '$query'." >&2; return 1; }

    declare -A st_type=() st_parent=()
    if [ "${#steam_ids[@]}" -gt 0 ] && declare -F classify_steam_app_types >/dev/null 2>&1; then
        local c_out c_id c_type c_parent
        c_out=$(classify_steam_app_types "${steam_ids[@]}" 2>/dev/null || true)
        while IFS=$'\t' read -r c_id c_type c_parent; do
            [ -n "$c_id" ] || continue
            st_type["$c_id"]="${c_type:-APP}"
            st_parent["$c_id"]="${c_parent:-}"
        done <<< "$c_out"
    fi

    local emitted=0 item_type parent_id row
    for row in "${raw_rows[@]}"; do
        IFS=$'\t' read -r r_store r_id r_title r_plats r_status <<< "$row"
        if [ "$r_store" = "STEAM" ]; then
            item_type="${st_type[$r_id]:-APP}"
            parent_id="${st_parent[$r_id]:-}"
        else
            item_type="GAME"
            parent_id=""
        fi
        if declare -F validate_tui_fields >/dev/null 2>&1; then
            validate_tui_fields "$r_store" "$r_id" "$r_title" "$r_plats" "$r_status" "$item_type" "$parent_id" || continue
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$r_store" "$r_id" "$r_title" "$r_plats" "$r_status" "$item_type" "$parent_id"
        emitted=$((emitted + 1))
    done
    [ "$emitted" -gt 0 ]
}

# Standalone-source compatibility: load split store adapters when sourced directly outside bin/gamectl
if [ -z "${GAMECTL_BUNDLED:-}" ] && [ -n "${BASH_SOURCE[0]:-}" ]; then
    _stores_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _stores_sub in 10_store_steam.sh 20_store_gog.sh 30_store_epic.sh 40_store_amazon.sh; do
        if [ -f "$_stores_dir/$_stores_sub" ]; then
            # shellcheck source=/dev/null
            source "$_stores_dir/$_stores_sub"
        fi
    done
    unset _stores_dir _stores_sub
fi
