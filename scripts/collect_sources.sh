#!/usr/bin/env bash
# Collect the source code of everything in the release's wheels.
#
#   scripts/collect_sources.sh WHEEL_DIR OUT_DIR
#
# Downloads into OUT_DIR, checking every pinned SHA-256:
#   - the solver sources pinned in sources.sh (Ipopt, ThirdParty-Mumps, MUMPS,
#     ThirdParty-ASL, the ASL, OpenBLAS);
#   - the source of the compiler runtime libraries bundled in each wheel, as
#     listed in the wheel's openpinch_solvers/runtime-sources.tsv.
# Then writes SOURCES.md (what each archive is and which wheels use it) and
# SHA256SUMS. The release workflow attaches all of it to the GitHub release,
# which is where the licences (EPL-2.0, CeCILL-C, GPL-3.0, LGPL-2.1) ask the
# corresponding source to be offered.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 WHEEL_DIR OUT_DIR" >&2
  exit 2
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sources.sh
source "$here/sources.sh"
wheels="$1"
out="$2"
mkdir -p "$out"

sha256_of() {
  if command -v sha256sum > /dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Rows of: file name, description, used by, URL, expected SHA-256 or "-",
# bundled libraries built from it ("-" for the solver sources).
rows="$(mktemp)"
trap 'rm -f "$rows"' EXIT
add() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "${6:--}" >> "$rows"; }

all="all wheels"
add "Ipopt-$IPOPT_VERSION.tar.gz" "Ipopt $IPOPT_VERSION (EPL-2.0)" "$all" "$IPOPT_URL" "$IPOPT_SHA256"
add "ThirdParty-Mumps-$THIRDPARTY_MUMPS_VERSION.tar.gz" "ThirdParty-Mumps $THIRDPARTY_MUMPS_VERSION build system and patches (EPL-2.0)" "$all" "$THIRDPARTY_MUMPS_URL" "$THIRDPARTY_MUMPS_SHA256"
add "MUMPS_$MUMPS_VERSION.tar.gz" "MUMPS $MUMPS_VERSION (CeCILL-C)" "$all" "$MUMPS_URL" "$MUMPS_SHA256"
add "ThirdParty-ASL-$THIRDPARTY_ASL_VERSION.tar.gz" "ThirdParty-ASL $THIRDPARTY_ASL_VERSION build system (EPL-2.0)" "$all" "$THIRDPARTY_ASL_URL" "$THIRDPARTY_ASL_SHA256"
add "$ASL_SNAPSHOT.tgz" "AMPL Solver Library $ASL_SNAPSHOT (permissive notice)" "$all" "$ASL_URL" "$ASL_SHA256"
add "OpenBLAS-$OPENBLAS_VERSION.tar.gz" "OpenBLAS $OPENBLAS_VERSION with reference LAPACK (BSD-3-Clause)" "Linux and Windows wheels" "$OPENBLAS_URL" "$OPENBLAS_SHA256"

found=0
for wheel in "$wheels"/*.whl; do
  [ -f "$wheel" ] || continue
  found=$((found + 1))
  name="$(basename "$wheel")"
  tag="${name##*-}"
  tag="${tag%.whl}"
  if ! unzip -p "$wheel" openpinch_solvers/runtime-sources.tsv > /dev/null 2>&1; then
    echo "$name has no openpinch_solvers/runtime-sources.tsv" >&2
    exit 1
  fi
  while IFS=$'\t' read -r description libraries url sha; do
    [ -n "$url" ] || continue
    file="$(basename "${url%%\?*}")"
    # GitHub archive names are bare commit hashes; make them recognisable.
    case "$url" in
      https://github.com/*/archive/*) file="$(echo "$url" | cut -d/ -f5)-$file" ;;
    esac
    add "$file" "$description" "$tag" "$url" "$sha" "$libraries"
  done < <(unzip -p "$wheel" openpinch_solvers/runtime-sources.tsv)
done
if [ "$found" -eq 0 ]; then
  echo "No wheels in $wheels" >&2
  exit 1
fi

# Download each distinct file once and verify it.
cut -f1,4,5 "$rows" | sort -u | while IFS=$'\t' read -r file url sha; do
  dest="$out/$file"
  if [ ! -f "$dest" ] || { [ "$sha" != - ] && [ "$(sha256_of "$dest")" != "$sha" ]; }; then
    echo "Downloading $url"
    curl -sSfL --retry 5 --retry-delay 10 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  if [ "$sha" != - ] && [ "$(sha256_of "$dest")" != "$sha" ]; then
    echo "Checksum mismatch for $file from $url" >&2
    exit 1
  fi
done

{
  echo "# Source code of openpinch-solvers $(sed -n 's/^__version__ = "\(.*\)"$/\1/p' "$here/../src/openpinch_solvers/__init__.py")"
  echo
  echo "Corresponding source for every third-party component in this release's"
  echo "wheels. The build scripts that turn it into the wheels are in the"
  echo "repository at the release tag (scripts/build_ipopt.sh)."
  echo
  echo "| File | What it is | Bundled libraries built from it | Wheels | Original URL |"
  echo "| --- | --- | --- | --- | --- |"
  cut -f1 "$rows" | awk '!seen[$0]++' | while read -r file; do
    # Every distinct value of column $1 among this file's rows, joined.
    values() { awk -F'\t' -v f="$file" -v c="$1" '$1 == f {print $c}' "$rows" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | paste -sd, - | sed 's/,/, /g'; }
    description="$(awk -F'\t' -v f="$file" '$1 == f {print $2}' "$rows" | awk '!seen[$0]++' | paste -sd';' - | sed 's/;/; /g')"
    url="$(awk -F'\t' -v f="$file" '$1 == f {print $4; exit}' "$rows")"
    users="$(awk -F'\t' -v f="$file" '$1 == f {print $3}' "$rows" | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')"
    libraries="$(values 6 | sed 's/^-$//')"
    echo "| \`$file\` | $description | ${libraries:--} | $users | $url |"
  done
} > "$out/SOURCES.md"

(cd "$out" && rm -f SHA256SUMS && for f in *; do [ "$f" = SHA256SUMS ] || printf '%s  %s\n' "$(sha256_of "$f")" "$f"; done > SHA256SUMS)
echo
cat "$out/SOURCES.md"
echo
ls -l "$out"
