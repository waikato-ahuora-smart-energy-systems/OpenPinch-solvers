"""Tests run against every built wheel (cibuildwheel's test step)."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import sysconfig
from pathlib import Path

import pytest

import openpinch_solvers

EXPECTED_IPOPT = "3.14.20"


def _clean_env() -> dict[str, str]:
    """An environment without toolchain paths, so the executable must find
    its runtime libraries inside the installed wheel."""
    env = {k: v for k, v in os.environ.items() if k not in {"LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH"}}
    if os.name == "nt":
        system_root = os.environ.get("SystemRoot", r"C:\Windows")
        env["PATH"] = os.pathsep.join([str(Path(system_root) / "System32"), system_root])
    else:
        env["PATH"] = "/usr/bin:/bin"
    return env


def _run_ipopt(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [openpinch_solvers.ipopt_executable(), *args],
        capture_output=True,
        text=True,
        env=_clean_env(),
        timeout=120,
        check=False,
    )


def test_executable_is_inside_the_package():
    exe = Path(openpinch_solvers.ipopt_executable())
    assert exe.is_file()
    assert exe.parent == Path(openpinch_solvers.bin_directory)
    assert Path(openpinch_solvers.__file__).resolve().parent in exe.parents


@pytest.mark.parametrize("flag", ["--version", "-v"])
def test_version(flag):
    result = _run_ipopt(flag)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert re.search(rf"\bIpopt {re.escape(EXPECTED_IPOPT)}\b", output), output
    assert f"ASL({openpinch_solvers.ASL_VERSION})" in output, output
    assert openpinch_solvers.IPOPT_VERSION == EXPECTED_IPOPT


def test_console_entry_point():
    scripts = Path(sysconfig.get_path("scripts"))
    candidates = [scripts / "ipopt", scripts / "ipopt.exe"]
    wrapper = next((p for p in candidates if p.is_file()), None)
    assert wrapper is not None, f"no ipopt entry point in {scripts}"
    result = subprocess.run([str(wrapper), "-v"], capture_output=True, text=True, timeout=120, check=False)
    assert result.returncode == 0, result.stdout + result.stderr
    assert EXPECTED_IPOPT in result.stdout + result.stderr


def test_runtime_libraries_are_bundled():
    """Every non-system shared library the executable loads comes from the
    installed wheel, not from the build machine."""
    exe = openpinch_solvers.ipopt_executable()
    site = Path(openpinch_solvers.__file__).resolve().parents[1]
    if sys.platform.startswith("linux"):
        out = subprocess.run(["ldd", exe], capture_output=True, text=True, check=True).stdout
        system = re.compile(r"^(linux-vdso|ld-linux|libc|libm|libdl|libpthread|librt|libstdc\+\+|libgcc_s)[.-]")
        for line in out.splitlines():
            line = line.strip()
            if not line or "=>" not in line:
                continue
            name, _, target = line.partition("=>")
            name, target = name.strip(), target.strip().split(" (")[0]
            assert target != "not found", out
            if not system.match(name):
                assert Path(target).resolve().is_relative_to(site), f"{name} loads from {target}\n{out}"
    elif sys.platform == "darwin":
        out = subprocess.run(["otool", "-L", exe], capture_output=True, text=True, check=True).stdout
        for line in out.splitlines()[1:]:
            dep = line.strip().split(" (")[0]
            assert dep.startswith(("/usr/lib/", "/System/", "@loader_path/", "@rpath/", "@executable_path/")), out
    else:
        bundled = {p.name.lower() for p in Path(openpinch_solvers.bin_directory).glob("*.dll")}
        assert any(name.startswith("libgfortran") for name in bundled), bundled


def test_linear_solver_is_mumps(tmp_path):
    pyomo = pytest.importorskip("pyomo.environ")
    model = _hs071(pyomo)
    solver = pyomo.SolverFactory("ipopt", executable=openpinch_solvers.ipopt_executable())
    logfile = tmp_path / "ipopt.log"
    solver.options["linear_solver"] = "mumps"
    solver.options["print_level"] = 5
    solver.options["output_file"] = str(logfile)
    result = solver.solve(model)
    assert result.solver.termination_condition == pyomo.TerminationCondition.optimal
    assert "MUMPS" in logfile.read_text()


def _hs071(pyo):
    """Hock-Schittkowski problem 71, the Ipopt documentation example.

    min x1*x4*(x1 + x2 + x3) + x3
    s.t. x1*x2*x3*x4 >= 25
         x1^2 + x2^2 + x3^2 + x4^2 = 40
         1 <= x1, x2, x3, x4 <= 5
    """
    m = pyo.ConcreteModel()
    start = {1: 1.0, 2: 5.0, 3: 5.0, 4: 1.0}
    m.x = pyo.Var([1, 2, 3, 4], bounds=(1, 5), initialize=start)
    m.obj = pyo.Objective(expr=m.x[1] * m.x[4] * (m.x[1] + m.x[2] + m.x[3]) + m.x[3])
    m.ineq = pyo.Constraint(expr=m.x[1] * m.x[2] * m.x[3] * m.x[4] >= 25)
    m.eq = pyo.Constraint(expr=sum(m.x[i] ** 2 for i in m.x) == 40)
    return m


def test_pyomo_solves_hs071_to_known_optimum():
    pyo = pytest.importorskip("pyomo.environ")
    model = _hs071(pyo)
    solver = pyo.SolverFactory("ipopt", executable=openpinch_solvers.ipopt_executable())
    assert solver.available(exception_flag=False)
    assert solver.version()[:3] == tuple(int(p) for p in EXPECTED_IPOPT.split("."))
    result = solver.solve(model, tee=True)
    assert result.solver.termination_condition == pyo.TerminationCondition.optimal
    assert pyo.value(model.obj) == pytest.approx(17.0140173, abs=1e-6)
    expected = {1: 1.0, 2: 4.7429994, 3: 3.8211503, 4: 1.3794082}
    for i, x in expected.items():
        assert pyo.value(model.x[i]) == pytest.approx(x, abs=1e-5)


def test_pyomo_finds_ipopt_via_add_to_path(monkeypatch):
    pyo = pytest.importorskip("pyomo.environ")
    monkeypatch.setenv("PATH", _clean_env()["PATH"])
    directory = openpinch_solvers.add_to_path()
    assert os.environ["PATH"].split(os.pathsep)[0] == directory
    openpinch_solvers.add_to_path()
    assert os.environ["PATH"].split(os.pathsep).count(directory) == 1
    found = shutil.which("ipopt")
    assert found is not None and Path(found).resolve() == Path(openpinch_solvers.ipopt_executable()).resolve()
    model = _hs071(pyo)
    result = pyo.SolverFactory("ipopt").solve(model)
    assert result.solver.termination_condition == pyo.TerminationCondition.optimal
    assert pyo.value(model.obj) == pytest.approx(17.0140173, abs=1e-6)
