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
