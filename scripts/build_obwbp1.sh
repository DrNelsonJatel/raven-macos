#!/usr/bin/env bash
# Build the OBWB-patched Raven v4.12 macOS binary (decisions D104, D105, 2026-10-15) into a NEW dist folder, leaving
# dist/raven-v4.12-macos-arm64 (the unmodified reference build) untouched.
#
# The patch: patches/OBWB_RavenPatch_v1_20261015.diff (src/Reservoir.cpp only; source of record
# Okanagan-Basin-Water-Board/mission-creek-mass-balance docs/OBWB_RavenPatch_v1_20261015.diff, checked by sha256 below). A control-structure
# flow sent to a non-downstream target is booked in full in the reservoir mass balance. Same compiler profile as build.sh
# 'reference' (-O0), same CMake options, same bundling and signing.
#
# D105: the working source tree src/ stays at upstream 81011f0 and is NEVER modified. The tracked files of src/ at that
# commit are exported to a temporary directory (git archive, read-only), the patch is applied there, and the build runs
# there. Checks prove that the compiled Reservoir.cpp is the patched file (sha256 and 13 markers), that src/ is clean
# before and after, and that the binary equals the D104 binary (sha256 b89340f2...).
#
# Usage:  bash scripts/build_obwbp1.sh
#         OBWBP1_OUT=<new dir> bash scripts/build_obwbp1.sh     (verification build elsewhere; the folder must not exist)
#
# Known (D106(3)): a rebuild outside the original build path links with a 0x28-byte layout shift, so the final binary
# sha256 check FLAGs although the normalised disassembly is identical (0 of 481,666 lines differ). The D104 binary
# b89340f2... remains the reference; a FLAG on that line alone is expected for rebuilds elsewhere.
# Output: dist/raven-v4.12-obwbp1-macos-arm64/ by default (no tarball). Refuses to overwrite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
PATCH="${OBWBP1_PATCH:-$ROOT/patches/OBWB_RavenPatch_v1_20261015.diff}"   # copy of mission-creek-mass-balance/docs/OBWB_RavenPatch_v1_20261015.diff
PATCH_SHA="57cf1db55963356e2d45b2b235b94b98709a2013d0ce88153a67ac10cec59a4e"
PATCHED_FILE_SHA="609c609df3fc56242b5094d4400d10f18b43e384a76b8a2497286b8cc4796611"   # src/Reservoir.cpp after the patch
EXPECTED_BIN_SHA="b89340f24a1df79706e6b45dc0b4bf378c884c2ce67f8ecd8f86344e375ec71d"   # D104 build (F146)
ARCH="$(uname -m)"
NAME="raven-v4.12-obwbp1-macos-${ARCH}"
OUT="${OBWBP1_OUT:-$ROOT/dist/$NAME}"
OLD="$ROOT/dist/raven-v4.12-macos-${ARCH}/Raven"
BREW="$(brew --prefix)"
OPT="-O0"
EXPECTED_SHA="81011f061e53ef1289ebcab36dc3622cea05c76d"

fail=0
qa() { if eval "$2"; then echo "$1 [PASS]"; else echo "$1 [FLAG]"; fail=1; fi; }
stop() { [ "$fail" -eq 0 ] || { echo "QAQC failed at stage '$1'; stopping."; exit 1; }; }
src_clean() { [ -z "$(git -C "$SRC" status --porcelain --untracked-files=no)" ] && git -C "$SRC" show HEAD:src/Reservoir.cpp | cmp -s - "$SRC/src/Reservoir.cpp"; }

[ ! -e "$OUT" ] || { echo "$OUT exists; not overwriting"; exit 1; }
OLD_SHA_BEFORE="$(shasum -a 256 "$OLD" | awk '{print $1}')"
SRC_RES_SHA_BEFORE="$(shasum -a 256 "$SRC/src/Reservoir.cpp" | awk '{print $1}')"

echo "== Source checks"
qa "source tree src/ is v4.12 commit $EXPECTED_SHA" "[ \"\$(git -C '$SRC' rev-parse HEAD)\" = '$EXPECTED_SHA' ]"
qa "src/ has no tracked modifications and its Reservoir.cpp equals the commit (D105: src stays upstream)" "src_clean"
qa "patch file sha256 is $PATCH_SHA" "[ \"\$(shasum -a 256 '$PATCH' | awk '{print \$1}')\" = '$PATCH_SHA' ]"
stop source

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/raven_obwbp1.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
B="$TMPD/raven"
mkdir -p "$B"
git -C "$SRC" archive HEAD | tar -x -C "$B"
qa "exported source Reservoir.cpp equals the commit before patching" "git -C '$SRC' show HEAD:src/Reservoir.cpp | cmp -s - '$B/src/Reservoir.cpp'"
(cd "$B" && patch -s -p1 < "$PATCH")
qa "patched Reservoir.cpp in the temporary tree has sha256 $PATCHED_FILE_SHA" "[ \"\$(shasum -a 256 '$B/src/Reservoir.cpp' | awk '{print \$1}')\" = '$PATCHED_FILE_SHA' ]"
qa "patched Reservoir.cpp carries 13 'OBWB patch D104' markers" "[ \$(grep -c 'OBWB patch D104: original line was' '$B/src/Reservoir.cpp') -eq 13 ]"
qa "patch replaces exactly the 13 original _Qout lines" "[ \$(grep -cE '^-[^-].*_Qout' '$PATCH') -eq 13 ] && [ \$(grep -cE '^-[^-]' '$PATCH') -eq 13 ]"
qa "only src/Reservoir.cpp differs between the temporary tree and src/ (tracked files)" \
   "[ \"\$(diff -rq '$B/src' '$SRC/src' | grep -v '^Only in $SRC' | sed 's|.*/||')\" = 'Reservoir.cpp differ' ]"
stop patch

echo "== Configure ($OPT) in $B/build"
mkdir -p "$B/lib"
ln -s "$BREW/opt/lp_solve/include" "$B/lib/lp_solve_unix"
ln -s "$BREW/opt/lp_solve/lib"     "$B/lib/lp_solve"
cmake -S "$B" -B "$B/build" \
  -DCMAKE_BUILD_TYPE=None \
  -DCMAKE_PREFIX_PATH="$BREW" \
  -DnetCDF_FOUND=ON \
  -DLPSOLVE=ON \
  -DCMAKE_CXX_FLAGS="$OPT -I$BREW/include" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$BREW/lib" >/dev/null
qa "compile flags equal the reference build's flags.make" \
   "diff <(grep -E 'CXX_FLAGS|CXX_DEFINES' '$SRC/build-reference/CMakeFiles/Raven.dir/flags.make') <(grep -E 'CXX_FLAGS|CXX_DEFINES' '$B/build/CMakeFiles/Raven.dir/flags.make') >/dev/null"
stop configure

echo "== Build"
cmake --build "$B/build" -j "$(sysctl -n hw.ncpu)" >/dev/null 2>&1
qa "the compiled Reservoir.cpp is the patched file (object built from $B/src/Reservoir.cpp, which still has sha256 $PATCHED_FILE_SHA)" \
   "[ -f \"\$(find '$B/build' -name 'Reservoir.cpp.o' | head -1)\" ] && [ \"\$(shasum -a 256 '$B/src/Reservoir.cpp' | awk '{print \$1}')\" = '$PATCHED_FILE_SHA' ]"
stop build

echo "== Bundle"
mkdir -p "$OUT/libs"
cp "$B/build/Raven" "$OUT/Raven"
dylibbundler -od -b -x "$OUT/Raven" -d "$OUT/libs" -p @executable_path/libs/ >/dev/null 2>&1
codesign --force -s - "$OUT"/libs/*.dylib "$OUT/Raven" 2>/dev/null
cp "$SRC/LICENSE" "$OUT/LICENSE-Raven.txt"
cp "$PATCH" "$OUT/OBWB_RavenPatch_v1_20261015.diff"
{
  echo "Raven v4.12 for macOS $ARCH, profile 'reference' ($OPT), OBWB patch obwbp1 (decisions D104, D105)"
  echo "Source: https://github.com/CSHS-CWRA/RavenHydroFramework commit $EXPECTED_SHA MODIFIED by OBWB_RavenPatch_v1_20261015.diff sha256 $PATCH_SHA (src/Reservoir.cpp, patched in a temporary copy)"
  echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ), macOS $(sw_vers -productVersion), $(clang --version | head -1)"
  echo "Libraries: netCDF $(nc-config --version | awk '{print $2}'), lp_solve $(brew list --versions lp_solve | awk '{print $2}'), HDF5 $(brew list --versions hdf5 | awk '{print $2}')"
  echo "Version string: $("$OUT/Raven" -v 2>&1 | head -1)"
} > "$OUT/BUILD_INFO.txt"

echo "== QAQC"
qa "binary is Mach-O $ARCH" "file '$OUT/Raven' | grep -q '$ARCH'"
qa "no load command points into Homebrew" "! otool -L '$OUT/Raven' '$OUT'/libs/*.dylib | grep -q '$BREW'"
qa "code signatures verify" "codesign -v '$OUT/Raven' && for f in '$OUT'/libs/*.dylib; do codesign -v \"\$f\" || exit 1; done"
qa "version string is 4.12 with netCDF and lp_solve" "'$OUT/Raven' -v 2>&1 | head -1 | grep -Eq '^4.12 w/ netCDF w/ lp_solve'"
NEW_SHA="$(shasum -a 256 "$OUT/Raven" | awk '{print $1}')"
OLD_SHA_AFTER="$(shasum -a 256 "$OLD" | awk '{print $1}')"
qa "unpatched reference binary unchanged by this build ($OLD_SHA_AFTER)" "[ '$OLD_SHA_BEFORE' = '$OLD_SHA_AFTER' ]"
qa "patched binary sha256 equals the D104 binary $EXPECTED_BIN_SHA" "[ '$NEW_SHA' = '$EXPECTED_BIN_SHA' ]"
qa "src/ still clean after the build (Reservoir.cpp sha256 unchanged, no tracked modification)" \
   "src_clean && [ \"\$(shasum -a 256 '$SRC/src/Reservoir.cpp' | awk '{print \$1}')\" = '$SRC_RES_SHA_BEFORE' ]"
echo "sha256 old $OLD_SHA_AFTER  $OLD"
echo "sha256 new $NEW_SHA  $OUT/Raven"
[ "$fail" -eq 0 ] && echo "QAQC build_obwbp1: 0 FLAG" || { echo "QAQC build_obwbp1: FLAGGED"; exit 1; }
