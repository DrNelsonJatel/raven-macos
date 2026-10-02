# Changelog

All notable changes to the build scripts and release archives are listed here.
Raven's own changes are documented upstream.

## [v4.12-1] - 2026-10-02

### Added
- `build.sh`: builds Raven from an upstream tag with NetCDF and lp_solve on
  macOS arm64, bundles dylibs, re-signs ad hoc, runs packaging QAQC.
- Two profiles: `reference` (`-O0`, matches the official Waterloo macOS
  executable) and `fast` (`-O3`).
- `benchmark.sh` and `scripts/compare_outputs.py`: run the upstream benchmark
  models and compare output files between two executables.
- Validation record in `docs/VALIDATION.md`.

### Release archives
- `raven-v4.12-macos-arm64.tar.gz` (reference)
- `raven-v4.12-macos-arm64-fast.tar.gz` (fast)
