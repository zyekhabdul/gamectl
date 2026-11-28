#!/usr/bin/env bash
# ==============================================================================
# gamectl - MIT Native Core Engine Compiler (crates/gamectl-core)
# ==============================================================================
set -euo pipefail

export RUST_MIN_STACK="${RUST_MIN_STACK:-536870912}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
if command -v clang >/dev/null 2>&1; then
    export CC="${CC:-clang}"
    export CXX="${CXX:-clang++}"
fi
if [ -z "${RUSTC:-}" ] && [ -x "/usr/bin/rustc" ]; then
    export RUSTC="/usr/bin/rustc"
    export PATH="/usr/bin:$PATH"
fi
CARGO_BIN="cargo"
if [ -x "/usr/bin/cargo" ]; then
    CARGO_BIN="/usr/bin/cargo"
elif command -v cargo >/dev/null 2>&1; then
    CARGO_BIN="$(command -v cargo)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CRATE_DIR="$REPO_ROOT/crates/gamectl-core"
OUTPUT_DIR="$REPO_ROOT/bin"

TARGET_TRIPLE=""
BUILD_PROFILE="release"
PROFILE_FLAG="--release"
CHECK_ONLY=false
FORCE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            shift
            TARGET_TRIPLE="${1:-}"
            ;;
        --target=*)
            TARGET_TRIPLE="${1#--target=}"
            ;;
        --debug)
            BUILD_PROFILE="debug"
            PROFILE_FLAG=""
            ;;
        --release)
            BUILD_PROFILE="release"
            PROFILE_FLAG="--release"
            ;;
        --check)
            CHECK_ONLY=true
            ;;
        --force|-f)
            FORCE=true
            ;;
        *)
            echo "Usage: $0 [--target <triple>] [--release|--debug] [--check] [--force]" >&2
            exit 1
            ;;
    esac
    shift
done

OUTPUT_NAME="gamectl-core"
if [[ "$TARGET_TRIPLE" =~ (windows|mingw|msvc) ]]; then
    OUTPUT_NAME="gamectl-core.exe"
fi

if [ "$CHECK_ONLY" = true ]; then
    if [ ! -f "$OUTPUT_DIR/$OUTPUT_NAME" ] || [ ! -x "$OUTPUT_DIR/$OUTPUT_NAME" ]; then
        echo "[FAIL] $OUTPUT_NAME missing or not executable at $OUTPUT_DIR/$OUTPUT_NAME" >&2
        exit 1
    fi
    stale_file=$(find "$CRATE_DIR/Cargo.toml" "$CRATE_DIR/Cargo.lock" "$CRATE_DIR/src" -type f -newer "$OUTPUT_DIR/$OUTPUT_NAME" 2>/dev/null | head -n 1 || true)
    if [ -n "$stale_file" ]; then
        echo "[FAIL] $OUTPUT_NAME is stale (newer source: $stale_file). Run ./scripts/build-core.sh" >&2
        exit 1
    fi
    echo "[PASS] $OUTPUT_NAME is present, executable, and up-to-date at $OUTPUT_DIR/$OUTPUT_NAME"
    exit 0
fi

if ! command -v "$CARGO_BIN" >/dev/null 2>&1; then
    if [ -f "$OUTPUT_DIR/$OUTPUT_NAME" ] && [ "$FORCE" = false ]; then
        echo "[WARN] Cargo / Rust toolchain not found on PATH; preserving $OUTPUT_DIR/$OUTPUT_NAME" >&2
        exit 0
    fi
    echo "[ERROR] Cargo / Rust toolchain not found on PATH." >&2
    exit 1
fi

CARGO_ARGS=("build" "--bin" "gamectl-core")
[ -f "$CRATE_DIR/Cargo.lock" ] && CARGO_ARGS+=("--locked")
[ -n "$PROFILE_FLAG" ] && CARGO_ARGS+=("$PROFILE_FLAG")
if [ -n "$TARGET_TRIPLE" ]; then
    CARGO_ARGS+=(--target "$TARGET_TRIPLE")
    TARGET_BIN="$CRATE_DIR/target/$TARGET_TRIPLE/$BUILD_PROFILE/$OUTPUT_NAME"
else
    TARGET_BIN="$CRATE_DIR/target/$BUILD_PROFILE/$OUTPUT_NAME"
fi

(
    cd "$CRATE_DIR"
    "$CARGO_BIN" "${CARGO_ARGS[@]}"
)

mkdir -p "$OUTPUT_DIR"
cp -f "$TARGET_BIN" "$OUTPUT_DIR/$OUTPUT_NAME"
chmod 0755 "$OUTPUT_DIR/$OUTPUT_NAME"
command -v strip >/dev/null 2>&1 && strip "$OUTPUT_DIR/$OUTPUT_NAME" 2>/dev/null || true

file_size=$(stat -c%s "$OUTPUT_DIR/$OUTPUT_NAME" 2>/dev/null || echo "0")
size_mb=$(awk "BEGIN {printf \"%.2f\", $file_size / (1024 * 1024)}")
echo "[ VERIFIED ] $OUTPUT_NAME built -> $OUTPUT_DIR/$OUTPUT_NAME (${size_mb} MB)"
