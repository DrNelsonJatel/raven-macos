#!/usr/bin/env bash
# Build a NetCDF + lp_solve enabled Raven executable for macOS from the
# official source (github.com/CSHS-CWRA/RavenHydroFramework, unmodified) and
# bundle its Homebrew dylibs so the binary runs without Homebrew installed.
#
# Usage:   ./build.sh [raven_tag] [profile]
#          ./build.sh v4.12 reference     (default)
#          ./build.sh v4.12 fast
# Profiles:
#   reference  -O0. Reproduces the official University of Waterloo macOS
#              executable bit for bit on the upstream benchmark models.
#   fast       -O3. About 2x faster; results on some models differ from the
#              official executable (see README, "Validation").
# Output:  dist/raven-<tag>-macos-<arch>[-fast]/ and a .tar.gz with .sha256
set -euo pipefail

TAG="${1:-v4.12}"
PROFILE="${2:-reference}"
case "$PROFILE" in
  reference) OPT="-O0"; SUFFIX="" ;;
  fast)      OPT="-O3"; SUFFIX="-fast" ;;
  *) echo "Unknown profile '$PROFILE' (use reference or fast)"; exit 2 ;;
esac
ARCH="$(uname -m)"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
NAME="raven-${TAG}-macos-${ARCH}${SUFFIX}"
OUT="$ROOT/dist/$NAME"
BREW="$(brew --prefix)"

echo "== Dependencies"
brew list cmake netcdf lp_solve dylibbundler >/dev/null 2>&1 || brew install cmake netcdf lp_solve dylibbundler

echo "== Source $TAG"
if [ ! -d "$SRC/.git" ] || [ "$(git -C "$SRC" describe --tags --exact-match 2>/dev/null)" != "$TAG" ]; then
  rm -rf "$SRC"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" \
    https://github.com/CSHS-CWRA/RavenHydroFramework.git "$SRC"
fi
SRC_SHA="$(git -C "$SRC" rev-parse HEAD)"

# DemandOptimization.h includes ../lib/lp_solve_unix/lp_lib.h and CMakeLists
# links from lib/lp_solve; point both at the Homebrew lp_solve install.
mkdir -p "$SRC/lib"
ln -sfn "$BREW/opt/lp_solve/include" "$SRC/lib/lp_solve_unix"
ln -sfn "$BREW/opt/lp_solve/lib"     "$SRC/lib/lp_solve"

echo "== Configure ($PROFILE, $OPT)"
# On case-insensitive macOS file systems find_package(NetCDF) succeeds through
# netCDFConfig.cmake and sets NetCDF_FOUND, but CMakeLists tests NETCDF_FOUND
# and netCDF_FOUND, so NetCDF is silently dropped. netCDF_FOUND=ON selects the
# branch that links libnetcdf directly.
BUILD="$SRC/build-$PROFILE"
rm -rf "$BUILD"
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=None \
  -DCMAKE_PREFIX_PATH="$BREW" \
  -DnetCDF_FOUND=ON \
  -DLPSOLVE=ON \
  -DCMAKE_CXX_FLAGS="$OPT -I$BREW/include" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$BREW/lib" >/dev/null

echo "== Build"
cmake --build "$BUILD" -j "$(sysctl -n hw.ncpu)" >/dev/null

echo "== Bundle"
rm -rf "$OUT" "$OUT.tar.gz" "$OUT.tar.gz.sha256"
mkdir -p "$OUT/libs"
cp "$BUILD/Raven" "$OUT/Raven"
dylibbundler -od -b -x "$OUT/Raven" -d "$OUT/libs" -p @executable_path/libs/ >/dev/null 2>&1
# dylibbundler rewrites load commands, which invalidates the signature; re-sign ad hoc.
codesign --force -s - "$OUT"/libs/*.dylib "$OUT/Raven" 2>/dev/null
cp "$SRC/LICENSE" "$OUT/LICENSE-Raven.txt"
# Licences of the bundled third-party libraries (lp_solve is LGPL-2.1: it ships
# as a separate, replaceable dylib in libs/).
mkdir -p "$OUT/third_party_licenses"
for pair in netcdf:COPYRIGHT hdf5:LICENSE lp_solve:LICENSE libaec:LICENSE.txt zstd:LICENSE; do
  pkg="${pair%%:*}"; f="${pair##*:}"
  cp "$(brew --prefix "$pkg")/$f" "$OUT/third_party_licenses/$pkg-$f"
done
cp "$ROOT/README.md" "$OUT/README.md" 2>/dev/null || true

{
  echo "Raven $TAG for macOS $ARCH, profile '$PROFILE' ($OPT)"
  echo "Source: https://github.com/CSHS-CWRA/RavenHydroFramework commit $SRC_SHA (unmodified)"
  echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ), macOS $(sw_vers -productVersion), $(clang --version | head -1)"
  echo "Libraries: netCDF $(nc-config --version | awk '{print $2}'), lp_solve $(brew list --versions lp_solve | awk '{print $2}'), HDF5 $(brew list --versions hdf5 | awk '{print $2}')"
  echo "Version string: $("$OUT/Raven" -v 2>&1 | head -1)"
} > "$OUT/BUILD_INFO.txt"

echo "== QAQC"
fail=0
qa() { if eval "$2"; then echo "[PASS] $1"; else echo "[FLAG] $1"; fail=1; fi; }
qa "binary is Mach-O $ARCH" "file '$OUT/Raven' | grep -q '$ARCH'"
qa "no load command points into Homebrew" "! otool -L '$OUT/Raven' '$OUT'/libs/*.dylib | grep -q '$BREW'"
qa "every bundled library resolves inside libs/" \
   "otool -L '$OUT/Raven' '$OUT'/libs/*.dylib | awk 'NR>1 && /@executable_path/ {sub(\"@executable_path/\",\"\"); print \$1}' | sort -u | while read -r f; do [ -e '$OUT/'\$f ] || exit 1; done"
qa "code signatures verify" "codesign -v '$OUT/Raven' && for f in '$OUT'/libs/*.dylib; do codesign -v \"\$f\" || exit 1; done"
qa "version string is ${TAG#v} with netCDF and lp_solve" \
   "'$OUT/Raven' -v 2>&1 | head -1 | grep -Eq '^${TAG#v} w/ netCDF w/ lp_solve'"
SMOKE="$(mktemp -d)"
cp -R "$SRC/benchmarking/_InputFiles/Salmon_HBV" "$SMOKE/hbv"
cp -R "$SRC/benchmarking/_InputFiles/York_nc" "$SMOKE/nc"
qa "smoke run: Salmon_HBV completes" \
   "(cd '$SMOKE/hbv' && '$OUT/Raven' raven-hbv-salmon -o '$SMOKE/hbv/out/' >/dev/null 2>&1); grep -q 'Successful' '$SMOKE/hbv/out/'*Raven_errors.txt 2>/dev/null || ls '$SMOKE/hbv/out/'*Hydrographs.csv >/dev/null 2>&1"
qa "smoke run: York_nc reads NetCDF forcing" \
   "(cd '$SMOKE/nc' && '$OUT/Raven' York_gridded_m_daily_i_daily -o '$SMOKE/nc/out/' >/dev/null 2>&1); ls '$SMOKE/nc/out/'*Hydrographs.csv >/dev/null 2>&1"
rm -rf "$SMOKE"
qa "licence files present for Raven and all 5 bundled packages" \
   "[ -s '$OUT/LICENSE-Raven.txt' ] && [ \$(ls '$OUT/third_party_licenses' | wc -l) -eq 5 ]"
[ "$fail" -eq 0 ] || { echo "QAQC failed; not packaging."; exit 1; }

tar -C "$ROOT/dist" -czf "$OUT.tar.gz" "$NAME"
(cd "$ROOT/dist" && shasum -a 256 "$NAME.tar.gz" > "$NAME.tar.gz.sha256" && cat "$NAME.tar.gz.sha256")
echo "Done: $OUT.tar.gz"
