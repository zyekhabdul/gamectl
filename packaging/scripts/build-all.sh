#!/usr/bin/env bash
set -euo pipefail

# gamectl Multi-Platform Packaging Master Runner
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=================================================="
echo "[ ORCHESTRATOR ] gamectl Multi-Platform Packaging"
echo "=================================================="

# 1. Monolithic Binary Compilation
echo ""
echo "[ 1/3 ] Compiling Monolithic Standalone Binary..."
cd "$ROOT_DIR"
./scripts/build.sh

# 2. Debian / Ubuntu (.deb)
echo ""
echo "[ 2/3 ] Building Debian / Ubuntu (.deb) Package..."
bash "$ROOT_DIR/packaging/debian/build-deb.sh"

# 3. Arch Linux (.SRCINFO)
echo ""
echo "[ 3/3 ] Updating Arch Linux Package Metadata (.SRCINFO)..."
cd "$ROOT_DIR/packaging/arch"
makepkg --printsrcinfo > .SRCINFO
if [ -d "$ROOT_DIR/packaging/aur-git" ]; then
    cd "$ROOT_DIR/packaging/aur-git"
    makepkg --printsrcinfo > .SRCINFO
fi

echo ""
echo "=================================================="
echo "[ VERIFIED ] ALL PLATFORM PACKAGES SUCCESSFULLY BUILT:"
echo "=================================================="
ls -lh "$ROOT_DIR/bin/gamectl"
ls -lh "$ROOT_DIR/packaging/debian"/*.deb 2>/dev/null || true
ls -lh "$ROOT_DIR/packaging/arch/.SRCINFO"
ls -lh "$ROOT_DIR/packaging/aur-git/.SRCINFO" 2>/dev/null || true
echo "=================================================="
