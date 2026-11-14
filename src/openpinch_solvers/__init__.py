"""Solver executables for OpenPinch, shipped as platform wheels.

The wheel contains an ``ipopt`` executable (Ipopt with MUMPS and the AMPL
Solver Library), so Pyomo's ``SolverFactory("ipopt")`` can drive it through
``.nl`` files without IDAES or conda.

>>> import openpinch_solvers
>>> openpinch_solvers.ipopt_executable()  # doctest: +SKIP
'/.../site-packages/openpinch_solvers/bin/ipopt'
>>> openpinch_solvers.add_to_path()  # doctest: +SKIP
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

__all__ = [
    "IPOPT_VERSION",
    "MUMPS_VERSION",
    "ASL_VERSION",
    "BLAS_LAPACK",
    "__version__",
    "add_to_path",
    "bin_directory",
    "ipopt_executable",
]

__version__ = "0.1.0"

#: Version of Ipopt in this wheel.
IPOPT_VERSION = "3.14.20"
#: Version of MUMPS, Ipopt's linear solver, in this wheel.
MUMPS_VERSION = "5.9.1"
#: Snapshot of the AMPL Solver Library that reads Pyomo's ``.nl`` files.
ASL_VERSION = "20241108"
#: BLAS and LAPACK implementation the solver uses on this platform.
BLAS_LAPACK = "Accelerate" if sys.platform == "darwin" else "OpenBLAS 0.3.34"

_EXE_SUFFIX = ".exe" if os.name == "nt" else ""

#: Directory holding the solver executables (an alias in the style of
#: ``idaes.bin_directory``).
bin_directory = str(Path(__file__).resolve().parent / "bin")


def _executable(name: str) -> str:
    path = Path(bin_directory) / f"{name}{_EXE_SUFFIX}"
    if not path.is_file():
        raise FileNotFoundError(
            f"{path} is missing. openpinch-solvers ships {name!r} only in its "
            "platform wheels; reinstall it from a wheel for this platform."
        )
    if not os.access(path, os.X_OK):
        raise PermissionError(f"{path} is not executable.")
    return str(path)


def ipopt_executable() -> str:
    """Return the absolute path of the bundled ``ipopt`` executable.

    Pass it to Pyomo as ``SolverFactory("ipopt", executable=...)``, or call
    :func:`add_to_path` so a plain ``SolverFactory("ipopt")`` finds it.
    """
    return _executable("ipopt")


def add_to_path() -> str:
    """Put the bundled solver directory first on ``PATH`` for this process.

    Child processes, including the ones Pyomo starts, inherit it. Returns the
    directory. Calling it again does not add a second entry.
    """
    directory = bin_directory
    entries = os.environ.get("PATH", "").split(os.pathsep)
    if not entries or os.path.normcase(entries[0]) != os.path.normcase(directory):
        entries = [e for e in entries if os.path.normcase(e) != os.path.normcase(directory)]
        os.environ["PATH"] = os.pathsep.join([directory, *entries])
    return directory
