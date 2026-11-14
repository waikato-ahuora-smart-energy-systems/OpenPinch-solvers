#!/usr/bin/env bash
# Build the Ipopt executable from pinned sources.
#
#   OpenBLAS (Linux, Windows) or Accelerate (macOS)  -> BLAS and LAPACK
#   ThirdParty-Mumps + MUMPS                         -> linear solver
#   ThirdParty-ASL + ASL                             -> .nl file interface
#   Ipopt                                            -> bin/ipopt
#
# All libraries are built static and linked into one executable, so the only
# shared libraries it needs are the Fortran runtime (libgfortran and friends)
# and the system libraries. The wheel repair step (auditwheel or delocate) or,
# on Windows, this script copies the runtime next to the executable.
#
# Runs on manylinux (inside cibuildwheel's container), on macOS, and on
# Windows in an MSYS2 UCRT64 shell (see msys2.py).
#
# Environment:
#   OPENPINCH_SOLVERS_PREFIX  install prefix (default: <repo>/build/prefix)
#   OPENPINCH_SOLVERS_WORK    work directory (default: <repo>/build/work)
#   OPENPINCH_SOLVERS_JOBS    parallel make jobs (default: CPU count)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
# shellcheck source=sources.sh
source "$here/sources.sh"

prefix="${OPENPINCH_SOLVERS_PREFIX:-$root/build/prefix}"
work="${OPENPINCH_SOLVERS_WORK:-$root/build/work}"
downloads="$work/downloads"
mkdir -p "$prefix" "$downloads"
prefix="$(cd "$prefix" && pwd)"
work="$(cd "$work" && pwd)"

case "$(uname -s)" in
  Linux) platform=linux ;;
  Darwin) platform=macos ;;
  MINGW* | MSYS* | UCRT* | CLANG*) platform=windows ;;
  *) echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac
arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=$([ "$platform" = macos ] && echo arm64 || echo aarch64) ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

if [ -n "${OPENPINCH_SOLVERS_JOBS:-}" ]; then
  jobs="$OPENPINCH_SOLVERS_JOBS"
elif command -v nproc > /dev/null; then
  jobs="$(nproc)"
else
  jobs="$(sysctl -n hw.ncpu)"
fi

exe_name=ipopt
[ "$platform" = windows ] && exe_name=ipopt.exe

# A finished build records what it was built from, so a rerun is a no-op.
fingerprint="$(cat "$here/sources.sh" "$here/build_ipopt.sh" | cksum | cut -d' ' -f1)-$platform-$arch"
if [ -x "$prefix/bin/$exe_name" ] && [ "$(cat "$prefix/.openpinch-solvers-build" 2> /dev/null)" = "$fingerprint" ]; then
  echo "Ipopt $IPOPT_VERSION is already built in $prefix"
  exit 0
fi

log() { printf '\n==> %s\n' "$*"; }

sha256_of() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# fetch NAME URL SHA256: download into $downloads and verify the checksum.
fetch() {
  local file="$downloads/$1"
  if [ ! -f "$file" ] || [ "$(sha256_of "$file")" != "$3" ]; then
    log "Downloading $1"
    curl -sSfL --retry 5 --retry-delay 5 -o "$file.part" "$2"
    mv "$file.part" "$file"
  fi
  local actual
  actual="$(sha256_of "$file")"
  if [ "$actual" != "$3" ]; then
    echo "Checksum mismatch for $1: expected $3, got $actual" >&2
    exit 1
  fi
}

# unpack NAME DEST: extract a verified archive into a fresh DEST whose top
# level is the archive's single top-level directory.
unpack() {
  rm -rf "$2" "$2.tmp"
  mkdir -p "$2.tmp"
  tar -xzf "$downloads/$1" -C "$2.tmp"
  mv "$2.tmp"/* "$2"
  rmdir "$2.tmp"
}

# ---------------------------------------------------------------- toolchain

if [ "$platform" = linux ]; then
  # manylinux images ship gcc, g++ and gfortran from gcc-toolset. Install
  # the few build tools that are not always present.
  missing=()
  command -v gfortran > /dev/null || missing+=(gcc-gfortran)
  command -v patch > /dev/null || missing+=(patch)
  command -v perl > /dev/null || missing+=(perl)
  command -v pkg-config > /dev/null || missing+=(pkgconf-pkg-config)
  if [ "${#missing[@]}" -gt 0 ]; then
    log "Installing ${missing[*]}"
    if command -v dnf > /dev/null; then
      dnf install -y "${missing[@]}"
    else
      yum install -y "${missing[@]}"
    fi
  fi
  export CC=gcc CXX=g++ F77=gfortran FC=gfortran
  # Static OpenBLAS uses pthread locks; the Fortran runtime comes from
  # libgfortran, which auditwheel bundles.
  lapack_lflags="-L$prefix/lib -lopenblas -lgfortran -lpthread -lm"
elif [ "$platform" = macos ]; then
  if [ "$arch" = arm64 ]; then
    gf_url="$MACOS_GFORTRAN_URL_ARM64" gf_sha="$MACOS_GFORTRAN_SHA256_ARM64"
  else
    gf_url="$MACOS_GFORTRAN_URL_X86_64" gf_sha="$MACOS_GFORTRAN_SHA256_X86_64"
  fi
  gf_archive="gfortran-darwin-$arch-native-$MACOS_GFORTRAN_VERSION.tar.gz"
  fetch "$gf_archive" "$gf_url" "$gf_sha"
  if [ ! -x "$work/gfortran/bin/gfortran" ]; then
    log "Unpacking gfortran $MACOS_GFORTRAN_VERSION"
    unpack "$gf_archive" "$work/gfortran"
  fi
  export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
  export CC=clang CXX=clang++ F77="$work/gfortran/bin/gfortran" FC="$work/gfortran/bin/gfortran"
  # Keep the deployment target cibuildwheel sets; fall back to the runtime's.
  if [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    export MACOSX_DEPLOYMENT_TARGET=$([ "$arch" = arm64 ] && echo 11.0 || echo 10.13)
  fi
  # The Fortran runtime is not in the MUMPS link flags, and clang++ links
  # the executable, so name it here.
  gf_lib="$work/gfortran/lib"
  lapack_lflags="-framework Accelerate -L$gf_lib -lgfortran -lquadmath"
  # The rpath lets the executable (and delocate) find
  # @rpath/libgfortran.5.dylib; the header padding leaves delocate room to
  # rewrite the install names.
  export LDFLAGS="-Wl,-headerpad_max_install_names -Wl,-rpath,$gf_lib${LDFLAGS:+ $LDFLAGS}"
  "$F77" --version | head -n1
else
  export CC=gcc CXX=g++ F77=gfortran FC=gfortran
  lapack_lflags="-L$prefix/lib -lopenblas -lgfortran"
fi

log "Building Ipopt $IPOPT_VERSION for $platform-$arch with $jobs jobs into $prefix"
"$CC" --version | head -n1
"$CXX" --version | head -n1

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
configure_common=(--prefix="$prefix" --disable-shared --enable-static --disable-dependency-tracking)

# ----------------------------------------------------------------- OpenBLAS

if [ "$platform" != macos ]; then
  fetch "OpenBLAS-$OPENBLAS_VERSION.tar.gz" "$OPENBLAS_URL" "$OPENBLAS_SHA256"
  src="$work/OpenBLAS"
  unpack "OpenBLAS-$OPENBLAS_VERSION.tar.gz" "$src"
  # Single-threaded and static. DYNAMIC_ARCH picks kernels at run time; the
  # TARGET is the baseline for the common code, so the library runs on any
  # CPU of the architecture, not only the build machine's.
  openblas_opts=(
    CC="$CC" FC="$FC" HOSTCC="$CC"
    USE_THREAD=0 USE_OPENMP=0 USE_LOCKING=1 NO_AFFINITY=1
    NO_SHARED=1 NO_CBLAS=1 NO_LAPACKE=1 BINARY=64 DYNAMIC_ARCH=1
  )
  if [ "$arch" = x86_64 ]; then
    openblas_opts+=(TARGET=PRESCOTT "DYNAMIC_LIST=PRESCOTT NEHALEM SANDYBRIDGE HASWELL SKYLAKEX ZEN")
  else
    openblas_opts+=(TARGET=ARMV8)
  fi
  log "Building OpenBLAS $OPENBLAS_VERSION"
  make -C "$src" -j"$jobs" "${openblas_opts[@]}" libs netlib > "$work/openblas-build.log" 2>&1 || {
    tail -n 100 "$work/openblas-build.log"
    exit 1
  }
  make -C "$src" "${openblas_opts[@]}" PREFIX="$prefix" install > "$work/openblas-install.log" 2>&1 || {
    tail -n 100 "$work/openblas-install.log"
    exit 1
  }
  ls -l "$prefix/lib"/libopenblas*
fi

# --------------------------------------------------------------------- ASL

fetch "ThirdParty-ASL-$THIRDPARTY_ASL_VERSION.tar.gz" "$THIRDPARTY_ASL_URL" "$THIRDPARTY_ASL_SHA256"
fetch "$ASL_SNAPSHOT.tgz" "$ASL_URL" "$ASL_SHA256"
src="$work/ThirdParty-ASL"
unpack "ThirdParty-ASL-$THIRDPARTY_ASL_VERSION.tar.gz" "$src"
grep -q "^coinasl=$ASL_SNAPSHOT\$" "$src/get.ASL" || {
  echo "get.ASL in ThirdParty-ASL $THIRDPARTY_ASL_VERSION does not use $ASL_SNAPSHOT" >&2
  exit 1
}
# What get.ASL does, with the verified archive instead of a fresh download.
tar -xzf "$downloads/$ASL_SNAPSHOT.tgz" -C "$src"
log "Building ASL ($ASL_SNAPSHOT)"
(cd "$src" && ./configure "${configure_common[@]}" && make -j"$jobs" && make install) > "$work/asl.log" 2>&1 || {
  tail -n 100 "$work/asl.log"
  exit 1
}

# ------------------------------------------------------------------- MUMPS

fetch "ThirdParty-Mumps-$THIRDPARTY_MUMPS_VERSION.tar.gz" "$THIRDPARTY_MUMPS_URL" "$THIRDPARTY_MUMPS_SHA256"
fetch "MUMPS_$MUMPS_VERSION.tar.gz" "$MUMPS_URL" "$MUMPS_SHA256"
src="$work/ThirdParty-Mumps"
unpack "ThirdParty-Mumps-$THIRDPARTY_MUMPS_VERSION.tar.gz" "$src"
grep -q "^mumps_ver=$MUMPS_VERSION\$" "$src/get.Mumps" || {
  echo "get.Mumps in ThirdParty-Mumps $THIRDPARTY_MUMPS_VERSION does not use MUMPS $MUMPS_VERSION" >&2
  exit 1
}
# What get.Mumps does, with the verified archive instead of a fresh download.
(
  cd "$src"
  tar -xzf "$downloads/MUMPS_$MUMPS_VERSION.tar.gz"
  mv "MUMPS_$MUMPS_VERSION" MUMPS
  patch -p0 < mumps_mpi.patch
  mv MUMPS/libseq/mpi.h MUMPS/libseq/mumps_mpi.h
  patch -p0 < mumps_call.patch
  patch -p0 < mumps_stdalign.patch
)
log "Building MUMPS $MUMPS_VERSION"
(
  cd "$src" &&
    ./configure "${configure_common[@]}" --without-metis --with-lapack-lflags="$lapack_lflags" &&
    make -j"$jobs" && make install
) > "$work/mumps.log" 2>&1 || {
  tail -n 150 "$work/mumps.log"
  exit 1
}

# ------------------------------------------------------------------- Ipopt

fetch "Ipopt-$IPOPT_VERSION.tar.gz" "$IPOPT_URL" "$IPOPT_SHA256"
src="$work/Ipopt"
unpack "Ipopt-$IPOPT_VERSION.tar.gz" "$src"
log "Building Ipopt $IPOPT_VERSION"
(
  mkdir -p "$src/build" && cd "$src/build" &&
    ../configure "${configure_common[@]}" \
      --with-lapack-lflags="$lapack_lflags" \
      --without-hsl --without-spral --disable-pardisomkl \
      --disable-java --disable-sipopt &&
    make -j"$jobs" && make install
) > "$work/ipopt.log" 2>&1 || {
  tail -n 150 "$work/ipopt.log"
  exit 1
}
grep -E "checking for package (Mumps|ASL|Lapack|HSL)|Lapack" "$src/build/config.log" | grep -i "result" | head -n 20 || true

exe="$prefix/bin/$exe_name"
test -x "$exe"

# ------------------------------------------------------- runtime libraries

if [ "$platform" = windows ]; then
  # Windows finds DLLs in the executable's own directory first, and a Python
  # wheel cannot add to the search path of a separate process. So the MinGW
  # runtime DLLs ipopt.exe needs are copied next to it here. delvewheel
  # only patches extension modules, so it has nothing left to do.
  mingw_bin="$(dirname "$(command -v gcc)")"
  queue=("$exe")
  declare -A seen=()
  while [ "${#queue[@]}" -gt 0 ]; do
    file="${queue[0]}"
    queue=("${queue[@]:1}")
    while read -r dll; do
      key="${dll,,}"
      [ -n "${seen[$key]:-}" ] && continue
      seen[$key]=1
      if [ -f "$mingw_bin/$dll" ]; then
        cp "$mingw_bin/$dll" "$prefix/bin/"
        queue+=("$mingw_bin/$dll")
        echo "Bundled $dll"
      fi
    done < <(objdump -p "$file" | sed -n 's/^\s*DLL Name: //p' | tr -d '\r')
  done
  strip "$exe"
elif [ "$platform" = macos ]; then
  strip "$exe"
  codesign --force --sign - "$exe"
else
  strip "$exe"
fi

# ------------------------------------------------- runtime library sources
#
# The wheel ships the compiler's runtime libraries (GPL-3.0 with the GCC
# Runtime Library Exception, LGPL-2.1 for libquadmath). Record exactly which
# packages they came from and where their source is, so the release can
# attach that source. scripts/collect_sources.sh reads this manifest from
# each wheel. Columns: description, libraries, source URL, SHA-256 ("-" when
# the distribution publishes no checksum we can pin in advance).

manifest="$prefix/share/openpinch-solvers/runtime-sources.tsv"
mkdir -p "$(dirname "$manifest")"
: > "$manifest"
record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$manifest"; }

if [ "$platform" = linux ]; then
  # auditwheel bundles the libraries outside the manylinux allow-list; of
  # those ipopt needs only libgfortran and libquadmath (x86_64).
  ldd "$exe" | awk '$3 ~ /^\// {print $3}' | while read -r lib; do
    case "$(basename "$lib")" in libgfortran* | libquadmath*) ;; *) continue ;; esac
    srpm="$(rpm -qf --qf '%{SOURCERPM}' "$lib")"
    url="$(dnf -q --enablerepo=baseos-source --enablerepo=appstream-source \
      repoquery --location --arch=src "${srpm%.src.rpm}" | head -n1 | sed 's#^http://#https://#')"
    if [ -z "$url" ]; then
      echo "Could not find the source package $srpm of $lib" >&2
      exit 1
    fi
    record "AlmaLinux 8 source package $srpm" "$(basename "$lib")" "$url" -
  done
elif [ "$platform" = macos ]; then
  libs="libgfortran.5.dylib libquadmath.0.dylib libgcc_s.1.1.dylib"
  record "GCC $MACOS_GCC_SOURCE_VERSION, built by conda-forge as libgfortran5 (gfortran $MACOS_GFORTRAN_VERSION from isuruf/gcc)" \
    "$libs" "$MACOS_GCC_SOURCE_URL" "$MACOS_GCC_SOURCE_SHA256"
  record "conda-forge recipe and patches used for that build" \
    "$libs" "$MACOS_GCC_RECIPE_URL" "$MACOS_GCC_RECIPE_SHA256"
else
  db=/var/lib/pacman/local
  for dll in "$prefix"/bin/*.dll; do
    name="$(basename "$dll")"
    owner="$(pacman -Qqo "$mingw_bin/$name")"
    version="$(pacman -Q "$owner" | cut -d' ' -f2)"
    base="$(sed -n '/^%BASE%$/{n;p;}' "$db/$owner-$version/desc")"
    record "MSYS2 source package $base $version" "$name" \
      "https://repo.msys2.org/mingw/sources/$base-$version.src.tar.zst" -
  done
fi
echo "Runtime library sources:"
cat "$manifest"

log "Built $exe"
ls -l "$prefix/bin"
case "$platform" in
  linux) ldd "$exe" ;;
  macos) otool -L "$exe" ;;
  windows) objdump -p "$exe" | grep "DLL Name" ;;
esac
"$exe" -v

echo "$fingerprint" > "$prefix/.openpinch-solvers-build"
