# Contributing

This repository packages Raven for macOS. It does not change Raven.

- **Build or packaging problems** (binary will not start, missing library,
  NetCDF not detected, signature or quarantine issues): open an issue here
  with the output of `./Raven -v`, `cat BUILD_INFO.txt`, `sw_vers` and
  `uname -m`.
- **Model results, Raven features or Raven bugs**: report upstream at
  https://github.com/CSHS-CWRA/RavenHydroFramework or through
  https://raven.uwaterloo.ca. If a result differs between the `reference` and
  `fast` builds, include both outputs.
- **Pull requests**: keep `build.sh` free of Raven source edits. Any new build
  step needs a matching QAQC check in `build.sh`, and `benchmark.sh` must pass
  against the reference build before merge.
