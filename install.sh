#!/usr/bin/env bash
# ==============================================================================
# VALKYRIE INSTALLER
# ==============================================================================
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
SRC_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/valkyrie"

echo "[INFO] Memeriksa dependensi sistem..."
for cmd in fzf jq curl rsync ssh file; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Dependensi '$cmd' tidak ditemukan. Harap install terlebih dahulu." >&2
        exit 1
    fi
done

mkdir -p "$BIN_DIR"
chmod +x "$SRC_BIN"

# Create symlinks
ln -sf "$SRC_BIN" "$BIN_DIR/valkyrie"
ln -sf "$SRC_BIN" "$BIN_DIR/game"

echo "[VERIFIED] Valkyrie berhasil di-link ke $BIN_DIR/valkyrie dan $BIN_DIR/game"
echo "Jalankan perintah 'valkyrie' atau 'game' di terminal untuk membuka antarmuka."
