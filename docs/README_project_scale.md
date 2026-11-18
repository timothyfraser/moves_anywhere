# `README`: project-scale runs

Part of the MOVES Anywhere guides: see the [index](README.md). The reasoning, assumptions, measurements and known weaknesses behind this guide are in [PROJECT_SCALE_DESIGN.md](PROJECT_SCALE_DESIGN.md).

## What project scale is

A county run estimates a whole county for a year. A project run estimates individual pieces of road, called **links**, for exactly one hour, one day type (weekday or weekend), one month, one year and one county. You give the length and traffic volume of each link. A link has a **road type**, a MOVES code for the kind of road (4 is an urban freeway, 5 is an urban arterial). A parking lot or truck stop is an **off-network link**: road type 1 (`roadTypeID` 1), where engines start and trucks idle. MOVES describes vehicles by **source type** (the vehicle type, such as passenger car or combination truck) and by **operating mode** (how the engine is working: idling, cruising at a speed band, braking). For starts, it uses **soak time**: how long the engine was off before it started. A longer soak means a colder start and more emissions.

Project runs use the same `run.sh` as county runs. The image reads your `link.csv`, fills in everything else from county data, runs MOVES, and writes the results by link.

## What you put in the folder

Put these files in the run folder, next to the others a county run uses. Column names are exact; capitals do not matter.

| File | Needed | Columns | What a blank means |
|----|----|----|----|
| `rs_custom.xml` | Required | The run file; see the next section. | n/a |
| `link.csv` | Required | `linkID`, `roadTypeID`, `linkLength` (miles), `linkVolume` (vehicles in the hour) are required. Optional: `linkAvgSpeed` (mph), `linkAvgGrade` (percent), `linkDescription`, `countyID`, `zoneID`. | Blank `linkAvgSpeed` on a road link: taken from the link's drive schedule if it has one (its mean speed), else from the county's speed distribution. Blank grade is 0. Blank `countyID` and `zoneID` are filled (county, and county times 10). A given `countyID` or `zoneID` must match the run's county. Description is cut at 50 characters. An `aadt` column is ignored in this release. |
| `offnetworklink.csv` | Required if any link has `roadTypeID` 1 | `sourceTypeID` and `vehiclePopulation` (vehicles in the lot) are required. Optional: `startFraction` (share of them that start in the hour), `extendedIdleFraction`, `parkedVehicleFraction`; each 0 to 1. | A vehicle type you leave out gets population 0. Blank `startFraction` is filled (see below). Blank `extendedIdleFraction` is 0. Blank `parkedVehicleFraction` is 1. |
| `linksourcetypehour.csv` | Optional | `linkID`, `sourceTypeID`, `sourceTypeHourFraction`. Shares of each road link's traffic by vehicle type; they must add up to 1 for each link. | A road link with no rows gets the default vehicle mix. No rows for the off-network link. |
| `driveschedulesecondlink.csv` | Optional | `linkID`, `secondID` (1, 2, 3, ...), `speed`; optional `grade`. A second-by-second speed trace of one link. | Blank grade is 0. Road links only. |
| `opmodedistribution.csv` | Optional | `sourceTypeID`, `hourDayID`, `linkID`, `polProcessID`, `opModeID`, `opModeFraction`. `hourDayID` is the hour times 10 plus the day (hour 8 on a weekday is 85). | If you give rows for the off-network link, they replace the default soak times. |

County tables (fuel, vehicle ages, weather and so on) are supplied the same way as in a county run; see [MOVES inputs](README_MOVES_inputs.md). The fixture `moves_anywhere/inputs_project/` is a complete example: seven links, one with a drive schedule, one parking lot.

## How to get a project `rs_custom.xml`

A project run file is a county run file with different settings. The image refuses a run file that breaks any of these rules:

1. One county, and nothing else selected (no state or nation).
2. One year.
3. One month.
4. One day type.
5. One hour: `beginhour` and `endhour` are the same.
6. Time is aggregated by Hour, and the output time step is Hour.
7. Results are by LINK.
8. Mass is in Grams, distance in Miles, time in Hours.
9. The scale is Inv (inventory). Rate mode is not supported.
10. The input database is `custom`, and `link.csv` is in the folder.
11. Every road type the run file selects has at least one link in `link.csv`.
12. In a county with no vehicle inspection (I/M) programme, MOVES's own input validation is off: `<skipdomaindatabasevalidation selected="true"/>`. With it on, MOVES treats the empty inspection table as missing and stops without a reason. The helper below writes it off, as `catr` does for county run files; the rules here do the checking instead.
13. The folder holds no county result (`data.csv` or `data.csv.gz`) from an earlier run. Use a new folder for a project run.

The domain is `<modeldomain value="PROJECT"/>`, which is what tells the image this is a project run. You can write the file by hand, or let the helper `task_runspec.R` make it. Set `LEVEL=project` and give `GEOID`, `YEAR`, `MONTH`, `DAY` (2 for weekend, 5 for weekday) and `HOUR` (1 to 24; hour 8 is 7:00 to 7:59) as environment variables. `ROADTYPES` (for example `1,4,5`) is optional; without it the helper reads the road types in `inputs/link.csv`. The helper keeps only the processes tested at project scale (running exhaust, brake wear, tire wear, crankcase running exhaust, and with road type 1 also starts, crankcase start, extended idle and auxiliary power) and checks the result against the rules above.

The worked example is `moves_anywhere/inputs_project/rs_custom.xml`: Tompkins County, NY (36109), 2022, month 7, day 5 (weekday), hour 8, road types 1, 4 and 5.

## How to run it

Run it as you run a county run: `run.sh <folder>`. The [main README](../README.md) explains `run.sh`. A full run of the fixture takes about 8 minutes of MOVES time.

**A second example: EPA's training exercise.** The folder `moves_anywhere/inputs_epa_project/` is a project run taken from EPA's own MOVES5 Hands-on Training Course (September 2025, Module 7, Project Exercise, Answer Key): a truck terminal and its roads in Washtenaw County, MI (26161), January 2025, a weekday, hour 9, carbon monoxide, five road links and one off-network link. EPA is the source of every number in it; the folder's `README.md` gives the attribution and every change made. Its purpose is a check against someone else's answer: `epa_movesoutput.csv` holds EPA's results, and `tests/compare_epa_project.py` compares a run of the folder with them. The result of that comparison for run 1: <!-- A5: AUD/epa_moves5_exercise/comparison_run1.csv -->

**Two years.** The two-year check (2019 and 2040): <!-- A13: AUD/release/years_2019_2040.csv -->

## What is filled in for you, and how far to trust it

Defaults are county averages. A link's traffic volume and length always come from you, and so does the number of vehicles in a parking lot.

| Input | Where the default comes from | When to replace it |
|----|----|----|
| Vehicle mix on a road link | The county's yearly mileage by vehicle type, times that month's, day type's and hour's share, times the share on that road type | Always for a truck route, a bus lane or any road whose traffic you know. |
| Link speed | The county's speed distribution for that road type and hour, averaged as miles divided by hours; or the link's drive schedule | When you know the speed. A real link can be far from the county average. |
| Grade | 0 (flat) | When the link is not flat. In the fixture, a 4 percent grade changes CO2 on the link by about 45 percent (282,026 g against 194,936 g). |
| Engine starts on a parking lot | Starts per vehicle per day in the county, times that hour's share of the day's starts | Almost always. This is the average vehicle in the county, not your lot. |
| Extended idle and parked share | 0 and 1 | When trucks idle or park at the site. |
| Soak times | MOVES's national start operating-mode table for that day type and hour, weighted by the county's vehicle ages | When you know how long vehicles sit. |
| Vehicle ages | The national age table, **travel-weighted** (next section) | When you know the ages of the vehicles on the link. Give your own `sourcetypeagedistribution.csv`. |
| Fuel, weather, inspection programme | The county adapters of a county run | As for a county run. |

### Vehicle ages: travel-weighted

An age table says what share of the *registered* vehicles of a type is each age. Older vehicles are driven fewer miles. At county scale MOVES weights each age by its mileage before it shares out the miles; at project scale it does not, and reads the table as the ages of the traffic on the link. So the image multiplies each age share by MOVES's relative mileage for that age and rescales the shares to add up to 1, for each vehicle type and year. **Travel-weighted** means the ages are those of the vehicles actually driving on the link, not those of the vehicles registered.

The effect of this default on the results (a county run against a project run, with and without it): <!-- A8: county vs project with the default, AUD/release/county_vs_project_default.csv -->

To keep the registration ages instead, set `PROJECT_AGES=registration` in the environment, or put `"project_ages": "registration"` in `parameters.json` in the run folder. The environment variable wins. Any other value stops the run. A `sourcetypeagedistribution.csv` that you supply is used as given, with no weighting. `diagnostics.txt` and `_project_inputs.csv` record which ages were used.

**County ages (off by default).** The default age table is national. With `AGE_SOURCE=county` (or `"age_source": "county"` in `parameters.json`), the run uses EPA's National Emissions Inventory age tables for the run's county: the county's own rows in 2020 and 2023, and in other years the national table adjusted age by age by the county-to-national ratio of the nearest inventory year (each ratio kept between 0.25 and 4). Long-haul truck types (53 and 62) always keep the national table. This needs the reference file `scripts/reference/nei_sourcetypeagedistribution.rds`, which is not in the repository; build it with `dev/make_nei_ages_reference.R`. If the file is missing or the county is not in it, the run uses the national table and says so in `_age_source.txt`; it does not fail. A table you supply still wins. For a project run the travel weighting is applied on top of whichever table is chosen.

## What you get back

`linkdata.csv` has one row per link, pollutant, process, vehicle type and fuel.

| Column | Meaning |
|----|----|
| `year`, `month`, `day`, `hour`, `geoid` | The run's time and county. |
| `link`, `roadtype` | The link and its road type. |
| `pollutant`, `process`, `sourcetype`, `fueltype` | MOVES codes (90 is CO2, 3 is NOx). |
| `emissions` | Grams in the hour. |
| `vmt` | Miles traveled in the hour. |
| `sourcehours` | Hours of driving (MOVES's "source hours operating"). Extended idle and hotelling hours on a parking lot are not here; they are in `movesactivityoutput.csv`. |
| `starts` | Engine starts. |
| `vehicles` | Vehicle population. |

The first rows of the fixture run:

```
year,month,day,hour,geoid,link,roadtype,pollutant,process,sourcetype,fueltype,emissions,vmt,sourcehours,starts,vehicles
2022,7,5,8,36109,1,5,1,1,11,1,7.139810085296631,5.614389896392822,0.22457599639892575,0,11.228799819946287
```

The activity columns repeat on every pollutant row of a link, vehicle type and fuel. Do not add `vmt` down the whole file. **Grams per mile** is the sum of `emissions` divided by the miles, counting miles once per link, vehicle type and fuel. **Grams per second** is grams divided by 3600. For link 1 of the fixture, CO2 is 194,936.1 g in 400 miles: 487.3 g per mile, or 54.1 g per second.

`diagnostics.txt` holds one line per link and the list of defaults used. This is the real file from the fixture run:

```
link,roadtype,description,miles,co2_g,nox_g,co2_g_per_mile,nox_g_per_mile,starts
1,5,arterial 25 mph flat,400,194936.1,313.6,487.3,0.784,0
7,1,parking lot and truck stop (off-network),0,86078.5,727.1,,,76.3

Inputs filled in by default or supplied by you:
link 5 linkAvgSpeed | default | 25.59 mph from avgspeeddistribution
vehicle mix, links 1, 2, 3, 4, 5, 6 | default | sourcetypeyearvmt x month, day, hour and road type shares
off-network startFraction | default | startsperdaypervehicle x startshourfraction
off-network extendedIdleFraction | default | 0
off-network parkedVehicleFraction | default | 1
start soak times (opmodedistribution) | default | startsopmodedistribution weighted by vehicle age
```

(Links 2 to 6 are left out here; the real file lists all seven.) A project run never writes `data.csv`, because that file means a county-year. `run_manifest.json` lists `linkdata.csv.gz` as the result. The adapted tables `_link.csv` and `_offnetworklink.csv` stay in the folder and show the values MOVES used.

A road link with `linkAvgSpeed` 0 is an idling queue. MOVES counts every vehicle in its volume as idling for the whole hour, so its grams are a rate per vehicle-hour times the volume. Scale them by the real delay. `diagnostics.txt` prints a note for each such link.

## When a run is refused

MOVES itself accepts a bad project command and then produces nothing, so the image checks first. The run stops with a reason, writes no `linkdata.csv`, and exits non-zero.

| Reason you see | What to fix |
|----|----|
| `needs exactly one county (found N selections)` | Select one county only. |
| `needs exactly one year`, `one month`, `one day type` | Keep one of each. |
| `more than one hour (8 to 9)` | Use the same `beginhour` and `endhour`; run each hour separately. |
| `aggregateBy must be Hour`, `outputtimestep must be Hour`, `geographicoutputdetail must be LINK` | Set the run file as in the rules above. |
| `massfactors units must be Grams` (also miles, hours) | Set the units. |
| `modelscale must be Inv; rates are not supported` | Use inventory mode. |
| `scaleinputdatabase must be custom` | Use the custom database. |
| `link.csv is missing from the inputs folder` | Add `link.csv`. |
| `link.csv needs column linkLength` (or another required column) | Add the column. |
| `link 3 roadTypeID 2 is not in the runspec` | Add the road type to the run file, or fix the link. |
| `runspec road type 4 has no link in link.csv` | Remove that road type from the run file, or add a link on it. |
| `no I/M programme here: set skipdomaindatabasevalidation to true` | The county has no inspection programme. Set that line in the run file to `selected="true"`. |
| `linkID 4 is repeated` | Give each link its own number. |
| `link 2 has no linkVolume` | Give every road link a volume. |
| `vehicle mix for link 1 sums to 0.9, not 1` | Make the shares add up to 1. |
| `vehicle mix for link 1 has a share outside 0 to 1` | Every share is between 0 and 1. |
| `folder holds a county result (data.csv); use a new folder` | Run the project in its own folder. |
| `off-network link needs offnetworklink.csv` | Add the file. |
| `offnetworklink.csv sourceTypeID not in the run's vehicle types` | Use vehicle types the run file selects. |
| `MOVES produced no results: ...` | MOVES refused the run. The reason ends with MOVES's own first error line; `moveslog.txt` in the folder has the rest. |

## Limits

- One hour per run. For several hours, make several runs, one folder each.
- Built for screening, research and teaching. EPA's guidance for regulatory hot-spot analysis expects project-specific traffic data and says there are no default values for off-network inputs. The defaults here do not replace that.
- The image uses MOVES5. MOVES6 exists; this image has not moved to it yet.
- Not tested: evaporative emissions, rate mode at project scale, runs with more than 7 links.
- Ticket mode (the CAT website's order path) does not carry project runs yet. Use `run.sh` or sync mode.

---

## For agents

Files that implement a project run (all in `moves_anywhere/scripts/`):

- `project_functions.R`: run-file reading (`is_project`, `project_spec`), rules R1 to R10 (`project_check`), county-table reads (`project_read`), default notes (`project_note`), run-file maker (`project_runspec`).
- `adapt_link.R`: `link.csv`, vehicle mix, drive schedules. `adapt_offnetwork.R`: `offnetworklink.csv`, soak times.
- `task_adapt.R`: calls the adapters for a project run only. `importer.R`, `task_check_import.R`: load and check the link tables.
- `task_postprocess.R`, `task_get_linkdata.R`: write `linkdata.csv`. `task_summarize.R`: `diagnostics.txt`. `task_pack.sh`: manifest result check.
- `task_runspec.R`: the `LEVEL=project` helper.

Tests, from the repository root: `Rscript moves_anywhere/tests/<name>.R` for `test_project_functions`, `test_adapt_link`, `test_adapt_offnetwork`, `test_importer_project`, `test_linkdata`, `test_runspec_project` (no Docker); `bash moves_anywhere/tests/test_pack_project.sh`; `bash moves_anywhere/tests/test_project.sh --image <image>` (Docker; full fixture run and refusals). The gate steps are `project-unit` and `project` in `moves_anywhere/tests/run_gate.sh`.

Age files: `adapt_projectage.R` (travel weighting and the `PROJECT_AGES` switch; called by `task_adapt.R` after the county adapters and before `adapt_link.R`), `adapt_ages_county.R` (the `AGE_SOURCE` setting and the county table; sourced by `adapt_sourcetypeagedistribution.R`). Tests: `tests/test_adapt_projectage.R`, `tests/test_adapt_ages_county.R`, `tests/test_nei_ages_reference.R`. The reference file is built by `dev/make_nei_ages.py` and `dev/make_nei_ages_reference.R`.

Gate and tests (all from the repository root; Docker for the ones that name an image):

- **Fast gate:** `bash moves_anywhere/tests/run_gate.sh --fast`. It runs `static`, `compare-unit`, `build`, `project-unit`, `replay` and only the refusals of `project`; it runs no MOVES. It takes several minutes (the script header says about 6, a measured run about 9). It is for working and is not a release gate: its last lines say so and list the steps left for the full gate. It cannot be combined with `--only`.
- **Replay test:** `bash moves_anywhere/tests/test_summarize_replay.sh --image <image>` runs only the summary step (`task_summarize.R`) on saved MOVES outputs, with no MOVES run: a county hour with no vehicle-population rows, the county fixture `inputs_ny`, and the project fixture. `--prove` also runs the first case against the image's own script and expects it to fail. The gate runs it as step `replay`.
- **EPA test:** `bash moves_anywhere/tests/test_epa_project.sh --image <image> [--run2]` runs `inputs_epa_project/` through `run.sh` and checks the exit code, the manifest, that `linkdata.csv` exists and `data.csv` does not, and EPA's run 1 against `movesoutput.csv` through `tests/compare_epa_project.py` (within 1 percent). `--run2` adds EPA's second run. It takes under 10 minutes of MOVES per run. <!-- epa step: the gate step that calls it is not in run_gate.sh yet -->

Rule: every change to an existing script sits behind a project-only branch, and the county fixture in the gate checks that county runs are unchanged.
