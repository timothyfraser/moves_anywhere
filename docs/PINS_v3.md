# moves-anywhere v3 pins

Part of the MOVES Anywhere guides: see the [index](README.md).

These are the exact versions that `tmf77/moves-anywhere:v2` (image digest starting `sha256:51ccd84e`) ships, recorded so v3 rebuilds the same MOVES and the same R stack. v3 changes how the image is built (MOVES pinned and compiled at build time, no Google tooling); it does not change which MOVES it runs.

## MOVES

| Item | Value |
|---|---|
| Repository | `https://github.com/USEPA/EPA_MOVES_Model.git` |
| Commit (v2 `HEAD`) | `2c4cd1ab31b53bc9731492544fcbd0a6e47b970a` |
| Commit date | 2024-11-21T11:40:13-05:00 |
| Default-database dump | `movesdb20241112.zip` (inside the repository at that commit) |
| Dockerfile argument | `MOVES_COMMIT` (default is the commit above) |

## System toolchain in v2

| Tool | Version |
|---|---|
| Base image | `ubuntu:20.04` |
| R | 4.5.0 (2025-04-11), from the CRAN apt repository |
| Java | OpenJDK 11.0.26 (2025-01-21) |
| Go | go1.13.8 linux/amd64 (Ubuntu `golang-go`) |
| MySQL client / server | MariaDB 10.3.39 (`mysql Ver 15.1`) |

## Build arguments in v3

| Argument | Default | Effect |
|---|---|---|
| `MOVES_COMMIT` | the commit above | commit fetched (shallow) and checked out |
| `GIT_REVISION` | `unknown` | the moves_anywhere commit, written to the `org.opencontainers.image.revision` label |
| `GO_VERSION` | `1.27.4` (3.1.0) | the go.dev Go release used to compile MOVES's two Go programs, then deleted in the same build step |
| `GO_SHA256` | the go.dev checksum of `go1.27.4.linux-amd64.tar.gz` | the download is checked against it; a mismatch stops the build |
| `PIN_RCLONE_VERSION` | `1.76.0` (3.1.0) | the official rclone release installed for sync mode |
| `PIN_RCLONE_SHA256` | rclone's published checksum of `rclone-v1.76.0-linux-amd64.zip` | the download is checked against it; a mismatch stops the build. (The names do not start with `RCLONE_`: rclone reads `RCLONE_<FLAG>` variables as flags.) |

MOVES debug data is a run-time switch (`"debug": true` in `parameters.json`), not a build argument. v2 applied the `keepDebugData = true` edit on every run, so v2 always kept debug data.

## Toolchain around MOVES in v3.1.0

| Tool | 3.0.0 | 3.1.0 |
|---|---|---|
| Go (compiles MOVES's two Go programs at build time) | Ubuntu `golang-go`, Go 1.13.8, kept in the image | Go 1.27.4 from go.dev, deleted in the same build step |
| Ant (compiles and runs MOVES) | Ubuntu `ant` 1.10.7 | the Ant 1.10.15 that EPA ships in the MOVES tree (`ant/`), linked into `/usr/local/bin` |
| rclone (sync mode only) | Ubuntu `rclone` 1.50.2 (built with Go 1.13.8) | rclone 1.76.0, official release |
| System Python | `python3` with `requests`, `urllib3`, `certifi` (from `software-properties-common`) | `python3` only, standard library |

EPA's source (`calc/` and `generators/` at `MOVES_COMMIT`) is unchanged. `GOAMD64=v1` (the default) keeps plain x86-64 floating point. EPA's own prebuilt Windows tools in `tools/` (built by EPA with Go 1.21) and the Java libraries in `libs/` are left as shipped. Apart from the two Go programs, every file under `/cat/EPA_MOVES_Model` is byte-identical to 3.0.0, and the R packages are the same as the v3.0.0 table below.

## What v3 pins that v2 left floating

The Dockerfile asks for `remotes` 2.5.0, `RMySQL` 0.11.1 and `httr` 1.4.7, the versions v2 had. In the v3.0.0 build a later install upgraded `httr` to 1.4.9 (see the v3.0.0 table below); `remotes` and `RMySQL` stayed as asked. Packages that v2 installed with a version (for example `dplyr` 1.1.0) are unchanged in the Dockerfile; v2 ended up with newer versions of several of them because later installs upgraded them (see the list below). The apt packages and the R binary itself are not version-pinned.

## What v3 removes

`google-cloud-cli`, `gcsfuse` and `fuse` (the Google command-line tools). The three Google R packages `gargle`, `googleAuthR` and `googleCloudStorageR` are not removed: the Dockerfile still installs them, pinned to the v2 versions below, because `catr` 0.2.0 imports them. They are asked for at the v2 versions, but later installs upgrade `gargle` and `googleAuthR` (v3.0.0 has `gargle` 1.7.0 and `googleAuthR` 2.0.2.1).

## R packages in v2 (`installed.packages()`)

| Package | Version |
|---|---|
| DBI | 1.2.3 |
| R6 | 2.6.1 |
| RMariaDB | 1.3.1 |
| RMySQL | 0.11.1 |
| askpass | 1.2.1 |
| assertthat | 0.2.1 |
| bit | 4.6.0 |
| bit64 | 4.6.0-1 |
| blob | 1.2.4 |
| cachem | 1.1.0 |
| catr | 0.2.0 |
| cli | 3.6.4 |
| clipr | 0.8.0 |
| cpp11 | 0.5.2 |
| crayon | 1.5.3 |
| curl | 6.2.2 |
| dbplyr | 2.3.2 |
| digest | 0.6.37 |
| dplyr | 1.1.4 |
| fansi | 1.0.6 |
| fastmap | 1.2.0 |
| fs | 1.6.6 |
| gargle | 1.5.2 |
| generics | 0.1.3 |
| glue | 1.8.0 |
| googleAuthR | 2.0.2 |
| googleCloudStorageR | 0.7.0 |
| hms | 1.1.3 |
| httr | 1.4.7 |
| jsonlite | 1.8.9 |
| lifecycle | 1.0.4 |
| lubridate | 1.9.4 |
| magrittr | 2.0.3 |
| memoise | 2.0.1 |
| mime | 0.13 |
| openssl | 2.3.2 |
| pillar | 1.10.2 |
| pkgconfig | 2.0.3 |
| plogr | 0.2.0 |
| prettyunits | 1.2.0 |
| progress | 1.2.3 |
| purrr | 1.0.4 |
| rappdirs | 0.3.3 |
| readr | 2.1.4 |
| remotes | 2.5.0 |
| rlang | 1.1.6 |
| stringi | 1.8.7 |
| stringr | 1.5.1 |
| sys | 3.4.3 |
| tibble | 3.2.1 |
| tidyr | 1.3.1 |
| tidyselect | 1.2.1 |
| timechange | 0.3.0 |
| tzdb | 0.5.0 |
| utf8 | 1.2.4 |
| vctrs | 0.6.5 |
| vroom | 1.6.3 |
| withr | 3.0.2 |
| xml2 | 1.3.6 |
| yaml | 2.3.10 |
| zip | 2.3.2 |
| KernSmooth | 2.23-26 |
| MASS | 7.3-65 |
| Matrix | 1.7-3 |
| base | 4.5.0 |
| boot | 1.3-31 |
| class | 7.3-23 |
| cluster | 2.1.8.1 |
| codetools | 0.2-19 |
| compiler | 4.5.0 |
| datasets | 4.5.0 |
| foreign | 0.8-90 |
| grDevices | 4.5.0 |
| graphics | 4.5.0 |
| grid | 4.5.0 |
| lattice | 0.22-5 |
| methods | 4.5.0 |
| mgcv | 1.9-1 |
| nlme | 3.1-168 |
| nnet | 7.3-20 |
| parallel | 4.5.0 |
| rpart | 4.1.24 |
| spatial | 7.3-11 |
| splines | 4.5.0 |
| stats | 4.5.0 |
| stats4 | 4.5.0 |
| survival | 3.8-3 |
| tcltk | 4.5.0 |
| tools | 4.5.0 |
| utils | 4.5.0 |

---

## R packages in v3.0.0 as built (2026-11-13)

The v3.0.0 image installs R packages from CRAN at build time; they are not pinned to the v2 versions above. Built 2026-11-13 from the release commit, it holds R 4.5.2 and the versions below wherever they differ from v2 (55 packages differ; `fansi` is no longer installed). The fixture run on this image matched the v2-era gold result exactly on all three output files, so these differences do not change results. The published image is fixed by its digest; a later rebuild may pick up newer CRAN versions.

| Package | v2 | v3.0.0 |
|---|---|---|
| DBI | 1.2.3 | 1.3.0 |
| bit64 | 4.6.0-1 | 4.8.6 |
| blob | 1.2.4 | 1.3.0 |
| cli | 3.6.4 | 3.6.6 |
| clipr | 0.8.0 | 0.8.1 |
| cpp11 | 0.5.2 | 0.5.5 |
| curl | 6.2.2 | 8.1.0 |
| digest | 0.6.37 | 0.6.39 |
| dplyr | 1.1.4 | 1.2.1 |
| fansi | 1.0.6 | (not installed) |
| fs | 1.6.6 | 2.1.0 |
| gargle | 1.5.2 | 1.7.0 |
| generics | 0.1.3 | 0.1.4 |
| glue | 1.8.0 | 1.8.1 |
| googleAuthR | 2.0.2 | 2.0.2.1 |
| hms | 1.1.3 | 1.1.4 |
| httr | 1.4.7 | 1.4.9 |
| jsonlite | 1.8.9 | 2.0.0 |
| lifecycle | 1.0.4 | 1.0.5 |
| lubridate | 1.9.4 | 1.9.5 |
| magrittr | 2.0.3 | 2.0.5 |
| openssl | 2.3.2 | 2.5.0 |
| pillar | 1.10.2 | 1.11.1 |
| purrr | 1.0.4 | 1.2.2 |
| rappdirs | 0.3.3 | 0.3.4 |
| rlang | 1.1.6 | 1.3.0 |
| stringi | 1.8.7 | 1.8.9 |
| stringr | 1.5.1 | 1.6.0 |
| tibble | 3.2.1 | 3.3.1 |
| tidyr | 1.3.1 | 1.3.2 |
| timechange | 0.3.0 | 0.4.0 |
| utf8 | 1.2.4 | 1.2.6 |
| vctrs | 0.6.5 | 0.7.3 |
| withr | 3.0.2 | 3.0.3 |
| yaml | 2.3.10 | 2.3.12 |
| zip | 2.3.2 | 3.0.2 |
| Matrix | 1.7-3 | 1.7-4 |
| base | 4.5.0 | 4.5.2 |
| cluster | 2.1.8.1 | 2.1.8.2 |
| compiler | 4.5.0 | 4.5.2 |
| datasets | 4.5.0 | 4.5.2 |
| foreign | 0.8-90 | 0.8-91 |
| grDevices | 4.5.0 | 4.5.2 |
| graphics | 4.5.0 | 4.5.2 |
| grid | 4.5.0 | 4.5.2 |
| lattice | 0.22-5 | 0.22-9 |
| methods | 4.5.0 | 4.5.2 |
| mgcv | 1.9-1 | 1.9-4 |
| parallel | 4.5.0 | 4.5.2 |
| splines | 4.5.0 | 4.5.2 |
| stats | 4.5.0 | 4.5.2 |
| stats4 | 4.5.0 | 4.5.2 |
| survival | 3.8-3 | 3.8-6 |
| tcltk | 4.5.0 | 4.5.2 |
| tools | 4.5.0 | 4.5.2 |
| utils | 4.5.0 | 4.5.2 |

## For agents

- Source of truth for the numbers above: `docker run --rm --entrypoint bash tmf77/moves-anywhere:v2 -c "git config --global --add safe.directory /cat/EPA_MOVES_Model; git -C /cat/EPA_MOVES_Model rev-parse HEAD; git -C /cat/EPA_MOVES_Model log -1 --format=%cI; R --version | head -1; java -version 2>&1 | head -1; go version; mysql --version"` plus `Rscript -e 'ip<-installed.packages()[,c("Package","Version")]; write.csv(ip, stdout(), row.names=FALSE)'`. The `safe.directory` line is required: the MOVES tree is owned by `mysql`, and git refuses to read it as root otherwise.
- The v2 MOVES working tree shows many `M` entries in `git status`. `HEAD` is still the commit above; do not read those entries as local source edits.
- Dockerfile pins: `ARG MOVES_COMMIT`, `ARG KEEP_DEBUG=false`. Build: `docker build -t tmf77/moves-anywhere:v3 --build-arg MOVES_COMMIT=2c4cd1ab31b53bc9731492544fcbd0a6e47b970a .` from `moves_anywhere/`.
- Compile happens once, in the build, after `setupdb.sh`. `scripts/task_importer.sh` and `scripts/task_launch_moves.sh` no longer run `ant clean`, `ant compileall`, `ant go64`, or the `keepDebugData` edit. `scripts/launch.sh` no longer runs `task_install_catr.R`. `scripts/launch_fuse.sh` is unchanged and is not supported by v3 (no gcsfuse).
- `scripts/task_check_packages.R` still lists `googleCloudStorageR`, `googleAuthR` and `gargle` as needed, so it prints a "packages need installed" line on v3. It is a diagnostic only; it does not stop the run.
- Package versions are those of the image at the time of the v2 build (2025). Versions pinned by `install_version` in the Dockerfile can be upgraded by later installs, so the list above, not the Dockerfile lines, is the record of what v2 actually contained.

---

Back to the [index](README.md). Next: [Developer tools](README_dev.md).
