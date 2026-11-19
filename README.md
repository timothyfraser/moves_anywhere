# `moves_anywhere` <a href="https://github.com/timothyfraser/moves_anywhere"><img src="docs/img/movesanywhere_hexagon.png" align="right" height="200"/></a>

**Run EPA MOVES anywhere: on Windows, Mac, or Linux, in one Docker container.**

The image is built for x86-64 (`linux/amd64`). It is tested on Linux and on Windows; Apple-silicon Macs are untested.

![Docker image](https://img.shields.io/badge/docker-tmf77%2Fmoves--anywhere%3Av3-2496ED?logo=docker&logoColor=white) ![R package](https://img.shields.io/badge/R-catr%200.2.0-276DC3?logo=r&logoColor=white) ![License](https://img.shields.io/badge/license-Apache%202.0-green)

-   Lead Developer: [Tim Fraser, PhD](https://github.com/timothyfraser) `<tmf77@cornell.edu>`
-   Contributors: Erin Murphy, Junna Chen, Mahak Bindal, Shungo Najima, Carl Closs
-   Institution: Gao Labs @ Cornell University

> **Image versions:** `tmf77/moves-anywhere:v3` (also `v3.1` and `v3.1.0`) is still the current release (3.1.0), and
> `run.sh` and `run.ps1` use it by default. Release 3.2.0 (project-scale runs) is the coming release, built and
> tested from this branch; its Docker tags are not published yet. `v3.0.0` and `tmf77/moves-anywhere:v2` are the previous images and are
> unchanged. See the [changelog](CHANGELOG.md) for what changed.

## Contents

-   [Welcome!](#welcome)
-   [Quick start](#quick-start)
-   [What you get back](#what-you-get-back)
-   [Project-scale runs](#project-scale-runs)
-   [Cheatsheet](#cheatsheet)
-   [What's in this repository](#whats-in-this-repository)
-   [Documentation](#documentation)
-   [The `catr` package](#the-catr-package)
-   [Versions](#versions)
-   [Citation](#citation)

## Welcome!

Welcome to `moves_anywhere`! This software suite includes several tools to help you run the Environmental Protection Agency's **MO**tor **V**ehicle **E**mission **S**imulator (MOVES) more easily. Developed by Tim Fraser and colleagues at Gao Labs at Cornell University, `moves_anywhere` aims to solve several common problems for planners, engineers, and researchers who need to know how many tons of emissions are produced from on-road transportation sources in their county or state. These problems include:

-   Writing `runspec.xml` documents faster (a recipe for your MOVES run)
-   Running MOVES on any OS (Windows, Mac, or Linux), using a Docker container.
-   Running MOVES with custom inputs when you have *some (or none)* of the required custom input tables, but not all.
-   Post-processing MOVES inventory output data into the more dataviz-friendly "CAT Format", developed for Cornell's Climate Action in Transportation (CAT) team's research.
-   Packing every run into a replication kit, so anyone can check your numbers.

## Quick start

You need [Docker Desktop](https://www.docker.com/products/docker-desktop/) and [R](https://cran.r-project.org/). Nothing else: no MOVES install, no MySQL, no cloud account.

**1. 📝 Write a runspec** (the recipe for your run) with `catr`:

``` r
library(catr)
dir.create("inputs", showWarnings = FALSE)
custom_rs(.geoid = "36109", .year = 2025, .path = "inputs/rs_custom.xml")
```

**2. 📂 Add any custom input tables you have** to the same folder, as `<tablename>.csv`. Have none? That's fine. `moves_anywhere` fills in the rest from MOVES defaults.

**3. ▶️ Run it:**

``` bash
bash moves_anywhere/run.sh inputs
```

``` powershell
powershell -ExecutionPolicy Bypass -File moves_anywhere\run.ps1 inputs
```

✅ The script exits `0` only when the run produced results.

## What you get back

Results land in the same folder as your inputs. The run manifest and replication kit are part of `v3`.

| File | What it is |
|----|----|
| `data.csv` | Emissions and activity in CAT Format, ready for analysis |
| `movesoutput.csv`, `movesactivityoutput.csv` | The raw MOVES output tables |
| `moveslog.txt` | The full MOVES log |
| `run_manifest.json` | A record of the run: status, file hashes, MOVES version, timings. See [the run manifest](docs/RUN_MANIFEST.md) |
| `replication.tar.xz` | Everything needed to rerun this result on a stock MOVES install. See [the replication kit](docs/REPLICATION_KIT.md) |

## Project-scale runs (beta)

**Beta.** Project runs are a beta feature. Check results before you rely on them, and tell us what you find.

A county run estimates emissions for a whole county over a year. A project run (MOVES's *project scale*) estimates emissions on specific roads for one hour. Each piece of road is a **link**, with a length in miles and a traffic volume in vehicles for that hour. Each link has a **road type**, the MOVES code for the kind of road: 4 is an urban freeway, 5 is an urban arterial, and 1 is a parking lot or truck stop. Project runs come with release 3.2.0, whose image is not published yet (see [Versions](#versions)).

You give a few settings, and either your own links (`link.csv`) or a box on a map. The image fills in the rest from the county's data and from MOVES defaults (the table is in [what is filled in for you](docs/README_project_scale.md#what-is-filled-in-for-you-and-how-far-to-trust-it)). To try it, copy `moves_anywhere/inputs_project/` (six road links and a parking lot) to a new folder `my_project`. Delete its `rs_custom.xml`, the run file (MOVES calls it a runspec) that tells MOVES what to compute; the image writes a new one. Then put this in its `parameters.json`:

```json
{"level": "project", "geoid": "36109", "year": 2022, "month": 7, "day": "weekday", "hour": 8}
```

Then run it:

```bash
bash moves_anywhere/run.sh my_project
```

The results by link are in `my_project/linkdata.csv`.

With no `link.csv`, add `"place": "west,south,east,north"` (a box in decimal degrees of longitude and latitude) to `parameters.json`. The link builder, which is in beta, then makes the links from federal data: road sections and traffic counts from FHWA's Highway Performance Monitoring System (HPMS), and grade from USGS 3DEP elevation. With `place` in `parameters.json`, MOVES runs straight after the build. To check the links first, build them with `bash moves_anywhere/links.sh` (see [Building links](docs/README_link_sources.md)), then run MOVES.

What has been measured:

- EPA's MOVES5 training-course project exercise, run in this image: all 21 rows match EPA's answer, with a largest relative difference of 5e-8. <!-- source: epa_moves5_exercise/comparison_run1b.csv -->
- With the default vehicle ages, a project run built to copy a county's speeds agrees with the county run to within 2% per mile for NOx, exhaust PM2.5 and CO2. <!-- source: release/county_vs_project_default.csv -->

Project runs are for screening, research and teaching. EPA's guidance for regulatory hot-spot analysis expects project-specific traffic data, and the defaults here do not replace that.

Guides: [project-scale runs](docs/README_project_scale.md) and [building links from federal road data (beta)](docs/README_link_sources.md).

## Cheatsheet

📂 To get started, check out [our cheatsheet](docs/img/moves-anywhere-cheatsheet.png):

![](docs/img/moves-anywhere-cheatsheet.png)

## What's in this repository

| Folder | What's inside |
|----|----|
| [`moves_anywhere/`](moves_anywhere/) | The Docker image: `Dockerfile`, the run scripts, and the pipeline in [`scripts/`](moves_anywhere/scripts/) |
| [`catr/`](catr/) | The `catr` R package: write runspecs, read MOVES output, make CAT Format |
| [`docs/`](docs/) | Guides and reference |
| [`validation/`](validation/) | Validation analyses against EPA's own runs |
| [`docker_moves/`](docker_moves/) | The older base image, kept for reference |

## Documentation

| Guide | Read it when you want to... |
|----|----|
| [MOVES inputs](docs/README_MOVES_inputs.md) | know which input tables MOVES needs and what goes in them |
| [Project-scale runs](docs/README_project_scale.md) | estimate single road links and parking lots for one hour |
| [The pipeline scripts](docs/README_scripts.md) | see what happens inside the container, step by step |
| [The `catr` package](docs/README_catr.md) | write runspecs and work with results in R |
| [The run manifest](docs/RUN_MANIFEST.md) | read or check `run_manifest.json` |
| [The replication kit](docs/REPLICATION_KIT.md) | rerun a result on a stock MOVES install |
| [Run tickets](docs/RUN_TICKET.md) | run `moves_anywhere` from your own cloud service |
| [Version pins](docs/PINS_v3.md) | see exactly which MOVES, R and package versions are inside |
| [Developer tools](docs/README_dev.md) | build and test the image yourself |
| [All guides](docs/README.md) | see the index of every guide |

## The `catr` package

Data processing in **MOVES Anywhere** is supported by our `catr` package in `R`. Need to install `catr`?

✅ To install the latest from source, use the `remotes` package:

``` r
remotes::install_github("timothyfraser/moves_anywhere", subdir = "catr")
```

✅ To install a specific version (e.g., 0.2.0):

``` r
remotes::install_url("https://github.com/timothyfraser/moves_anywhere/raw/main/catr/catr_0.2.0.tar.gz")
```

## Versions

| Image | Status | Notes |
|----|----|----|
| `tmf77/moves-anywhere:v3` (`v3.1`, `v3.1.0`) | Current release | `run.sh` and `run.ps1` use it by default; see [version pins](docs/PINS_v3.md) and the [changelog](CHANGELOG.md). |
| `3.2.0` (not published yet) | Coming release | Built and tested from this branch; no Docker tag exists yet. Adds project-scale runs; see the [changelog](CHANGELOG.md). |
| `tmf77/moves-anywhere:v3.0.0` | Previous release | Unchanged. Same MOVES and scripts as 3.1.0; it still holds the Go 1.13 toolchain, Ubuntu's Ant and rclone, and the system Python packages that 3.1.0 removes or replaces. |
| `tmf77/moves-anywhere:v2` | Older release | Unchanged; use it by setting `MOVES_IMAGE=tmf77/moves-anywhere:v2`. |

## Citation

To cite this package, please tentatively cite:

-   Fraser, Timothy & Gao, H. Oliver. (2025). Distributed Cloud Computing for Clean Transportation, Community Health, & Climate Action Anywhere. Cornell University Systems Studio Working Paper.

<p align="center"><a href="https://github.com/timothyfraser/moves_anywhere"><img src="docs/img/movesanywhere_hexagon.png" height="60"/></a><br/><sub>MOVES Anywhere · Apache 2.0 · Gao Labs @ Cornell University</sub></p>
