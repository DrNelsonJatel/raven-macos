# Validation record

Machine: Apple Silicon (arm64), macOS 27.0, Apple clang 21.0.0.
Libraries: netCDF-C 4.10.1, HDF5 2.2.0, lp_solve 5.5.2.14 (Homebrew).
Date: 2026-10-02. Tool: `benchmark.sh`, comparing every output file except
`Raven_errors.txt` and lines carrying run timestamps.

## 1. Toolchain check: v4.1 built here vs official Waterloo macOS v4.1

Reference: `RavenExecutableMacOS_v4.1.zip` from https://raven.uwaterloo.ca/Downloads.html
(arm64, version string `4.1`, no NetCDF).

| Case | This build `-O0` | Official | Identical files | Hydrograph max abs diff (m3/s) |
|---|---|---|---|---|
| Alouette | run | run | 16/16 | 0 |
| Alouette2 | run | run | 9/9 | 0 |
| Irondequoit | run | run | 3/3 | 0 |
| LOTW | run | run | 8/8 | 0 |
| LaJoie | run | run | 16/16 | 0 |
| Revelstoke | run | run | 16/16 | 0 |
| Salmon_GR4J | run | run | 5/5 | 0 |
| Salmon_HBV | run | run | 5/5 | 0 |
| Salmon_HMETS | run | run | 5/5 | 0 |
| Salmon_MOHYSE | run | run | 4/4 | 0 |
| Williston_Finlay | run | run | 16/16 | 0 |
| York_nc | run | cannot run (no NetCDF) | n/a | n/a |
| Nith | input error | input error | n/a | n/a |

Result: the `-O0` build reproduces the official executable exactly on every
comparable case.

## 2. Optimization level

With the official v4.1 as reference, `-O3` builds gave identical hydrographs
on 9 of 11 comparable cases and differed on two:

| Case | Hydrograph max abs diff (m3/s) | Max relative diff (flows > 1 m3/s) |
|---|---|---|
| LaJoie | 2.84 | 2.5% |
| Williston_Finlay | 0.02 | not computed |

`-O1`, `-O2` and `-O3` builds give identical LaJoie output to each other, and
disabling floating point contraction (`-ffp-contract=off`) did not restore
agreement with `-O0`. The cause was not isolated. The difference starts
abruptly partway through the LaJoie record rather than growing gradually.

Runtime, LaJoie: `-O0` 7.5 s, official 7.4 s, `-O1` 4.1 s, `-O2` 4.0 s, `-O3` 3.8 s.

## 3. v4.12

`reference` vs `fast`, same source commit
(81011f061e53ef1289ebcab36dc3622cea05c76d):

| Case | Identical files | Hydrograph max abs diff (m3/s) |
|---|---|---|
| Alouette | 13/16 | 0 |
| Alouette2 | 9/9 | 0 |
| York_nc | 4/4 | 0 |
| Irondequoit | 3/3 | 0 |
| LOTW | 7/8 | 0 |
| LaJoie | 6/16 | 2.84 |
| Revelstoke | 11/16 | 0 |
| Salmon_GR4J | 5/5 | 0 |
| Salmon_HBV | 5/5 | 0 |
| Salmon_HMETS | 5/5 | 0 |
| Salmon_MOHYSE | 3/4 | 0 |
| Williston_Finlay | 8/16 | 0.02 |

All 12 cases run with the `reference` build (single-executable mode: PASS).
Nith is skipped: its inputs fail to parse under Raven 4.x with every
executable tested (`:AggregatedVariable - invalid HRU Group used`).

## Not tested

- Intel (x86_64) Macs.
- Running on a Mac with no Homebrew installed. The packaging QAQC verifies
  that no load command points into Homebrew and that every bundled library
  resolves inside `libs/`, but a clean-machine run has not been done.
- lp_solve-dependent features (demand optimization): the library links and
  the version string reports it, but no benchmark model exercises it.
