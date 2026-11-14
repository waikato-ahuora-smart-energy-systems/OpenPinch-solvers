"""Run a bash script in an MSYS2 UCRT64 login shell (Windows build helper).

cibuildwheel runs ``before-all`` through ``cmd.exe`` on Windows. This helper
installs the MinGW-w64 toolchain with pacman and then runs the given script
with the UCRT64 environment, from the current directory.

Usage: python scripts/msys2.py scripts/build_ipopt.sh [args...]
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

PACKAGES = [
    "curl",
    "make",
    "patch",
    "mingw-w64-ucrt-x86_64-gcc",
    "mingw-w64-ucrt-x86_64-gcc-fortran",
    "mingw-w64-ucrt-x86_64-pkgconf",
]


def main() -> int:
    root = Path(os.environ.get("MSYS2_ROOT", r"C:\msys64"))
    bash = root / "usr" / "bin" / "bash.exe"
    if not bash.is_file():
        print(f"MSYS2 bash not found at {bash}; set MSYS2_ROOT.", file=sys.stderr)
        return 1
    env = dict(os.environ, MSYSTEM="UCRT64", CHERE_INVOKING="1", MSYS2_PATH_TYPE="minimal")
    pacman = "pacman -S --needed --noconfirm " + " ".join(PACKAGES)
    subprocess.run([str(bash), "-lc", pacman], env=env, check=True)
    script = Path(sys.argv[1]).as_posix()
    return subprocess.run([str(bash), "-l", script, *sys.argv[2:]], env=env).returncode


if __name__ == "__main__":
    sys.exit(main())
