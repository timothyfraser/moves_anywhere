# MOVES Anywhere

EPA's MOVES 5 emissions model in a container, with the inputs filled in and the results packed.
Runs county totals, county emission rates, and project-scale (road link) runs. Built for linux/amd64.

## Start here

1. **Write the run file** with the `catr` R package: one call to `custom_rs()` makes the runspec for your county and year.
2. **Save `parameters.json`** beside it: it says what to report (pollutants, grouping, time and place).
3. **Run `run.sh`** (or `run.ps1` on Windows). Results appear beside your inputs as `data.csv`.

```
docker pull tmf77/moves-anywhere:v3
```

Full quick start, with the exact commands: https://github.com/timothyfraser/moves_anywhere#quick-start

## Choose your run

| Run | You give | You get | Guide |
|----|----|----|----|
| County totals | A run file, `parameters.json`, and your own tables if you have them | `data.csv` | [County runs](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_county_runs.md) |
| County emission rates | A run file made with `custom_rs(.rate = TRUE)`, and `parameters.json` | The rate tables (`rateperdistance.csv` and others) | [Emission rates](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_county_runs.md#emission-rates) |
| Project, your own links | `link.csv` and `parameters.json` | `linkdata.csv` | [Project-scale runs](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_project_scale.md) |
| Project for a place | `parameters.json` with a `place` box | The built links and `linkdata.csv` | [Link sources](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/README_link_sources.md) |

State and national runs are not supported.

## Tags

- `v3` = `v3.2` = `v3.2.0`: current release. Digest `sha256:3509df74aafd5164cfe3ac2afdf2f3f0c07c34c320f35ad9dc3ccbfe120d20c9`.
- `v3.1` / `v3.1.0`: security release of 3.0.
- `v3.0.0`: older release, unchanged.
- `v2`: older release, unchanged.

## Links

- [Source code](https://github.com/timothyfraser/moves_anywhere)
- [Changelog](https://github.com/timothyfraser/moves_anywhere/blob/main/CHANGELOG.md)
- [Run manifest: how to tell a run finished](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/RUN_MANIFEST.md)
- [Replication kit: rerun a result on stock MOVES](https://github.com/timothyfraser/moves_anywhere/blob/main/docs/REPLICATION_KIT.md)
- [How to cite](https://github.com/timothyfraser/moves_anywhere/blob/main/CITATION.cff)
- [Report a problem](https://github.com/timothyfraser/moves_anywhere/issues)
- [CAT, Climate Action in Transportation](https://cat-apps.com)
