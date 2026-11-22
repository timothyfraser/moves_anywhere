# `README`: project-scale runs (beta)

**Beta.** Project runs are a beta feature. Check results before you rely on them, and tell us what you find.

Part of the MOVES Anywhere guides: see the [index](README.md). The reasoning, assumptions, measurements and known weaknesses behind this guide are in [PROJECT_SCALE_DESIGN.md](PROJECT_SCALE_DESIGN.md).

## What project scale is

A county run estimates emissions for a whole county over a year. A project run (MOVES's *project scale*) estimates emissions on individual pieces of road, called **links**, for exactly one hour, one day type (weekday or weekend), one month, one year and one county. You give the length and traffic volume of each link.

Terms used below:

- A link's **road type** is the MOVES code for the kind of road: 4 is an urban freeway, 5 is an urban arterial.
- An **off-network link** is a parking lot or truck stop: road type 1 (`roadTypeID` 1). Engines start and trucks idle there.
- A **source type** is MOVES's vehicle type, such as passenger car or combination truck.
- An **operating mode** is how the engine is working: idling, cruising in a speed band, or braking.
- **Soak time** is how long the engine was off before it started. A longer soak means a colder start and more emissions.

Project runs use the same `run.sh` as county runs. The image (the Docker package that holds MOVES and these scripts) reads your `link.csv`, fills in the rest from the county's data and from MOVES defaults, runs MOVES, and writes the results by link.

## Quick start: one settings file

A project run can start from one settings file. Make a new folder and put in it:

- `parameters.json`, with `"level": "project"` and the county, year, month, day type and hour;
- `link.csv`, or a `place` in `parameters.json` so that the image builds the links from federal road data first (see [Building links](README_link_sources.md)).

Then run `run.sh <folder>`. The image writes the run file, `rs_custom.xml`, itself. (The run file is what MOVES calls a runspec: the XML file that tells MOVES what to compute.) For example, copy the example folder `moves_anywhere/inputs_project/` (the test fixture, "the fixture" below) to a new folder, delete its `rs_custom.xml`, and save this whole file as its `parameters.json`:

```json
{"level": "project", "geoid": "36109", "year": 2022, "month": 7, "day": "weekday", "hour": 8}
```

These settings match the county, year, month, day type and hour in the fixture's own run file. The road types (1, 4 and 5) come from the folder's `link.csv`. The pollutants are the default list below, the same 21 that the fixture's run file selects. The next section lists every key.

## `parameters.json` for a project run

Only a `parameters.json` with `"level": "project"` is read this way. Without that key, or with any other value, the file is treated as a county run's settings and this step is skipped.

Upper or lower case does not matter in `level`, `day`, `age_source` and `project_ages`. Keys not in the table are ignored, and the log lists them (`parameters.json: ignored keys: ...`). A file that is not valid JSON stops the run with `parameters.json: not valid JSON (...)`.

A refused key stops the run before MOVES starts. The run ends with exit code 1 (an error status) and one line that names the key. For a missing required key the line is `parameters.json: <key> must be given for a project run: <allowed values>`; for a wrong value it is `parameters.json: <key> must be <allowed values>`. The table quotes the part after `must be`.

| Key | Needed | Allowed values | Default | If it is wrong |
|----|----|----|----|----|
| `level` | Required | `"project"` | none | Any other value, or none: a county run (see above). |
| `geoid` | Required | A 5-digit county FIPS code, as a string (`"36109"`) or a number (a lost leading zero is put back: `1001` is `01001`). The state must be one of the 50 states, DC or Puerto Rico. | none | `geoid must be a 5-digit county FIPS code, e.g. "36109"`; outside those states, `geoid must be a county FIPS code in one of the 50 states, DC or PR` |
| `year` | Required | 1990 to 2060 | none | `year must be a year from 1990 to 2060` |
| `month` | Required | 1 to 12 | none | `month must be a month from 1 to 12` |
| `day` | Required | `"weekday"` or `"weekend"`, or MOVES's codes 5 (weekday) and 2 (weekend) | none | `day must be "weekday", "weekend", 5 or 2` |
| `hour` | Required | 1 to 24, in MOVES's numbering: hour 8 is 7:00 to 7:59 | none | `hour must be an hour from 1 to 24 (8 is 7:00 to 7:59)` |
| `pollutant` | Optional | A list of MOVES pollutant IDs, for example `[90, 3]` | The 21 a county run file gets: 90, 98, 2, 118, 112, 119, 5, 33, 32, 6, 3, 100, 110, 106, 107, 116, 117, 115, 31, 91, 1 <!-- source: moves_anywhere/scripts/project_parameters.R, PROJECT_POLLUTANTS; moves_anywhere/inputs_ny/parameters.json --> | `pollutant must be a list of MOVES pollutant IDs (positive whole numbers)` |
| `roadtypes` | Optional | A list of road types from 1 to 5, for example `[1, 4, 5]` | The road types in `link.csv` | `roadtypes must be a list of road types from 1 to 5`. With no `roadtypes`, no `link.csv` and no `place`, the run stops with `task_runspec.R failed: could not make rs_custom.xml from parameters.json`. |
| `place` | Optional | A box `"west,south,east,north"` in degrees, or a 5-digit county FIPS code as a string | none: you give `link.csv` | `place must be a box "west,south,east,north" (degrees, west < east, south < north) or a 5-digit county FIPS code`. Used only when the folder has no `link.csv`. If the link builder refuses, the run stops with `links: ` and the builder's reason. |
| `max_links` | Optional | A whole number of 1 or more | 40 | `max_links must be a positive whole number` |
| `age_source` | Optional | `national`, `county` or `county_adjusted` (see "County ages" below) | `national` | The run stops at the adapt step with `age_source must be national, county or county_adjusted (found ...)`. |
| `project_ages` | Optional | `travel` or `registration` (see "Vehicle ages" below) | `travel` | The run stops at the adapt step with `project_ages must be travel or registration (found ...)`. |

What the image does with the file, in order:

1. If the folder has no `link.csv` and `parameters.json` gives a `place`, it builds the links first, as [`links.sh`](README_link_sources.md) does. The state comes from the first two digits of `geoid`, and `max_links` sets the link limit.
2. If the folder has no `rs_custom.xml`, it writes one from `parameters.json`.
3. If you supplied `rs_custom.xml`, your file is used, and the `pollutant` and `roadtypes` keys are not. It must name the same county, year, month, day type and hour as `parameters.json`, or the run stops with a line such as `parameters.json: rs_custom.xml disagrees on hour: run file 9, parameters.json 8`.

The run file is then checked against the rules in "How to get a project `rs_custom.xml`", as any project run file is. County runs never go through this step.

## What you put in the folder

Put these files in the run folder, next to the files a county run uses. Spell column names exactly as shown; upper or lower case does not matter.

| File | Needed | Columns | What a blank means |
|----|----|----|----|
| `parameters.json` | Required for the one-file start above; otherwise optional | The run's settings; see the section above. | n/a |
| `rs_custom.xml` | Required unless `parameters.json` says `"level": "project"` (then the image writes it) | The run file; see the next section. | n/a |
| `link.csv` | Required unless `parameters.json` gives a `place` (then the image builds it) | `linkID`, `roadTypeID`, `linkLength` (miles), `linkVolume` (vehicles in the hour) are required. Optional: `linkAvgSpeed` (mph), `linkAvgGrade` (percent), `linkDescription`, `countyID`, `zoneID`. | Blank `linkAvgSpeed` on a road link: taken from the link's drive schedule if it has one (its mean speed), else from the county's speed distribution. Blank grade is 0. Blank `countyID` and `zoneID` are filled (county, and county times 10). A given `countyID` or `zoneID` must match the run's county. Description is cut at 50 characters. An `aadt` column is ignored in this release. |
| `offnetworklink.csv` | Required if any link has `roadTypeID` 1 | `sourceTypeID` and `vehiclePopulation` (vehicles in the lot) are required. Optional: `startFraction` (share of them that start in the hour), `extendedIdleFraction`, `parkedVehicleFraction`; each 0 to 1. | A vehicle type you leave out gets population 0. Blank `startFraction` is filled (see below). Blank `extendedIdleFraction` is 0. Blank `parkedVehicleFraction` is 1. |
| `linksourcetypehour.csv` | Optional | `linkID`, `sourceTypeID`, `sourceTypeHourFraction`. Shares of each road link's traffic by vehicle type; they must add up to 1 for each link. | A road link with no rows gets the default vehicle mix. No rows for the off-network link. |
| `driveschedulesecondlink.csv` | Optional | `linkID`, `secondID` (1, 2, 3, ...), `speed`; optional `grade`. A second-by-second speed trace of one link. | Blank grade is 0. Road links only. |
| `opmodedistribution.csv` | Optional | `sourceTypeID`, `hourDayID`, `linkID`, `polProcessID`, `opModeID`, `opModeFraction`. `hourDayID` is the hour times 10 plus the day (hour 8 on a weekday is 85). | If you give rows for the off-network link, they replace the default soak times. |

County tables (fuel, vehicle ages, weather and so on) are supplied the same way as in a county run; see [MOVES inputs](README_MOVES_inputs.md). The fixture `moves_anywhere/inputs_project/` is a complete example: seven links, of which six are road links (one with a drive schedule) and one is a parking lot.

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
12. In a county with no vehicle inspection and maintenance (I/M) programme, MOVES's own input check is turned off: `<skipdomaindatabasevalidation selected="true"/>`. With the check on, MOVES treats the empty inspection table as missing and stops without giving a reason. The helper below turns the check off, as `catr` does for county run files; the rules on this list do the checking instead.
13. The folder holds no county result (`data.csv` or `data.csv.gz`) from an earlier run. Use a new folder for a project run.

The line `<modeldomain value="PROJECT"/>` is what tells the image this is a project run. With a project `parameters.json` (see the quick start) you do not need to write this file: the image writes it with `task_runspec.R` from the values in `parameters.json`.

You can still write the file by hand, or run the helper `task_runspec.R` yourself.

Give it these environment variables (named settings in the shell that runs it): `LEVEL=project`, `GEOID`, `YEAR`, `MONTH`, `DAY` (2 for weekend, 5 for weekday) and `HOUR` (1 to 24; hour 8 is 7:00 to 7:59).

`ROADTYPES` (for example `1,4,5`) is optional; without it the helper reads the road types in `inputs/link.csv`. The helper keeps only the MOVES processes tested at project scale, and checks the result against the rules above.

Those processes are running exhaust, brake wear, tire wear and crankcase running exhaust; with road type 1, also starts, crankcase start, extended idle and auxiliary power.

The worked example is `moves_anywhere/inputs_project/rs_custom.xml`: Tompkins County, NY (36109), 2022, month 7, day 5 (weekday), hour 8, road types 1, 4 and 5.

## How to run it

Use the published image `tmf77/moves-anywhere:v3` (`run.sh` pulls it). One order of steps that works:

1. Make a new folder, for example `my_project`. Use a new folder: it must not hold a county result.
2. Save a full `parameters.json` in it:

   ```json
   {"level": "project", "geoid": "36109", "year": 2022, "month": 7, "day": "weekday", "hour": 8}
   ```

3. Give it links. Either copy `link.csv` (and `offnetworklink.csv` if a link has road type 1) from `moves_anywhere/inputs_project/`, or add `"place": "-76.52,42.42,-76.47,42.46"` (a box, `west,south,east,north`) to `parameters.json` so the image builds them from federal data.
4. Run `bash moves_anywhere/run.sh my_project`. The image writes `rs_custom.xml` itself. The [main README](../README.md) explains `run.sh`. A full run of the fixture takes about 8 minutes of MOVES time.
5. After a place run, open `link_summary.txt` first: it says what was built and what was left out. Results are in `linkdata.csv`.

To check the links before MOVES runs, use `links.sh`. It needs a run file, and the only one outside the image is the shipped example's: `cp moves_anywhere/inputs_project/rs_custom.xml my_project/`. See [Building links](README_link_sources.md).

**A second example: EPA's training exercise.** The folder `moves_anywhere/inputs_epa_project/` is a project run taken from EPA's own MOVES5 Hands-on Training Course (September 2025, Module 7, Project Exercise, Answer Key). It models a truck terminal and its roads in Washtenaw County, MI (26161): January 2025, a weekday, hour 9, carbon monoxide, five road links and one off-network link.

Every number in it comes from EPA; the folder's `README.md` gives the attribution and lists every change made. The folder lets you check the image against an answer someone else computed: `epa_movesoutput.csv` holds EPA's results, and `tests/compare_epa_project.py` compares a run of the folder with them.

For run 1 (carbon monoxide, 21 rows of EPA's answer), all 21 rows are within 1 percent of EPA's, and the largest relative difference is 5.0e-8. The run took 188 seconds in all.

A first attempt did not match, because it left out two input tables that EPA's run had filled: the fuel and technology table and the hotelling table. With those supplied, the results match. <!-- measured; record kept by the maintainers -->

**Two years.** A two-year check ran 2019 and 2040, each with the same set of pollutant-process pairs that a county run file gets (84 pairs). NOx and exhaust PM2.5 per mile fall on every road link from 2019 to 2040. CO2 per mile in 2040 is about 45 percent of 2019 (link 1: 214 g against 484 g per mile).

MOVES took 876 seconds for 2019 and 963 seconds for 2040 on a busy machine (the EPA exercise run took 188 seconds in all).

One range check in the same table did not pass. CO2 per mile on the slow queue link (889 g per mile in 2019) and on four 2040 links (190 to 231 g per mile) fell outside the 250 to 700 g window we expected. Do not read that window as a validity limit.
<!-- measured; record kept by the maintainers -->

## What is filled in for you, and how far to trust it

Some defaults come from the county (vehicle mix, speed, parking-lot starts, fuel and weather). Others do not: grade is 0, and the vehicle age and start operating-mode tables are national. A link's traffic volume and length always come from you, and so does the number of vehicles in a parking lot.

| Input | Where the default comes from | When to replace it |
|----|----|----|
| Vehicle mix on a road link | The county's yearly mileage by vehicle type, times that month's, day type's and hour's share, times the share on that road type | Always for a truck route, a bus lane or any road whose traffic you know. |
| Link speed | The county's speed distribution for that road type and hour, averaged as miles divided by hours; or the link's drive schedule | When you know the speed. A real link can be far from the county average. |
| Grade | 0 (flat) | When the link is not flat. In the fixture, a 4 percent grade changes CO2 on the link by about 45 percent (269,937 g against 186,660 g). |
| Engine starts on a parking lot | Starts per vehicle per day in the county, times that hour's share of the day's starts | Almost always. This is the average vehicle in the county, not your lot. |
| Extended idle and parked share | 0 and 1 | When trucks idle or park at the site. |
| Soak times | MOVES's national start operating-mode table for that day type and hour, weighted by the county's vehicle ages | When you know how long vehicles sit. |
| Vehicle ages | The national age table, **travel-weighted** (next section) | When you know the ages of the vehicles on the link. Give your own `sourcetypeagedistribution.csv`. |
| Fuel, weather, inspection programme | The county adapters of a county run | As for a county run. |

### Vehicle ages: travel-weighted

**Travel-weighted** ages are the ages of the vehicles driving on the link, rather than of the vehicles registered. An age table says what share of the *registered* vehicles of a type is each age, and older vehicles are driven fewer miles.

At county scale MOVES weights each age by its mileage before it shares out the miles. At project scale it does not: it reads the table as the ages of the traffic on the link. So, for each vehicle type and year, the image multiplies each age share by MOVES's relative mileage for that age and rescales the shares to add up to 1.

The table shows what this default changes. Each cell is the per-mile difference, in percent, between a project run and a county run, on urban unrestricted roads:

| Pollutant | Registration ages | Travel-weighted default |
|---|---|---|
| NOx | 93.54 | 1.53 |
| Exhaust PM2.5 | 164.72 | 1.83 |
| CO2 | 4.28 | 0.08 |
| CO | 47.52 | -0.06 |

With the default, NOx, exhaust PM2.5 and CO2 are each within 2 percent of the county run. <!-- measured; record kept by the maintainers -->

To keep the registration ages instead, set `PROJECT_AGES=registration` in the environment, or put `"project_ages": "registration"` in `parameters.json` in the run folder. If both are set, the environment variable wins. Any other value stops the run.

A `sourcetypeagedistribution.csv` that you supply is used as given, with no weighting. `diagnostics.txt` and `_project_inputs.csv` record which ages were used.

**County ages (`age_source`, national by default).** You can choose one of three age tables, with `"age_source"` in `parameters.json` or `AGE_SOURCE` in the environment (if both are set, the environment wins). The setting works the same in county and project runs.

- `national` (the default): the national table for the run year, as in earlier releases.
- `county`: the county's own table from EPA's National Emissions Inventory (NEI), from the nearest inventory year, used as is. Run years up to 2021 take 2020; 2022 and later take 2023.
- `county_adjusted`: the national table adjusted to the county. In 2020 and 2023 it is the county's own table. In other years it is the national table for the run year, multiplied age by age by the county-to-national ratio of the nearest inventory year; between 2020 and 2023 the two years' ratios are interpolated in a straight line. Each ratio is kept between 0.25 and 4.

Both county settings rescale the shares to add up to 1 for each vehicle type. Long-haul truck types (53, long-haul single-unit trucks, and 62, long-haul combination trucks) always keep the national table.

The county settings need the reference file `scripts/reference/nei_sourcetypeagedistribution.rds`, which is included in the image (11.8 MB; 3,223 counties for 2020 and 3,224 for 2023; built by `dev/make_nei_ages_reference.R`).

If the file is missing or the county is not in it, the run uses the national table and says so in `_age_source.txt`; it does not fail. Any other value of the setting stops the run. A table you supply still wins. For a project run, the travel weighting is applied on top of whichever table is chosen.

One measurement exists (Tompkins, NY, 2022, county run). With county ages, CO2 was 0.962 of the national-age result, NOx 0.676, exhaust PM2.5 0.716, CO 0.722 and hydrocarbons 0.687. In the county table, cars were 1.9 years younger and light trucks 2.3 to 3.4 years younger than in the national table.
<!-- measured; record kept by the maintainers -->

This was measured before the setting was split in three, with the earlier `county` setting and a partial reference file (2020, New York only). It has not been repeated for `county` or `county_adjusted`. The default stays national until this has been reviewed.

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

```text
year,month,day,hour,geoid,link,roadtype,pollutant,process,sourcetype,fueltype,emissions,vmt,sourcehours,starts,vehicles
2022,7,5,8,36109,1,5,1,1,11,1,5.41786003112793,5.614389896392822,0.22457599639892575,0,11.228799819946287
```

The activity columns (`vmt`, `sourcehours`, `starts`, `vehicles`) repeat on every pollutant row of a link, vehicle type and fuel. Do not sum `vmt` down the whole file, or you count the same miles many times.

**Grams per mile** is the sum of `emissions` divided by the miles, counting miles once per link, vehicle type and fuel. **Grams per second** is grams divided by 3600.

For link 1 of the fixture, CO2 is 186,659.7 g in 400 miles: 466.6 g per mile, or 51.8 g per second. (The reference results were regenerated with travel-weighted ages.)
<!-- measured; record kept by the maintainers -->

`diagnostics.txt` holds one line per link and the list of defaults used. This is the real file from the fixture run:

```text
link,roadtype,description,miles,co2_g,nox_g,co2_g_per_mile,nox_g_per_mile,starts
1,5,arterial 25 mph flat,400,186659.7,167.3,466.6,0.418,0
7,1,parking lot and truck stop (off-network),0,79646.2,528.2,,,76.3

Inputs filled in by default or supplied by you:
link 5 linkAvgSpeed | default | 25.59 mph from avgspeeddistribution
vehicle mix, links 1, 2, 3, 4, 5, 6 | default | sourcetypeyearvmt x month, day, hour and road type shares
off-network startFraction | default | startsperdaypervehicle x startshourfraction
off-network extendedIdleFraction | default | 0
off-network parkedVehicleFraction | default | 1
start soak times (opmodedistribution) | default | startsopmodedistribution weighted by vehicle age
```

(Links 2 to 6 are left out here; the real file lists all seven.) A project run never writes `data.csv`, because that file holds a county-year result. `run_manifest.json` lists `linkdata.csv.gz` as the result. The adapted tables `_link.csv` and `_offnetworklink.csv` stay in the folder and show the values MOVES used.

A road link with `linkAvgSpeed` 0 is an idling queue. MOVES counts every vehicle in its volume as idling for the whole hour, so its grams are a rate per vehicle-hour times the volume. Scale them by the real delay: multiply by the hours each vehicle actually waits (0.05 for a 3-minute wait). `diagnostics.txt` prints a note for each such link.

## When a run is refused

MOVES itself accepts a bad project run and then produces nothing, so the image checks the inputs first. A refused run stops with a reason, writes no `linkdata.csv`, and exits with a non-zero code (an error status).

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
| `vehicle mix for link 1 has a share outside 0 to 1` | Keep every share between 0 and 1. |
| `folder holds a county result (data.csv); use a new folder` | Run the project in its own folder. |
| `off-network link needs offnetworklink.csv` | Add the file. |
| `offnetworklink.csv sourceTypeID not in the run's vehicle types` | Use vehicle types the run file selects. |
| `MOVES produced no results: ...` | MOVES refused the run. The reason ends with MOVES's own first error line; `moveslog.txt` in the folder has the rest. |

## Hosted runs

You do not need this to run the image yourself. Cloud MOVES is the maintainers' hosted service that runs this same image for CAT users.

It runs a project folder through a run ticket: a file that tells the container where to fetch the inputs and where to send the outputs (see [RUN_TICKET.md](RUN_TICKET.md)). The outputs are the same files as a local run, compressed: `linkdata.csv.gz`, `moveslog.txt.gz`, `replication.tar.xz` and `run_manifest.json`.

## Limits

- One hour per run. For several hours, make several runs, one folder each.
- Built for screening, research and teaching. EPA's guidance for regulatory hot-spot analysis expects project-specific traffic data and says there are no default values for off-network inputs. The defaults here do not replace that.
- The image uses MOVES5. MOVES6 exists; this image has not moved to it yet.
- Not tested: evaporative emissions, rate mode at project scale, runs with more than 32 links. Runs with 16, 17 and 32 links have run. <!-- measured; record kept by the maintainers -->

---

## For agents

Files that implement a project run (all in `moves_anywhere/scripts/`):

- `project_functions.R`: run-file reading (`is_project`, `project_spec`), the run-file rules (`project_check` holds rules 1 to 10 and 13, `project_check_im` rule 12, `adapt_link.R` rule 11), county-table reads (`project_read`), default notes (`project_note`), run-file maker (`project_runspec`).
- `adapt_link.R`: `link.csv`, vehicle mix, drive schedules. `adapt_offnetwork.R`: `offnetworklink.csv`, soak times.
- `task_adapt.R`: calls the adapters for a project run only. `importer.R`, `task_check_import.R`: load and check the link tables.
- `task_postprocess.R`, `task_get_linkdata.R`: write `linkdata.csv`. `task_summarize.R`: `diagnostics.txt`. `task_pack.sh`: manifest result check.
- `project_parameters.R`: reads and checks a project `parameters.json` (`project_params`), checks that a supplied run file agrees with it (`project_params_agree`), and gives the state for the link builder (`project_state`). As a script it prints shell lines for step 1b of `launch.sh` (`env`) or runs the agreement check (`agree`). Test: `tests/test_project_parameters.R`.
- `task_runspec.R`: the `LEVEL=project` helper. When `parameters.json` says `"level": "project"`, every value comes from that file. Step 1b of `launch.sh` runs it when the folder has no `rs_custom.xml`.

Tests, from the repository root: `Rscript moves_anywhere/tests/<name>.R` for `test_project_functions`, `test_adapt_link`, `test_adapt_offnetwork`, `test_importer_project`, `test_linkdata`, `test_runspec_project` (no Docker); `bash moves_anywhere/tests/test_pack_project.sh`; `bash moves_anywhere/tests/test_project.sh --image <image>` (Docker; full fixture run and refusals).

The gate steps are `project-unit` and `project` in `moves_anywhere/tests/run_gate.sh`.

Age files: `adapt_projectage.R` (travel weighting and the `PROJECT_AGES` switch; called by `task_adapt.R` after the county adapters and before `adapt_link.R`), `adapt_ages_county.R` (the `AGE_SOURCE` setting, `national`, `county` or `county_adjusted`, and the county table; sourced by `adapt_sourcetypeagedistribution.R`).

Tests: `tests/test_adapt_projectage.R`, `tests/test_adapt_ages_county.R`, `tests/test_nei_ages_reference.R`.

The reference file is included in the image and was built by `dev/make_nei_ages.py` and `dev/make_nei_ages_reference.R`.

Tests (all from the repository root; Docker for the ones that name an image):

- **Fast gate:** `bash moves_anywhere/tests/run_gate.sh --fast`. It runs `static`, `compare-unit`, `build`, `project-unit`, `replay` and only the refusals of `project`; it runs no MOVES. It takes several minutes (the script header says about 6, a measured run about 9). It is for working and is not a release gate: its last lines say so and list the steps left for the full gate. It cannot be combined with `--only`.
- **Replay test:** `bash moves_anywhere/tests/test_summarize_replay.sh --image <image>` runs only the summary step (`task_summarize.R`) on saved MOVES outputs, with no MOVES run: a county hour with no vehicle-population rows, the county fixture `inputs_ny`, and the project fixture. `--prove` also runs the first case against the image's own script and expects it to fail. The gate runs it as step `replay`.
- **EPA test:** `bash moves_anywhere/tests/test_epa_project.sh --image <image> [--run2]` runs `inputs_epa_project/` through `run.sh` and checks the exit code, the manifest, that `linkdata.csv` exists and `data.csv` does not, and EPA's run 1 against `movesoutput.csv` through `tests/compare_epa_project.py` (within 1 percent). `--run2` adds EPA's second run. It takes about 3 minutes of MOVES for run 1 (188 seconds in all). It is step 14 (`epa`) of the full gate. <!-- measured; record kept by the maintainers -->

Rule: every change to an existing script sits behind a project-only branch, and the county fixture in the gate checks that county runs are unchanged.
