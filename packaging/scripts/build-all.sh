#!/usr/bin/env bash
set -euo pipefail

# gamectl Multi-Platform Packaging Master Runner
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=================================================="
echo "[ ORCHESTRATOR ] gamectl Multi-Platform Packaging"
echo "=================================================="

# 1. Monolithic Binary Compilation & Native Depot Downloader
echo ""
echo "[ 1/4 ] Compiling Monolithic Standalone Binary & Native Depot Downloader..."
cd "$ROOT_DIR"
./scripts/build.sh
if [ -f "$ROOT_DIR/scripts/build-depot-dl.sh" ]; then
    ./scripts/build-depot-dl.sh --check >/dev/null 2>&1 || ./scripts/build-depot-dl.sh
fi

# 2. Debian / Ubuntu (.deb)
echo ""
echo "[ 2/4 ] Building Debian / Ubuntu (.deb) Package..."
bash "$ROOT_DIR/packaging/debian/build-deb.sh"

# 3. Arch Linux (.SRCINFO)
echo ""
echo "[ 3/4 ] Updating Arch Linux Package Metadata (.SRCINFO)..."
cd "$ROOT_DIR/packaging/arch"
makepkg --printsrcinfo > .SRCINFO
if [ -d "$ROOT_DIR/packaging/aur-git" ]; then
    cd "$ROOT_DIR/packaging/aur-git"
    makepkg --printsrcinfo > .SRCINFO
fi

# 4. PyPI / Python Wheel & Sdist
echo ""
echo "[ 4/4 ] Building Python Wheel & Source Distribution..."
cd "$ROOT_DIR"
rm -rf dist/ build/ src/*.egg-info
python3 -m build --no-isolation
twine check dist/*

echo ""
echo "=================================================="
echo "[ VERIFIED ] ALL PLATFORM PACKAGES SUCCESSFULLY BUILT:"
echo "=================================================="
ls -lh "$ROOT_DIR/bin/gamectl"
ls -lh "$ROOT_DIR/bin/gamectl-depot-dl" 2>/dev/null || true
ls -lh "$ROOT_DIR/packaging/debian"/*.deb 2>/dev/null || true
ls -lh "$ROOT_DIR/packaging/arch/.SRCINFO"
ls -lh "$ROOT_DIR/packaging/aur-git/.SRCINFO" 2>/dev/null || true
ls -lh "$ROOT_DIR/dist"/* 2>/dev/null || true
echo "=================================================="
