# `moves_anywhere` <a href="https://github.com/timothyfraser/moves_anywhere"><img src="docs/img/movesanywhere_hexagon.png" align="right" height="200"/></a>

**Run EPA MOVES anywhere: on Windows, Mac, or Linux, in one Docker container.**

![Docker image](https://img.shields.io/badge/docker-tmf77%2Fmoves--anywhere%3Av2-2496ED?logo=docker&logoColor=white) ![R package](https://img.shields.io/badge/R-catr%200.2.0-276DC3?logo=r&logoColor=white) ![License](https://img.shields.io/badge/license-Apache%202.0-green)

-   Lead Developer: [Tim Fraser, PhD](https://github.com/timothyfraser) `<tmf77@cornell.edu>`
-   Contributors: Erin Murphy, Junna Chen, Mahak Bindal, Shungo Najima, Carl Closs
-   Institution: Gao Labs @ Cornell University

> **Image versions (2026-11):** `tmf77/moves-anywhere:v2` is the supported, released image. **`v3` is under
> active development and is not yet released for public use**: its Dockerfile is on `main` so the work is
> open, but nothing is published to a registry under the `v3` tag yet and its interfaces (`MOVES_IO`
> ticket mode, `run_manifest.json`, the replication kit) may still change. Use `v2` until a release note
> here says otherwise.

## Contents

-   [Welcome!](#welcome)
-   [Quick start](#quick-start)
-   [What you get back](#what-you-get-back)
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

Results land in the same folder as your inputs. The run manifest and replication kit are part of `v3`, which is not released yet.

| File | What it is |
|----|----|
| `data.csv` | Emissions and activity in CAT Format, ready for analysis |
| `movesoutput.csv`, `movesactivityoutput.csv` | The raw MOVES output tables |
| `moveslog.txt` | The full MOVES log |
| `run_manifest.json` | A record of the run: status, file hashes, MOVES version, timings. See [the run manifest](docs/RUN_MANIFEST.md) |
| `replication.tar.xz` | Everything needed to rerun this result on a stock MOVES install. See [the replication kit](docs/REPLICATION_KIT.md) |

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
| `tmf77/moves-anywhere:v2` | Released | The supported image; `run.sh` and `run.ps1` use it by default. |
| `tmf77/moves-anywhere:v3` | In development | Not released for public use. Its Dockerfile is on `main`; see [version pins](docs/PINS_v3.md). |

## Citation

To cite this package, please tentatively cite:

-   Fraser, Timothy & Gao, H. Oliver. (2025). Distributed Cloud Computing for Clean Transportation, Community Health, & Climate Action Anywhere. Cornell University Systems Studio Working Paper.

<p align="center"><a href="https://github.com/timothyfraser/moves_anywhere"><img src="docs/img/movesanywhere_hexagon.png" height="60"/></a><br/><sub>MOVES Anywhere · Apache 2.0 · Gao Labs @ Cornell University</sub></p>
