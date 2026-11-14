"""Console entry points that forward to the bundled executables."""

from __future__ import annotations

import os
import subprocess
import sys

from . import ipopt_executable


def _run(executable: str) -> int:
    args = [executable, *sys.argv[1:]]
    if os.name == "nt":
        # Windows has no exec that keeps the console process; wait instead.
        try:
            return subprocess.call(args)
        except KeyboardInterrupt:
            return 130
    os.execv(executable, args)
    return 1  # unreachable


def ipopt() -> None:
    """Run the bundled ``ipopt`` with this process's arguments."""
    sys.exit(_run(ipopt_executable()))
