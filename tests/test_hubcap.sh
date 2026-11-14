#!/usr/bin/env bash
# ==============================================================================
# gamectl - Hubcap Manifest & Config Storage Automated Contract Test
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GAMECTL="$REPO_ROOT/bin/gamectl"

echo "=== [TEST] gamectl config & Hubcap provider contract ==="

t_home=$(mktemp -d "${TMPDIR:-/tmp}/gamectl_hubcap_test.XXXXXX")
trap 'rm -rf "$t_home"' EXIT

# 1. Test CLI config set & get with hubcap_key alias
HOME="$t_home" "$GAMECTL" config set hubcap_key "smm_test_secret_123" >/dev/null
got_key=$(HOME="$t_home" "$GAMECTL" config get hubcap_key)
got_api_key=$(HOME="$t_home" "$GAMECTL" config get hubcap_api_key)

if [ "$got_key" != "smm_test_secret_123" ] || [ "$got_api_key" != "smm_test_secret_123" ]; then
    echo "[FAIL] config get returned unexpected key: '$got_key' / '$got_api_key'" >&2
    exit 1
fi

if ! grep -q "hubcap_api_key=smm_test_secret_123" "$t_home/.config/gamectl/config"; then
    echo "[FAIL] config file does not contain hubcap_api_key=smm_test_secret_123" >&2
    exit 1
fi
echo "[PASS] gamectl config set/get resolves hubcap_key and hubcap_api_key symmetrically."

# 2. Test graceful fallback when unconfigured
rm -rf "$t_home/.config/gamectl"
unconf_out=$(HOME="$t_home" "$GAMECTL" fetch-manifest 999999 2>&1 || true)
if ! echo "$unconf_out" | grep -q 'Hubcap provider was skipped (no API key configured)'; then
    echo "[FAIL] fetch-manifest did not skip unconfigured Hubcap gracefully: $unconf_out" >&2
    exit 1
fi
echo "[PASS] fetch-manifest skips Hubcap without error when key is unconfigured."

# 3. Test explicit provider flag without key triggers clean error
explicit_err=$(HOME="$t_home" "$GAMECTL" fetch-manifest 999999 "" hubcap 2>&1 || true)
if ! echo "$explicit_err" | grep -q 'Hubcap API key is not configured'; then
    echo "[FAIL] fetch-manifest with explicit source=hubcap did not error cleanly: $explicit_err" >&2
    exit 1
fi
echo "[PASS] explicit source=hubcap errors cleanly with instruction when unconfigured."

echo "[VERIFIED] All Hubcap and config contracts passed with exit code 0."
