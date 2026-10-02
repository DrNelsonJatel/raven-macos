#!/usr/bin/env bash
# Run the Raven benchmark models (src/benchmarking/_InputFiles) with one or two
# executables. With a reference executable, compare every output file and
# report the largest absolute hydrograph difference.
#
# Usage: ./benchmark.sh <test_exe> [reference_exe]
# Env:   TOL (default 1e-6, m3/s)
#        KNOWN_FAIL (default "Nith"): cases whose upstream inputs fail to parse
#        under Raven 4.x with every executable, including the official one
# Exit status is non-zero if a comparable case differs by more than TOL, or if
# one executable completes a case the other cannot.
set -uo pipefail

[ $# -ge 1 ] || { echo "Usage: $0 <test_exe> [reference_exe]"; exit 2; }
TEST_EXE="$1"; REF_EXE="${2:-}"
TOL="${TOL:-1e-6}"
KNOWN_FAIL="${KNOWN_FAIL:-Nith}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
CASES_DIR="$ROOT/src/benchmarking/_InputFiles"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Case directory and .rvi stem, from upstream RavenBenchmarking.sh
cases=(Alouette:Alouette_ws Alouette2:Alouette2 York_nc:York_gridded_m_daily_i_daily
       Irondequoit:Irondequoit LOTW:LOWRL LaJoie:La_Joie_ws Nith:Nith
       Revelstoke:Revelstoke_ws Salmon_GR4J:raven-gr4j-salmon Salmon_HBV:raven-hbv-salmon
       Salmon_HMETS:raven-hmets-salmon Salmon_MOHYSE:raven-mohyse-salmon
       Williston_Finlay:Williston_Finlay_ws)

run_case() {  # exe label case rvi; status 0 = run wrote a hydrograph file
  local out="$WORK/$2/$3"; mkdir -p "$out"
  cp -R "$CASES_DIR/$3" "$WORK/in_$2_$3"
  ( cd "$WORK/in_$2_$3" && "$1" "$4" -o "$out/" > "$out/stdout.txt" 2>&1 )
  ls "$out"/*Hydrographs.* >/dev/null 2>&1
}

fail=0
printf "%-18s %-5s %-5s %-9s %s\n" CASE TEST REF IDENTICAL HYDRO_MAX_DIFF
for c in "${cases[@]}"; do
  dir="${c%%:*}"; rvi="${c##*:}"
  [ -d "$CASES_DIR/$dir" ] || { printf "%-18s missing in this source tag\n" "$dir"; continue; }
  if [[ " $KNOWN_FAIL " == *" $dir "* ]]; then printf "%-18s known upstream input failure, skipped\n" "$dir"; continue; fi
  t="FAIL"; r="-"; same="-"; d="-"
  run_case "$TEST_EXE" test "$dir" "$rvi" && t="PASS"
  if [ -n "$REF_EXE" ]; then
    r="FAIL"; run_case "$REF_EXE" ref "$dir" "$rvi" && r="PASS"
    if [ "$t" = PASS ] && [ "$r" = PASS ]; then
      read -r same d <<< "$(python3 "$ROOT/scripts/compare_outputs.py" "$WORK/test/$dir" "$WORK/ref/$dir")"
      python3 -c "import sys; sys.exit(0 if float('$d') <= $TOL else 1)" || fail=1
    elif [ "$t" != "$r" ]; then
      fail=1
    fi
  else
    [ "$t" = PASS ] || fail=1
  fi
  printf "%-18s %-5s %-5s %-9s %s\n" "$dir" "$t" "$r" "$same" "$d"
done
echo "Tolerance $TOL m3/s. Result: $([ $fail -eq 0 ] && echo PASS || echo FLAG)"
exit $fail
