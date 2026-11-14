# Changelog

## 3.1.0

Image `tmf77/moves-anywhere:v3` (also `v3.1` and `v3.1.0`). `v3.0.0` and `v2` are unchanged and stay available.

3.1.0 changes what sits around EPA MOVES, never MOVES itself: the same MOVES commit, the same EPA files, the same default database, the same run scripts, run manifest and run ticket. It removes or replaces the software outside MOVES that a vulnerability scan of 3.0.0 flagged.

### What changed since 3.0.0

- **No Go toolchain in the image.** 3.0.0 installed Ubuntu's `golang-go` (Go 1.13.8), compiled MOVES's two Go programs (`calc/externalcalculatorgo64.exe`, `generators/externalgenerator64.exe`) with it, and kept it. 3.1.0 compiles the same, unchanged EPA source with Go 1.27.4 from go.dev (checked against its published SHA-256) and deletes the toolchain in the same build step. `GOAMD64=v1` keeps plain x86-64 floating point.
- **rclone from its official release.** Sync mode (`MOVES_IO=sync`) uses rclone. Ubuntu's rclone 1.50.2 was built with Go 1.13.8; 3.1.0 installs rclone 1.76.0 from its official release, pinned by SHA-256. Sync mode works as before (new test below).
- **MOVES's own Ant.** 3.0.0 compiled and ran MOVES with Ubuntu's Ant 1.10.7. 3.1.0 uses the Ant 1.10.15 that EPA ships inside the MOVES tree (the one MOVES's `setenv.sh` puts on `PATH`), linked into `/usr/local/bin`. EPA's files are unchanged.
- **No `software-properties-common`.** Nothing used it, and it brought in the Ubuntu system Python packages `requests`, `urllib3` and `certifi`. `python3` (standard library only, used by the run scripts) and `lsb-release` are installed explicitly.
- **No build-host files in the image.** `.dockerignore` leaves out `__pycache__` folders and `.pyc` files.
- **Faster rebuilds.** `GIT_REVISION` is declared at the labels, so a new commit no longer invalidates the build cache of every step.
- **Tests.** New `tests/test_sync_mode.sh` runs a full MOVES run in sync mode through rclone with a remote defined only in environment variables, plus the configuration-error (exit 5) and fetch-failure (exit 2) paths. `tests/test_dockerfile_static.sh` now joins continuation lines correctly (it matched lines containing `$`), skips comments, and checks the changes above.

### What did not change

EPA MOVES at commit `2c4cd1ab...`: its Java and Go source, its database, its bundled Java libraries and the Windows-only tools EPA ships prebuilt in `tools/`. Apart from the two Go programs compiled from EPA's source, every file under `/cat/EPA_MOVES_Model` is byte-identical to 3.0.0 (3,024 of 3,026 files). The R packages and R 4.5.2 are identical to 3.0.0.

### Results did not change

- Tompkins County, NY, 2022 (`inputs_ny`): `OVERALL: PASS` against the reference, maximum relative difference 0.0 on all three output files, and the three files are byte-identical to the 3.0.0 run.
- Richmond County, NY, 2022 (`inputs2`), run on 3.0.0 and on 3.1.0: the three output files are byte-identical.
- Sync mode: `data.csv` equals the reference (maximum relative difference 0.0).
- Cloud MOVES on AWS Fargate, Tompkins 2025: the result equals the known reference result.

### Scan

`docker scout cves`, critical and high only: 15 critical and 84 high, against 25 and 171 in 3.0.0 and 60 and 350 in v2. Every remaining finding is inside EPA's MOVES tree, left as EPA ships it:

| Component | Critical | High | Where |
|---|---|---|---|
| Go standard library 1.21.4 and 1.21.6 | 12 | 73 | EPA's prebuilt Windows tools `tools/MOVESOutputGrouper.exe` and `tools/OpModeDistCalc.exe` (not run on Linux) |
| dom4j 1.6.1 (two entries), xmlbeans 2.3.0 | 3 | 2 | `libs/poi/`, Java libraries EPA bundles |
| MySQL connector 5.1.17, xerces 2.6.2, POI 3.9, commons-io 2.11.0 | 0 | 9 | `libs/`, Java libraries EPA bundles |

Gone since 3.0.0: Go 1.13.8 (9 critical, 78 high: the Go toolchain, rclone 1.50.2 and MOVES's two Go programs as 3.0.0 compiled them), Ubuntu's Ant 1.10.7 (1 high) and the system Python `certifi` and `urllib3` (1 critical, 8 high).

### Rollback

Set `MOVES_IMAGE=tmf77/moves-anywhere:v3.0.0` (or pass `--image`) to run 3.0.0; `v2` is also unchanged.

## 3.0.0

Image `tmf77/moves-anywhere:v3` (also `v3.0.0`). `v2` is unchanged and stays available.

### What changed since v2

- **Slimmer, pinned image.** EPA MOVES is pinned to one commit (`MOVES_COMMIT`, fetched once, shallow) and compiled at build time, not on every run. The MOVES tree and the default database are written in one layer. The image drops gcloud and gcsfuse (about 9.16 GB to 4.12 GB locally). Package versions are listed in [`docs/PINS_v3.md`](docs/PINS_v3.md). (#4)
- **Ticket mode.** A run can take its inputs from and send its outputs to a ticket, described in [`docs/RUN_TICKET.md`](docs/RUN_TICKET.md). (#3, #5)
- **Run manifest.** Every run ends by writing `run_manifest.json`, the one file that says the run is over, whether it succeeded, and a checksum for every input and output. Described in [`docs/RUN_MANIFEST.md`](docs/RUN_MANIFEST.md). (#3, #5)
- **Replication kit.** A run can pack its inputs, settings and outputs into a kit; see [`docs/REPLICATION_KIT.md`](docs/REPLICATION_KIT.md). (#5)
- **Runtime debug switch.** MOVES debug data is switched on with `"debug": true` in `parameters.json`, not at build time. (#4)
- **`run.sh` and `run.ps1`.** One command runs a local folder of inputs, and the script exits `0` only when the run produced results. Both now default to the `v3` image. (#7)
- **Failed runs say so.** A run with no results reports `failed` (#6). A failed R step or adapter stops the run with that step's exit status and a `stop_reason`, and the adapt step names the table that failed (#12).
- **`compare_outputs.py`.** An exact per-key comparison of two MOVES output folders, used to check that a run matches a reference run. (#2)
- **Apache License 2.0.** The repository was relicensed from GPL-3.0. (#1)
- **Documentation.** The README has the new look and the published citation, and its repository links and `catr` install commands are fixed (#8, #9). Every script carries one standard header, and `CONTRIBUTING.md` describes it (#10). The guides were corrected (#11), the scripts guide is generated from the headers (#13), and the guides have an index, top and tail links and a `CITATION.cff` (#14). A test runs every command in the README (#15).

### Frozen interfaces

- The run manifest (`manifest_version: 1`) and the run ticket are both frozen at v3.0.0: fields are not removed or renamed within v3. See [`docs/RUN_MANIFEST.md`](docs/RUN_MANIFEST.md) and [`docs/RUN_TICKET.md`](docs/RUN_TICKET.md).
- R packages are the current CRAN versions at build time, listed in [`docs/PINS_v3.md`](docs/PINS_v3.md).

### Known limits

- The image is built for `linux/amd64` (Intel/AMD). It has not been tested on Apple-silicon Macs.
- `catr` 0.2.0 still imports the Google R packages (`gargle`, `googleAuthR`, `googleCloudStorageR`), so they stay in the image at their v2 versions. No Google service is needed to run.

### Rollback

Set `MOVES_IMAGE=tmf77/moves-anywhere:v2` (or pass `--image`) to run the previous image. `v2` is not modified by this release.

### Failure handling, detail

- A failed R step in `launch.sh` (check packages, adapt, create database, create importer, postprocess, summarize) now stops the run with that step's exit status and a `stop_reason`, instead of limping on.
- `task_adapt.R` names the adapter that failed: `adapt failed on <table>: <first error line>`. New ticket-mode test: `moves_anywhere/tests/test_bad_table.sh`.
- In mounted mode a failed step exits non-zero and prints the reason to the log, and no manifest is written; in ticket mode the failed manifest carries the reason.
