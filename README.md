# openpinch-solvers

Platform wheels that ship a current [Ipopt](https://github.com/coin-or/Ipopt)
executable, so [OpenPinch](https://github.com/waikato-ahuora-smart-energy-systems/OpenPinch)
can get its nonlinear solver from pip, without IDAES or conda.

```bash
pip install openpinch-solvers
```

```python
import openpinch_solvers
import pyomo.environ as pyo

solver = pyo.SolverFactory("ipopt", executable=openpinch_solvers.ipopt_executable())
```

## What is in the wheel

| Component | Version | Role | Licence |
| --- | --- | --- | --- |
| Ipopt | 3.14.20 | interior point NLP solver, `ipopt` executable | EPL-2.0 |
| MUMPS | 5.9.1 (via ThirdParty-Mumps 3.0.14) | sparse linear solver used by Ipopt | CeCILL-C |
| AMPL Solver Library | 20241108 (via ThirdParty-ASL 2.1.0) | reads Pyomo's `.nl` files, writes `.sol` files | permissive notice |
| OpenBLAS | 0.3.34 (Linux, Windows) | BLAS and LAPACK | BSD-3-Clause |
| Accelerate | system framework (macOS) | BLAS and LAPACK | part of macOS |
| GCC runtime | from the build toolchain | `libgfortran`, `libquadmath`, `libgcc_s` (and on Windows `libstdc++`, `libwinpthread`) | GPL-3.0 with the GCC Runtime Library Exception; LGPL-2.1 for `libquadmath`; MIT and BSD-3-Clause for `winpthreads` |

MUMPS is the only linear solver. The HSL solvers (MA27, MA57 and others) are
not redistributable and are not included; Ipopt's linear solver loader is
enabled, so a user who has an HSL licence can still point Ipopt at their own
`libhsl` with the `hsllib` option.

Wheels are built for:

- Linux x86_64 and aarch64 (`manylinux_2_28`, glibc 2.28 or newer)
- macOS arm64 (11.0 or newer) and x86_64 (10.13 or newer)
- Windows x86_64

Each wheel is tagged `py3-none-<platform>`: the executable does not depend on
the Python version, so one wheel serves Python 3.10 and newer. There is no
source distribution; building from source needs the toolchain described in
[Building](#building).

## Python API

- `openpinch_solvers.ipopt_executable()` returns the absolute path of the
  bundled `ipopt` executable. It raises `FileNotFoundError` if the package was
  not installed from a platform wheel.
- `openpinch_solvers.bin_directory` is the directory that holds it (named
  like `idaes.bin_directory`).
- `openpinch_solvers.add_to_path()` puts that directory first on `PATH` for
  the current process and its children, so a plain `SolverFactory("ipopt")`
  finds the bundled executable.
- `IPOPT_VERSION`, `MUMPS_VERSION`, `ASL_VERSION` and `BLAS_LAPACK` describe
  the bundled build.

The wheel also installs an `ipopt` console command. It is a small Python
launcher that runs the bundled executable with the same arguments, so
`ipopt -v` works in an activated environment. Code that starts the solver
many times should use `ipopt_executable()` or `add_to_path()` instead,
which run the executable directly without starting Python first.

## How OpenPinch uses it

OpenPinch's heat exchanger network synthesis solves Pyomo models. Ipopt is
the default solver for network evolution and duty optimisation. Before this
package, Ipopt came only from IDAES's `idaes get-extensions` download, which
ships Ipopt 3.13.2 from 2020.

OpenPinch's `synthesis` extra is planned to depend on `openpinch-solvers`.
OpenPinch looks for a solver executable on `PATH` first and then in IDAES's
`bin_directory`, which it prepends to `PATH` so Pyomo's
`SolverFactory("ipopt")` finds it. With this package installed it checks
`openpinch_solvers.bin_directory` in the same way, which is the same as:

```python
import openpinch_solvers

openpinch_solvers.add_to_path()
```

## Building

The wheels are built by [cibuildwheel](https://cibuildwheel.pypa.io) on
GitHub Actions (`.github/workflows/wheels.yml`). Its `before-all` step runs
`scripts/build_ipopt.sh`, which downloads the sources listed in
`scripts/sources.sh`, checks each SHA-256, and builds, all as static
libraries linked into one executable:

1. OpenBLAS (single-threaded, `DYNAMIC_ARCH` with a baseline target, so it
   runs on any CPU of the architecture) on Linux and Windows; Accelerate on
   macOS.
2. The ASL, through ThirdParty-ASL.
3. MUMPS (sequential, with its built-in AMD and PORD orderings, no METIS),
   through ThirdParty-Mumps and its patches.
4. Ipopt, with MUMPS and the ASL.

Toolchains: the `manylinux_2_28` image's GCC and gfortran on Linux; Apple
clang and conda-forge's gfortran 15.2 (from
[isuruf/gcc](https://github.com/isuruf/gcc/releases), pinned by checksum) on
macOS; MSYS2's UCRT64 MinGW-w64 GCC and gfortran on Windows.

The hatchling build hook (`hatch_build.py`) copies the executable into
`openpinch_solvers/bin` and tags the wheel. The repair step then bundles the
Fortran runtime: `auditwheel` on Linux and `delocate` on macOS. On Windows
the build script copies the MinGW runtime DLLs next to `ipopt.exe`, where
Windows looks for them; `delvewheel` only patches extension modules, so it
is not used. The tests in `tests/` run against every wheel: they check
`ipopt --version`, that the runtime libraries come from the wheel, that MUMPS
is the linear solver, and that Pyomo solves Hock-Schittkowski problem 71 to
its known optimum.

To build locally on Linux or macOS:

```bash
bash scripts/build_ipopt.sh
```

```bash
python -m build --wheel
```

On Windows, run `python scripts/msys2.py scripts/build_ipopt.sh` with MSYS2
installed in `C:\msys64` (or set `MSYS2_ROOT`).

## Releasing

Bump `__version__` in `src/openpinch_solvers/__init__.py`, merge to `main`,
then push a tag `v<version>` on that commit. `.github/workflows/release.yml`
checks the tag, builds and tests the wheels, publishes them to PyPI through
trusted publishing, and creates a GitHub release with the wheels attached.

The PyPI side needs a one-time setup: a trusted publisher for the project
`openpinch-solvers` with owner `waikato-ahuora-smart-energy-systems`,
repository `openpinch-solvers`, workflow `release.yml` and environment `pypi`
(a "pending publisher" before the first release), and a `pypi` environment
in the repository settings.

To update a solver, change its version, URL and checksum in
`scripts/sources.sh`, the matching constant in `src/openpinch_solvers/__init__.py`,
`EXPECTED_IPOPT` in the tests for Ipopt, and the licence files if they
changed.

## Licences

The Python code and build scripts in this repository are MIT licensed (see
`LICENSE`), the same as OpenPinch. The wheels also contain the third-party
components in the table above, under their own licences. Their texts are in
`licenses/` and are installed in each wheel's `.dist-info/licenses/`
directory:

- `EPL-2.0.txt`: Ipopt, ThirdParty-Mumps and ThirdParty-ASL.
- `MUMPS-LICENSE.txt`, `MUMPS-CeCILL-C-V1-en.txt`, `MUMPS-PORD-README.txt`:
  MUMPS (CeCILL-C; BSD-3-Clause parts derived from LAPACK; PORD is public
  domain).
- `ASL-NOTICE.txt`: the AMPL Solver Library notices (AMPL Optimization and
  Lucent Technologies).
- `OpenBLAS-LICENSE.txt`, `GotoBLAS-LICENSE.txt`, `LAPACK-LICENSE.txt`:
  OpenBLAS and the reference LAPACK it contains.
- `GPL-3.0.txt`, `GCC-RUNTIME-EXCEPTION-3.1.txt`: the GCC runtime libraries.
- `LGPL-2.1.txt`: `libquadmath` (x86_64 builds), shipped as a separate shared
  library.
- `winpthreads-COPYING.txt`: `libwinpthread` (Windows).

The sources of every component are available at the URLs pinned in
`scripts/sources.sh`.
