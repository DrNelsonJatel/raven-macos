# raven-macos

Native macOS (Apple Silicon) builds of the [Raven hydrological modelling framework](https://raven.uwaterloo.ca) with **NetCDF** and **lp_solve** support, and the scripts to reproduce them.

The University of Waterloo distributes a macOS executable without NetCDF support. Models that read gridded or HRU-based NetCDF forcing, including the Okanagan Basin Water Board Raven models, need a NetCDF-enabled build. This repository provides one, built from the official Raven source with no source changes.

> This is an independent build. It is not an official Raven release. Raven is developed by the Raven Development Team, led by Dr. James R. Craig, University of Waterloo. Report modelling bugs upstream; report build or packaging problems here.

## Downloads

See [Releases](../../releases). Each release has two builds:

| File | Profile | Use |
|---|---|---|
| `raven-<tag>-macos-arm64.tar.gz` | `reference` (`-O0`) | Default. Reproduces the official Waterloo macOS executable bit for bit on the upstream benchmark models (see [Validation](#validation)). |
| `raven-<tag>-macos-arm64-fast.tar.gz` | `fast` (`-O3`) | About 2x faster. Use for calibration runs where speed matters, after checking your own model against the reference build. |

Each archive contains `Raven`, the bundled libraries in `libs/`, `BUILD_INFO.txt`, `LICENSE-Raven.txt` and `third_party_licenses/`. A `.sha256` file accompanies each archive.

Requirements: macOS on Apple Silicon (arm64). Homebrew is not needed to run the binary. Intel Macs are not built or tested.

## Install

```sh
shasum -a 256 -c raven-v4.12-macos-arm64.tar.gz.sha256
tar -xzf raven-v4.12-macos-arm64.tar.gz
xattr -dr com.apple.quarantine raven-v4.12-macos-arm64   # binaries are ad hoc signed, not notarized
./raven-v4.12-macos-arm64/Raven -v                        # prints: 4.12 w/ netCDF w/ lp_solve
```

Run a model from its directory:

```sh
cd path/to/model
/path/to/raven-v4.12-macos-arm64/Raven <model_stem> -o ./output/
```

Keep `Raven` and `libs/` together. The binary loads its libraries from `@executable_path/libs/`.

## Build from source

```sh
./build.sh v4.12 reference   # or: ./build.sh v4.12 fast
```

`build.sh` installs `cmake`, `netcdf`, `lp_solve` and `dylibbundler` with Homebrew if missing, clones the requested tag of [CSHS-CWRA/RavenHydroFramework](https://github.com/CSHS-CWRA/RavenHydroFramework), configures, builds, bundles the dylibs, re-signs ad hoc, and runs packaging QAQC (architecture, no Homebrew load paths, library resolution, signatures, version string, two smoke runs including a NetCDF model, licence files). It stops without packaging if any check fails.

Two build details handled by the script, without editing Raven source:

1. **NetCDF detection on macOS.** On a case-insensitive file system `find_package(NetCDF)` succeeds through `netCDFConfig.cmake` and sets `NetCDF_FOUND`, but the upstream `CMakeLists.txt` tests `NETCDF_FOUND` and `netCDF_FOUND`, so NetCDF is silently dropped. The script passes `-DnetCDF_FOUND=ON`.
2. **lp_solve headers.** `DemandOptimization.h` expects `lib/lp_solve_unix/lp_lib.h`. The script links `src/lib/lp_solve_unix` and `src/lib/lp_solve` to the Homebrew `lp_solve` install.

## Validation

`benchmark.sh` runs the upstream benchmark models in `src/benchmarking/_InputFiles` and, given a second executable, compares every output file.

```sh
./benchmark.sh <test_exe> [reference_exe]
```

Results on an Apple M-series Mac (2026-10-02), full detail in [docs/VALIDATION.md](docs/VALIDATION.md):

- **Toolchain check.** Raven v4.1 built here with the `reference` profile matched the official Waterloo macOS v4.1 executable on all 11 comparable benchmark models: every output file identical (hydrograph max difference 0).
- **Optimization sensitivity.** Builds at `-O1`, `-O2` and `-O3` agree with each other but differ from `-O0` on two models (v4.1 and v4.12 alike): LaJoie (hydrograph max difference 2.84 m3/s, up to 2.5% relative) and Williston_Finlay (0.02 m3/s). On v4.12 the other 10 comparable models give identical hydrographs. This is why `reference` is the default.
- **v4.12.** All 12 models run with the `reference` build. `York_nc` exercises NetCDF forcing.
- **Nith** fails to parse under Raven 4.x with every executable tested, including the official one (`:AggregatedVariable - invalid HRU Group`). It is skipped as an upstream input issue.

## Notes for existing models

Raven 4.x is stricter than 3.x. Models written for Raven 3.x may stop with input errors that older versions accepted, for example:

```
ERROR : CReservoir::SetVolumeStageCurve: volume-stage relationships must be monotonically increasing for all stages.
ERROR : CReservoir::SetVolumeStageCurve: volume-stage relationships must start with volume of zero.
```

These are model input issues, not build issues.

## Citation

If you use these builds, cite Raven (see `CITATION.cff`):

Craig, J. R., Brown, G., Chlumsky, R., Jenkinson, R. W., Jost, G., Lee, K., Mai, J., Serrer, M., Sgro, N., Shafii, M., Snowdon, A. P., & Tolson, B. A. (2020). Flexible watershed simulation with the Raven hydrological modelling framework. *Environmental Modelling & Software, 129*, 104728. https://doi.org/10.1016/j.envsoft.2020.104728

## Licences

- Build scripts in this repository: MIT, see [LICENSE](LICENSE).
- Raven: Artistic License 2.0, see `LICENSE-Raven.txt` in each archive. Binaries are compiled from the unmodified Standard Version; source is at https://github.com/CSHS-CWRA/RavenHydroFramework at the commit recorded in `BUILD_INFO.txt`.
- Bundled libraries (see `third_party_licenses/`): netCDF-C (BSD-style), HDF5 (BSD-style), lp_solve (LGPL-2.1, shipped as a separate replaceable dylib), libaec (BSD-2-Clause), zstd (BSD).

## Maintainer

Nelson Jatel ([@DrNelsonJatel](https://github.com/DrNelsonJatel)).
