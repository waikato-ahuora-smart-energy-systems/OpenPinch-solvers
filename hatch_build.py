"""Hatchling build hook: put the built solver into a platform wheel.

scripts/build_ipopt.sh installs Ipopt into ``build/prefix`` (or
``$OPENPINCH_SOLVERS_PREFIX``). This hook copies the executable, plus any
DLLs the build script placed next to it on Windows, into
``openpinch_solvers/bin`` and tags the wheel ``py3-none-<platform>``: the
executable does not depend on the Python version, so one wheel per platform
serves every Python 3 version.
"""

from __future__ import annotations

import os
import sysconfig
from pathlib import Path

from hatchling.builders.hooks.plugin.interface import BuildHookInterface


class SolverBuildHook(BuildHookInterface):
    PLUGIN_NAME = "openpinch-solvers"

    def initialize(self, version: str, build_data: dict) -> None:
        if self.target_name != "wheel":
            return
        if version == "editable":
            raise RuntimeError("openpinch-solvers does not support editable installs.")

        prefix = Path(os.environ.get("OPENPINCH_SOLVERS_PREFIX", Path(self.root) / "build" / "prefix"))
        windows = os.name == "nt"
        exe = prefix / "bin" / ("ipopt.exe" if windows else "ipopt")
        if not exe.is_file():
            raise RuntimeError(
                f"{exe} does not exist. Run scripts/build_ipopt.sh (on Windows: "
                "python scripts/msys2.py scripts/build_ipopt.sh) before building the wheel."
            )

        files = [exe]
        if windows:
            files += sorted(p for p in (prefix / "bin").glob("*.dll"))
        for path in files:
            build_data["force_include"][str(path)] = f"openpinch_solvers/bin/{path.name}"

        # Where the source of the bundled compiler runtime libraries is.
        manifest = prefix / "share" / "openpinch-solvers" / "runtime-sources.tsv"
        if not manifest.is_file():
            raise RuntimeError(f"{manifest} does not exist; rerun scripts/build_ipopt.sh.")
        build_data["force_include"][str(manifest)] = "openpinch_solvers/runtime-sources.tsv"

        build_data["pure_python"] = False
        build_data["tag"] = f"py3-none-{_platform_tag()}"


def _platform_tag() -> str:
    # cibuildwheel sets _PYTHON_HOST_PLATFORM on macOS, so this reflects the
    # deployment target and architecture of the build; the repair step then
    # turns linux_* into manylinux_* and checks the macOS tag.
    return sysconfig.get_platform().replace("-", "_").replace(".", "_")
