"""gamectl runner - Python shim for sovereign native gamectl CLI."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path


def get_bundled_bin() -> Path:
    """Locate bundled gamectl executable."""
    # 1. Check inside package directory (installed wheel)
    pkg_bin = Path(__file__).parent / "bin" / "gamectl"
    if pkg_bin.is_file():
        return pkg_bin

    # 2. Check repo root if running in editable/dev mode
    repo_bin = Path(__file__).resolve().parent.parent.parent / "bin" / "gamectl"
    if repo_bin.is_file():
        return repo_bin

    # 3. Check PATH for existing system gamectl
    system_bin = shutil.which("gamectl")
    if system_bin:
        return Path(system_bin)

    raise FileNotFoundError("gamectl: bundled standalone executable not found")


def main() -> None:
    """Entrypoint executing bundled gamectl binary via bash."""
    try:
        bin_path = get_bundled_bin()
    except FileNotFoundError as err:
        sys.stderr.write(f"Error: {err}\n")
        sys.exit(1)

    # Ensure executable permissions
    if not os.access(bin_path, os.X_OK):
        try:
            bin_path.chmod(bin_path.stat().st_mode | 0o755)
        except OSError:
            pass

    # Delegate directly to bash, replacing current process
    try:
        os.execvp("bash", ["bash", str(bin_path), *sys.argv[1:]])
    except FileNotFoundError:
        sys.stderr.write("gamectl: 'bash' executable required but not found in PATH\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
