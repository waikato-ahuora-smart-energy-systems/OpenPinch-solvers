# Pinned sources for the solver build. Sourced by build_ipopt.sh.
#
# Every archive is checked against its SHA-256 before it is unpacked. To move
# to a new release, update the version, URL and checksum together, then update
# the licence files in licenses/ if the upstream licence text changed.

# Ipopt, the interior point NLP solver (EPL-2.0).
IPOPT_VERSION=3.14.20
IPOPT_URL="https://github.com/coin-or/Ipopt/archive/refs/tags/releases/${IPOPT_VERSION}.tar.gz"
IPOPT_SHA256=43bddd6fa793b1694aa94d6129fe3e4a8d452d97a84ef5f2ff721c8047c75605

# COIN-OR build system for MUMPS (EPL-2.0) and the MUMPS sources it patches.
THIRDPARTY_MUMPS_VERSION=3.0.14
THIRDPARTY_MUMPS_URL="https://github.com/coin-or-tools/ThirdParty-Mumps/archive/refs/tags/releases/${THIRDPARTY_MUMPS_VERSION}.tar.gz"
THIRDPARTY_MUMPS_SHA256=49c2773de7b34dea0152b1894da7634cb8319605a9e05b0d9bbc29746acb247c

# MUMPS, the sparse direct linear solver (CeCILL-C). The version must match
# mumps_ver in ThirdParty-Mumps's get.Mumps; build_ipopt.sh checks this.
MUMPS_VERSION=5.9.1
MUMPS_URL="https://coin-or-tools.github.io/ThirdParty-Mumps/MUMPS_${MUMPS_VERSION}.tar.gz"
MUMPS_SHA256=659c9b57646b5a003ac618baa1faf9dd2044e46c732b3daaccbc7158003e1b46

# COIN-OR build system for the AMPL Solver Library (EPL-2.0) and the ASL
# sources it builds. The ASL snapshot must match coinasl in get.ASL.
THIRDPARTY_ASL_VERSION=2.1.0
THIRDPARTY_ASL_URL="https://github.com/coin-or-tools/ThirdParty-ASL/archive/refs/tags/releases/${THIRDPARTY_ASL_VERSION}.tar.gz"
THIRDPARTY_ASL_SHA256=633e9d42b015a5a6a9ae324cac5736af1605fb74eb18299a54912b67d1a69be7
ASL_SNAPSHOT=solvers-20241108
ASL_URL="https://coin-or-tools.github.io/ThirdParty-ASL/${ASL_SNAPSHOT}.tgz"
ASL_SHA256=7ffe7541a5b1a347124f909a0e260c1784f698b78ff24b145d0b11be635292e5

# OpenBLAS, BLAS and LAPACK for Linux and Windows (BSD-3-Clause). macOS uses
# the Accelerate framework instead.
OPENBLAS_VERSION=0.3.34
OPENBLAS_URL="https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/OpenBLAS-${OPENBLAS_VERSION}.tar.gz"
OPENBLAS_SHA256=cd7e129868320cc2d033afa920e31202dfe0b8066a5b66661900ccc0f197dfed

# gfortran for macOS: conda-forge's GCC packaged by isuruf/gcc, the toolchain
# SciPy and NumPy have used for their macOS wheels. Its runtime libraries
# target macOS 10.13 (x86_64) and 11.0 (arm64), so wheels keep a low
# deployment target. delocate bundles libgfortran into the wheel.
MACOS_GFORTRAN_VERSION=15.2.0
MACOS_GFORTRAN_URL_ARM64="https://github.com/isuruf/gcc/releases/download/gcc-${MACOS_GFORTRAN_VERSION}/gfortran-darwin-arm64-native.tar.gz"
MACOS_GFORTRAN_SHA256_ARM64=999a91eef894d32f99e3b641520bef9f475055067f301f0f1947b8b716b5922a
MACOS_GFORTRAN_URL_X86_64="https://github.com/isuruf/gcc/releases/download/gcc-${MACOS_GFORTRAN_VERSION}/gfortran-darwin-x86_64-native.tar.gz"
MACOS_GFORTRAN_SHA256_X86_64=fb03c1f37bf0258ada6e3e41698e3ad416fff4dad448fd746e01d8ccf1efdc0f
