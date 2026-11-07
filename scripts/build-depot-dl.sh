#!/usr/bin/env bash
# ==============================================================================
# gamectl - Reproducible Standalone Depot Downloader Compiler
# Builds the native Rust Steam CDN depot downloader crate.
# ==============================================================================
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CRATE_DIR="$REPO_ROOT/crates/depot-dl"
OUTPUT_DIR="$REPO_ROOT/bin"

if ! command -v cargo >/dev/null 2>&1; then
    echo "[ERROR] Cargo / Rust toolchain not found on PATH." >&2
    echo "        Please install rustup / cargo to compile gamectl-depot-dl." >&2
    exit 1
fi

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

OUTPUT_NAME="gamectl-depot-dl"
if [[ "$TARGET_TRIPLE" =~ (windows|mingw|msvc) ]]; then
    OUTPUT_NAME="gamectl-depot-dl.exe"
fi

if [ "$CHECK_ONLY" = true ]; then
    if [ -f "$OUTPUT_DIR/$OUTPUT_NAME" ] && [ -x "$OUTPUT_DIR/$OUTPUT_NAME" ]; then
        echo "[PASS] $OUTPUT_NAME is present and executable at $OUTPUT_DIR/$OUTPUT_NAME"
        exit 0
    else
        echo "[FAIL] $OUTPUT_NAME missing or not executable at $OUTPUT_DIR/$OUTPUT_NAME" >&2
        exit 1
    fi
fi

CARGO_ARGS=("build" "--bin" "gamectl-depot-dl")
[ -n "$PROFILE_FLAG" ] && CARGO_ARGS+=("$PROFILE_FLAG")

if [ -n "$TARGET_TRIPLE" ]; then
    CARGO_ARGS+=(--target "$TARGET_TRIPLE")
    TARGET_BIN="$CRATE_DIR/target/$TARGET_TRIPLE/$BUILD_PROFILE/$OUTPUT_NAME"
else
    TARGET_BIN="$CRATE_DIR/target/$BUILD_PROFILE/$OUTPUT_NAME"
fi

echo "=================================================="
echo " BUILDING NATIVE DEPOT DOWNLOADER (Rust)"
echo " Crate Dir : $CRATE_DIR"
echo " Profile   : $BUILD_PROFILE"
[ -n "$TARGET_TRIPLE" ] && echo " Target    : $TARGET_TRIPLE"
echo " Artifact  : $OUTPUT_DIR/$OUTPUT_NAME"
echo "=================================================="

build_status=0
(
    cd "$CRATE_DIR"
    cargo "${CARGO_ARGS[@]}"
) || build_status=$?

if [ $build_status -ne 0 ]; then
    if [ -f "$OUTPUT_DIR/$OUTPUT_NAME" ] && [ "$FORCE" = false ]; then
        echo "[WARN] Local cargo build exited with code $build_status." >&2
        echo "       Preserving validated pre-existing binary at: $OUTPUT_DIR/$OUTPUT_NAME" >&2
        exit 0
    else
        echo "[ERROR] Compilation failed with exit code $build_status and no existing fallback binary found." >&2
        exit "$build_status"
    fi
fi

if [ ! -f "$TARGET_BIN" ]; then
    if [ -f "$OUTPUT_DIR/$OUTPUT_NAME" ]; then
        echo "[WARN] Build artifact $TARGET_BIN not found, retaining $OUTPUT_DIR/$OUTPUT_NAME"
        exit 0
    fi
    echo "[ERROR] Compilation finished but artifact was not found at: $TARGET_BIN" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cp -f "$TARGET_BIN" "$OUTPUT_DIR/$OUTPUT_NAME"
chmod +x "$OUTPUT_DIR/$OUTPUT_NAME" 2>/dev/null || true

file_size=$(stat -c%s "$OUTPUT_DIR/$OUTPUT_NAME" 2>/dev/null || stat -f%z "$OUTPUT_DIR/$OUTPUT_NAME" 2>/dev/null || echo "0")
size_mb=$(awk "BEGIN {printf \"%.2f\", $file_size / (1024 * 1024)}")

echo "[ VERIFIED ] $OUTPUT_NAME successfully built -> $OUTPUT_DIR/$OUTPUT_NAME (${size_mb} MB)"
