# MOVES Anywhere

**EPA's MOVES 5 emissions model, ready to run in one command, on any computer.** It fills in the inputs you don't have, runs MOVES, and hands back tidy results with a record anyone can check.

Lead developer: **Tim Fraser** (Cornell University), with H. Oliver Gao, Gao Labs @ Cornell. It is the engine behind [CAT, Climate Action in Transportation](https://cat-apps.com): every county and project run ordered on CAT runs in this image.

[CAT website](https://cat-apps.com) · [GitHub](https://github.com/timothyfraser/moves_anywhere) · [Quick start](https://github.com/timothyfraser/moves_anywhere#quick-start) · [Choose your run](https://github.com/timothyfraser/moves_anywhere#choose-your-run)

[Changelog](https://github.com/timothyfraser/moves_anywhere/blob/main/CHANGELOG.md) · [How to cite](https://github.com/timothyfraser/moves_anywhere/blob/main/CITATION.cff) · [Report a problem](https://github.com/timothyfraser/moves_anywhere/issues)

## Why use it instead of installing MOVES

| Plain MOVES | MOVES Anywhere |
|---|---|
| Install MOVES, Java and a MariaDB database server, then load EPA's default database | `docker pull`; no MOVES install, no database server, no cloud account |
| Supply every county input table yourself | Give the tables you have; the rest are filled in from the county's data and MOVES defaults |
| Write the run file (runspec) by hand | One R call writes it (`catr::custom_rs()`) |
| Read raw MOVES output tables | Get `data.csv`: emissions and activity in one tidy table, in U.S. tons, miles and hours |
| Keep your own notes on what you ran | Every run writes a manifest (status, versions, a checksum per file) and a replication kit that reruns on stock MOVES |
| Draw road links for a project run | Give a box on a map; the link builder makes the links from federal road and elevation data |

## Start here

```
docker pull tmf77/moves-anywhere:v3
```

1. Clone the [GitHub repository](https://github.com/timothyfraser/moves_anywhere): `run.sh` (or `run.ps1` on Windows) comes with it.
2. Write a run file with the `catr` R package and save a short `parameters.json` beside it.
3. Run `bash moves_anywhere/run.sh inputs`. One county and one year takes about 10 minutes on a laptop.

The [quick start](https://github.com/timothyfraser/moves_anywhere#quick-start) has the exact commands; it is run for real on every documentation change.

## Choose your run

| Run | You give | You get | Guide |
|----|----|----|----|
| County totals | A run file, `parameters.json`, and your own tables if you have them | `data.csv` | [County runs](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_county_runs.md) |
| County emission rates | A run file made with `custom_rs(.rate = TRUE)` | Rate tables (`rateperdistance.csv` and others), in U.S. tons | [Emission rates](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_county_runs.md#emission-rates) |
| Project, your own links (beta) | `link.csv` and `parameters.json` | `linkdata.csv`, grams per link for one hour | [Project-scale runs](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_project_scale.md) |
| Project for a place (beta) | `parameters.json` with a `place` box | The built links and `linkdata.csv` | [Building links](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_link_sources.md) |

State and national runs are not supported.

## How it is checked

- EPA MOVES 5 is pinned to one commit and compiled into the image; the same inputs give the same numbers.
- Before release, a county fixture must match its reference exactly, and EPA's own project-level training exercise must match EPA's answer key within 1 percent.
- Each release's tests, scan results and fixes are in the [changelog](https://github.com/timothyfraser/moves_anywhere/blob/main/CHANGELOG.md).

## Tags

- `v3` = `v3.2` = `v3.2.0`: current release (digest `sha256:3509df74aafd5164cfe3ac2afdf2f3f0c07c34c320f35ad9dc3ccbfe120d20c9`).
- `v3.1` / `v3.1.0`: security release of 3.0. `v3.0.0` and `v2`: older releases, unchanged.
- Built for `linux/amd64`. Apache License 2.0.
