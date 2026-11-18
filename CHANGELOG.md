# Changelog

## 3.2.0 (release candidate)

Adds project-scale runs: individual road links and parking lots for one hour. Guide: [docs/README_project_scale.md](docs/README_project_scale.md).

### What changed

- **Project-scale runs from a folder.** A run file with `<modeldomain value="PROJECT"/>` is a project run. Give `rs_custom.xml` and `link.csv` (plus `offnetworklink.csv` for a parking lot, and optional vehicle mix, drive schedules and operating-mode tables) to the same `run.sh`. The image fills in the vehicle mix, link speed, grade, engine starts, soak times and the county tables, and records each default it used.
- **`linkdata.csv`.** The result of a project run: one row per link, pollutant, process, vehicle type and fuel, with grams, miles, hours, starts and vehicles. A project run never writes `data.csv`. `diagnostics.txt` lists each link and the defaults used. `linkdata.csv.gz` is the result in `run_manifest.json`.
- **Refusals with reasons.** A project run file that breaks rules R1 to R10 (one county, year, month, day type and hour; hourly link output; grams, miles, hours; inventory mode; custom database) or bad link inputs stop the run with a one-line reason, because MOVES itself accepts such a command and produces nothing.
- **`LEVEL=project` helper.** `task_runspec.R` makes a project run file from `GEOID`, `YEAR`, `MONTH`, `DAY`, `HOUR` and optional `ROADTYPES`.

- **Travel-weighted vehicle ages at project scale.** MOVES reads the age table as the ages of the traffic on a link at project scale, but weights by mileage only at county scale. A project run now multiplies each age share by MOVES's relative mileage and rescales it to 1 for each vehicle type and year. `PROJECT_AGES=registration` (or `"project_ages": "registration"` in `parameters.json`) keeps the registration ages. A user's own `sourcetypeagedistribution.csv` is used as given. County runs are unchanged.
- **County ages (off by default).** `AGE_SOURCE=county` (or `"age_source": "county"` in `parameters.json`) uses EPA's National Emissions Inventory county age tables, with a national fallback and a note if the reference file or the county is missing. The reference file is included in the image (11.8 MB; 3,223 counties for 2020 and 3,224 for 2023; built by `dev/make_nei_ages_reference.R`); the switch is off by default. On Tompkins County, NY (2022), it lowers NOx by about a third (county over national 0.676) and CO2 by about 4%, from a partial reference file measured before the full one was built; the default stays national until the effect is reviewed. <!-- source: release/county_ages_effect.csv -->
- **Link builder (beta).** `links.sh` builds a project run folder from live federal data (FHWA HPMS, USGS 3DEP): road type, length, hourly volume (with a year factor), vehicle mix from truck counts, grade, and a remainder link for uncounted roads. Every value is labelled measured, derived or default, and every response is saved. Guide: [docs/README_link_sources.md](docs/README_link_sources.md). A live build for a box in Ithaca, NY made 17 links in 87 s (10.2% of values default) and ran in MOVES in 371 s; 13 of 16 road links were within 10% of the flat fixture's CO2 per mile, and the three outliers are the steepest links. <!-- source: release/live_link_build/RESULT.md -->
- **Summary-step fix.** A run with no vehicle-population or CO2-equivalent rows no longer fails at the summary step; the fault was in 3.1.0 since 2025-03-25.
- **Partial-table fix.** A user table that covers only some vehicle types no longer stops the fuel-technology and age adapters; the types it leaves out take the national defaults.
- **Gate.** New step `replay` (the summary step on saved MOVES outputs, no MOVES run, `tests/test_summarize_replay.sh`); `run_gate.sh --fast` for the short gate (not a release gate); step 14, `epa` (full gate only; `tests/test_epa_project.sh`, about 3 minutes of MOVES). The four link-builder unit tests are part of `project-unit`.
- **EPA's training exercise as a fixture.** `inputs_epa_project/` is a project run from EPA's MOVES5 Hands-on Training Course (September 2025, Module 7, Project Exercise, Answer Key), with EPA's results and a comparison script (`tests/compare_epa_project.py`, `tests/test_epa_project.sh`). Source: US EPA; its folder README gives the attribution and every change. EPA's second run (drive schedules) is also reproduced: 21 of 21 rows, largest relative difference about 5e-8. <!-- source: epa_moves5_exercise/comparison_run2.csv -->
- **Tests no longer default to a path on one machine.** `test_ticket_mode.sh` defaulted its fixture to a path on one machine (since 3.1.0); it now defaults to the repository's `inputs_ny`. `testme.sh` and `testme_cloud.sh` use placeholders.

### What did not change

- In 3.1.0, a fuel-technology table that misses some strata inside a vehicle type it does cover gives those strata zero. This is unchanged.
- County runs: the same scripts path, with every change to an existing script behind a project-only branch. The gate's county fixture checks this.
- The run manifest schema: `manifest_version` stays 1.

### What is not included

- Ticket mode (the CAT website's order path) does not carry project runs yet.
- MOVES6: the image stays on MOVES5.
- Not tested: evaporative emissions and rate mode at project scale. Runs with 16 and 17 links have run (the live link build).

Checks: full gate PASS on commit aac249f, 14 steps in 2,367 s (static, compare-unit, build, county fixture, compare, manifest, pack, ticket, bad-table, sha, project-unit, project, replay, epa); EPA's MOVES5 course project exercise reproduced on both runs, 21 of 21 rows each, largest relative difference 5e-8; project against county scale with the age default, 16 urban links: NOx +1.5%, exhaust PM2.5 +1.8%, CO2 +0.1% per mile; 2019 and 2040 project runs complete; a 17-link live build of downtown Ithaca from federal data ran in MOVES in 371 s. <!-- source: release/gate_full.txt, epa_moves5_exercise/comparison_run1b.csv and comparison_run2.csv, release/county_vs_project_default.csv, release/years_2019_2040.csv, release/live_link_build/RESULT.md -->

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
