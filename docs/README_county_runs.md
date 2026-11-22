# `README`: county runs

A county run estimates emissions and activity for one county and one year, at MOVES's county scale.
<!-- source: README.md, "Quick start"; catr/R/custom_rs.R:3-4 -->
You give a run file (`rs_custom.xml`) and settings (`parameters.json`). <!-- source: README.md, "Quick start" steps 1-2 -->
You get emissions and activity in CAT Format (`data.csv`). For the three-step example, see the [Quick start](../README.md#quick-start). <!-- source: README.md, "What you get back" -->

Part of the MOVES Anywhere guides: see the [index](README.md).

| Section | What it holds |
|----|----|
| [Settings (`parameters.json`)](#settings-parametersjson) | Every key: meaning, allowed values, default |
| [The `by` codes](#the-by-codes) | What each code 1 to 16 groups by |
| [What comes back](#what-comes-back) | `data.csv`, column by column, with two real rows |
| [Emission rates](#emission-rates) | Asking for rates, and the tables a rate run writes |
| [Not supported](#not-supported) | State and national runs |
| [Your own input tables: a worked example](#your-own-input-tables-a-worked-example) | Change one table and see where it shows |
| [Check your setup](#check-your-setup) | Run the shipped example |

## Settings (`parameters.json`)

**Without `parameters.json`, a county run ends as failed, even when MOVES finishes: no `data.csv` is written.** <!-- source: README.md, "Quick start" step 2; moves_anywhere/scripts/task_postprocess.R:55,64-65 (data.csv is built only when the file exists) -->

`catr::rs_to_parameters()` can write the file from a run file. <!-- source: catr/R/rs_to_parameters.R:1-17 --> It writes `geoid`, `level`, `pollutant`, `year`, `default`, `mode`, `geoaggregation`, `timeaggregation`, `dtablename` and `by`. <!-- source: catr/R/rs_to_parameters.R:24-46 -->

| Key | Meaning | Allowed values | Default | When absent |
|----|----|----|----|----|
| `geoid` | The county, as a FIPS code. Used to pick that county's rows and to pad the code in `data.csv`. <!-- source: moves_anywhere/scripts/task_get_data.R:139-143; catr/R/process_emissions.R:36-42,62-68 --> | A 5-digit county FIPS code, as a string (`"36109"`). Keep it the same as in your run file. <!-- source: README.md, "Quick start" step 2 --> | None in the code. | Not documented in the code. |
| `level` | The level of the run. Decides which MOVES column becomes `geoid`. <!-- source: moves_anywhere/scripts/task_get_data.R:32-39 --> | `"county"` for a county run. The code also knows `"state"`, `"nation"`, `"zone"` and `"link"`, but see [Not supported](#not-supported). <!-- source: moves_anywhere/scripts/task_get_data.R:32-39 --> | None in the code. | Not documented in the code. |
| `year` | The year of the run. | A year. Keep it the same as in your run file. <!-- source: README.md, "Quick start" step 2 --> | None in the code. | Recorded in the run manifest as empty. <!-- source: moves_anywhere/scripts/manifest_fields.py:106 (as_int of None returns None) -->  The image does not use it to build `data.csv`. <!-- source: moves_anywhere/scripts/task_get_data.R:50, 136-143 (year comes from the MOVES output) --> |
| `pollutant` | The pollutant IDs of the run. | A list of MOVES pollutant IDs, such as `[98, 3, 87, 2, 31, 33, 110, 100, 106, 107, 116, 117]`. <!-- source: README.md, "Quick start" step 2 --> | Not applicable to this file; the run file's own default list is in `custom_rs()`. <!-- source: catr/R/custom_rs.R:60 --> | Recorded in the run manifest as an empty list. <!-- source: moves_anywhere/scripts/manifest_fields.py:97-111 --> The list is passed on, but `data.csv` is not filtered by it: `process_emissions()` is called with no pollutant filter. <!-- source: moves_anywhere/scripts/task_get_data.R:56 (.pollutant = NULL passed to process_emissions) --> `data.csv` holds every pollutant MOVES wrote. |
| `default` | Whether the run file is a default run (`TRUE`) or a custom one (`FALSE`). | `true` or `false`. <!-- source: catr/R/rs_to_parameters.R:27-29; catr/R/translate_rs.R:130 --> | `custom_rs()` makes a custom run (`.default = FALSE`). <!-- source: catr/R/custom_rs.R:57 --> | Recorded only. Nothing in `moves_anywhere/scripts` reads it. <!-- source: search of moves_anywhere/scripts for a `default` key: none --> |
| `mode` | Inventory or rates. | `"inv"`, or `"rate"` / `"rates"`. <!-- source: moves_anywhere/scripts/manifest_fields.py:115-117 --> | `"inv"` (`custom_rs()` makes an inventory run unless `.rate = TRUE`). <!-- source: catr/R/custom_rs.R:59,117-128 --> | The manifest falls back to the run file's mode. <!-- source: moves_anywhere/scripts/manifest_fields.py:118-124 --> The post-processing step reads the mode from `rs_custom.xml`, not from this key. <!-- source: moves_anywhere/scripts/task_postprocess.R:41-43 --> |
| `geoaggregation` | The geographic level of the MOVES output. | `"county"`, `"state"`, `"link"` or `"nation"`. <!-- source: catr/R/custom_rs.R:35 --> | The run's `level`. <!-- source: catr/R/custom_rs.R:35 --> | Recorded as empty in the run manifest; not read elsewhere in the image. <!-- source: moves_anywhere/scripts/manifest_fields.py:108 --> |
| `timeaggregation` | The time level of the MOVES output. | `"hour"`, `"day"`, `"month"` or `"year"`. <!-- source: catr/R/custom_rs.R:36 --> | `"year"`. <!-- source: catr/R/custom_rs.R:67 --> | Recorded as empty in the run manifest; not read elsewhere in the image. <!-- source: moves_anywhere/scripts/manifest_fields.py:109 --> |
| `dtablename` | The name of a results table, for example `d36109_u1_o1`. | Text. <!-- source: catr/R/rs_to_parameters.R:7-10,34-39 --> | `d<geoid>_u<user>_o<order>`, made by `rs_to_parameters()`. <!-- source: catr/R/rs_to_parameters.R:34-39 --> | Not read by the image. Nothing in `moves_anywhere/scripts` uses it. <!-- source: search of moves_anywhere/scripts for dtablename: none --> |
| `by` | Which groupings to write to `data.csv`. See [the `by` codes](#the-by-codes). | A list of whole numbers from 1 to 16, such as `[1, 16, 8, 12, 14, 15]`. <!-- source: catr/R/rs_to_parameters.R:11, 17; moves_anywhere/scripts/task_get_data.R:139-142 --> | `rs_to_parameters()` writes `[1, 16, 8, 12, 14, 15]`. <!-- source: catr/R/rs_to_parameters.R:17 --> | `task_postprocess.R` sets a fallback of `[1, 16, 15, 14, 12, 8]`, but `get_data()` reads `by` from the file itself. <!-- source: moves_anywhere/scripts/task_postprocess.R:84; moves_anywhere/scripts/task_get_data.R:139-143 --> Do not leave it out. |
| `training_type` | Marks a training run. | `"randomized"` skips building `data.csv`. Other values do not. <!-- source: moves_anywhere/scripts/task_postprocess.R:68-79 --> | Not set. | A normal run: `data.csv` is built. <!-- source: moves_anywhere/scripts/task_postprocess.R:73-79 --> |
| `debug` | Keeps MOVES's debug data. | `true`. <!-- source: moves_anywhere/scripts/task_launch_moves.sh:27-30; moves_anywhere/scripts/manifest_fields.py:97-111 --> | Off. <!-- source: moves_anywhere/scripts/task_launch_moves.sh:28 --> | Debug off, unless the environment variable `MOVES_DEBUG` is `1`. <!-- source: moves_anywhere/scripts/task_launch_moves.sh:27-31 --> |

Keys not in this table are not read by the image. <!-- source: search of moves_anywhere/scripts for other parameters.json keys: none found in task_postprocess.R, task_get_data.R, manifest_fields.py, task_launch_moves.sh -->

## The `by` codes

Each code gives one grouping of the results. A code groups emissions and activity by the columns in its row and sums over the rest. The other grouping columns in `data.csv` are `NA` for that code. <!-- source: catr/R/get_bycats.R:8-26; catr/R/process_emissions.R:41-60 -->

`year`, `geoid` and `pollutant` are always kept. <!-- source: catr/R/process_emissions.R:46-52 -->

| `by` | Groups by | | `by` | Groups by |
|----|----|----|----|----|
| 1 | `sourcetype`, `regclass`, `fueltype`, `roadtype` | | 9 | `regclass`, `fueltype`, `roadtype` |
| 2 | `sourcetype`, `regclass`, `fueltype` | | 10 | `regclass`, `fueltype` |
| 3 | `sourcetype`, `regclass`, `roadtype` | | 11 | `regclass`, `roadtype` |
| 4 | `sourcetype`, `regclass` | | 12 | `regclass` |
| 5 | `sourcetype`, `fueltype`, `roadtype` | | 13 | `fueltype`, `roadtype` |
| 6 | `sourcetype`, `fueltype` | | 14 | `fueltype` |
| 7 | `sourcetype`, `roadtype` | | 15 | `roadtype` |
| 8 | `sourcetype` | | 16 | none: one total per pollutant |

<!-- source: catr/R/get_bycats.R:8-25 -->

All 16 codes are traced in `catr/R/get_bycats.R`.

## What comes back

The files a run writes are listed in [What you get back](../README.md#what-you-get-back). This section covers `data.csv`.

When `by` lists more than one code, `data.csv` stacks one block per code, and the `by` column says which block a row is in. <!-- source: moves_anywhere/scripts/task_get_data.R:139-147 (map_dfr over p$by); catr/R/get_data.R, process_by2 adds mutate(by = .by) -->

| Column | Meaning | Unit |
|----|----|----|
| `year` | Year (MOVES `yearID`). <!-- source: moves_anywhere/scripts/task_get_data.R:48-53 --> | calendar year |
| `geoid` | County FIPS code, padded to 5 digits. <!-- source: catr/R/process_emissions.R:62-68 --> | none |
| `pollutant` | MOVES pollutant ID. <!-- source: moves_anywhere/scripts/task_get_data.R:48-53 --> | none |
| `sourcetype` | MOVES vehicle (source) type ID. <!-- source: moves_anywhere/scripts/task_get_data.R:48-53 --> | none |
| `regclass` | MOVES regulatory class ID. <!-- source: moves_anywhere/scripts/task_get_data.R:48-53 --> | none |
| `fueltype` | MOVES fuel type ID. <!-- source: moves_anywhere/scripts/task_get_data.R:48-53 --> | none |
| `roadtype` | MOVES road type ID. <!-- source: moves_anywhere/scripts/task_get_data.R:48-53 --> | none |
| `emissions` | The summed MOVES emission quantity (`emissionQuant`). <!-- source: moves_anywhere/scripts/task_get_data.R:53; catr/R/process_emissions.R:55-60 --> | U.S. tons over the time step (a year by default) <!-- source: catr/data_raw/rs_inventory.xml:229,231; catr/R/process_emissions.R:55-60 --> |
| `vmt` | Vehicle miles travelled: MOVES activity type 1, on roads other than road type 1. <!-- source: catr/R/process_activity.R:40,94 --> | miles <!-- source: catr/data_raw/rs_inventory.xml:230; catr/R/process_activity.R:54-59 --> |
| `sourcehours` | Hours the vehicles operate: activity type 4, on roads other than road type 1. <!-- source: catr/R/process_activity.R:40,94 --> | hours <!-- source: catr/R/process_activity.R:94-97 (column name; values only summed) --> |
| `vehicles` | Vehicle population: activity type 6, on road type 1. <!-- source: catr/R/process_activity.R:42,95 --> | count of vehicles <!-- source: catr/R/process_activity.R:95 (vehicle population; values only summed) --> |
| `starts` | Engine starts: activity type 7, on road type 1. <!-- source: catr/R/process_activity.R:42,95 --> | count of starts <!-- source: catr/R/process_activity.R:95 (values only summed) --> |
| `idlehours` | Idle hours: activity type 3, on road type 1. <!-- source: catr/R/process_activity.R:42,96 --> | hours <!-- source: catr/R/process_activity.R:94-97 (column name; values only summed) --> |
| `hoteld` | Hotelling hours (MOVES activity; see the MOVES documentation). Activity type 13, on road type 1. <!-- source: catr/R/process_activity.R:42,96 --> | hours <!-- source: catr/R/process_activity.R:96-97 (column name; values only summed) --> |
| `hotelb` | Hotelling hours (MOVES activity; see the MOVES documentation). Activity type 14, on road type 1. <!-- source: catr/R/process_activity.R:42,97 --> | hours <!-- source: catr/R/process_activity.R:96-97 (column name; values only summed) --> |
| `hotelo` | Hotelling hours (MOVES activity; see the MOVES documentation). Activity type 15, on road type 1. <!-- source: catr/R/process_activity.R:42,97 --> | hours <!-- source: catr/R/process_activity.R:96-97 (column name; values only summed) --> |
| `by` | The `by` code of the block the row is in. <!-- source: moves_anywhere/scripts/task_get_data.R:94 (mutate(by = .by)) --> | none |

Units come from the run file, which sets time to years, distance to miles and mass to U.S. tons. `catr` only sums the values, so it does not change them. <!-- source: catr/data_raw/rs_inventory.xml:229-231; catr/R/process_emissions.R:55-60; catr/R/process_activity.R:54-59 -->

The activity columns are joined onto the emissions rows. <!-- source: moves_anywhere/scripts/task_get_data.R:90-94 --> `NA` means no value for that row: MOVES has no activity of that kind for it, or the column does not apply (road type 1 has no `vmt`). <!-- source: catr/R/process_activity.R:36-43; real run 2026-11-21, see below -->

The header and one row from a run of the [Quick start](../README.md#quick-start) on the published image `tmf77/moves-anywhere:v3`: <!-- measured 2026-11; record kept by the maintainers -->

```
year,geoid,pollutant,sourcetype,regclass,fueltype,roadtype,emissions,vmt,sourcehours,vehicles,starts,idlehours,hoteld,hotelb,hotelo,by
2025,36109,1,11,10,1,2,0.548347532749176,508172,7441.58984375,1935.7099609375,129783,NA,NA,NA,NA,1
```

<!-- measured 2026-11; record kept by the maintainers -->

That run's file has 10,225 rows. <!-- measured 2026-11; record kept by the maintainers --> The row above is `by` code 1 (all four grouping columns kept). Its `idlehours` and the three hotelling columns are `NA`.

## Emission rates

By default a run is an inventory run: total emissions. To ask for rates instead, make the run file with `catr::custom_rs(.rate = TRUE)`. A `parameters.json` is optional for a rate run. <!-- source: catr/R/custom_rs.R:11,59,117-122; moves_anywhere/scripts/task_postprocess.R:127-146 (does not read parameters.json); moves_anywhere/scripts/manifest_fields.py:115-124 (mode only feeds the manifest) -->

Two lines are enough: the run file for Tompkins County, NY, 2025, then the run. <!-- source: catr/R/custom_rs.R:54-59 (argument names .geoid, .year, .path, .rate); README.md, "Quick start" step 4 -->

```r
catr::custom_rs(.geoid = "36109", .year = 2025, .rate = TRUE, .path = "inputs/rs_custom.xml")
```

```
bash moves_anywhere/run.sh inputs
```

A rate run does not write `data.csv`. It writes these tables to the same folder: <!-- source: moves_anywhere/scripts/task_postprocess.R:127-143 -->

| File | What it is, its key columns and its unit |
|----|----|
| `rateperdistance.csv` | The MOVES `rateperdistance` table: rates per distance travelled. Columns: `MOVESScenarioID`, `MOVESRunID`, `yearID`, `monthID`, `dayID`, `hourID`, `linkID`, `pollutantID`, `processID`, `sourceTypeID`, `regClassID`, `SCC`, `fuelTypeID`, `modelYearID`, `roadTypeID`, `avgSpeedBinID`, `temperature`, `relHumidity`, `ratePerDistance`. Unit: U.S. tons per mile. <!-- source: moves_anywhere/defaults/CreateOutput.sql:290-310 (columns); catr/data_raw/rs_rate.xml:229-231 (units); measured 2026-11-22; record kept by the maintainers --> <!-- source: moves_anywhere/scripts/task_postprocess.R:139; moves_anywhere/scripts/task_pack.sh:121-123 --> |
| `rateperhour.csv` | The MOVES `rateperhour` table: rates per hour. Key columns: the time columns (`yearID`, `monthID`, `dayID`, `hourID`), `linkID`, `pollutantID`, `processID`, `sourceTypeID`, `regClassID`, `SCC`, `fuelTypeID`, `modelYearID`, `roadTypeID`, `temperature`, `relHumidity`; value `ratePerHour`. Unit: U.S. tons per hour of activity (for example, about 7.5 kg of CO2 per hour of extended idle for a long-haul truck). <!-- source: moves_anywhere/defaults/CreateOutput.sql:421-440; catr/data_raw/rs_rate.xml:229-231 --> <!-- source: moves_anywhere/scripts/task_postprocess.R:137; moves_anywhere/scripts/task_pack.sh:121 --> |
| `ratepervehicle.csv` | The MOVES `ratepervehicle` table: rates per vehicle. Key columns: the time columns, `zoneID`, `pollutantID`, `processID`, `sourceTypeID`, `regClassID`, `SCC`, `fuelTypeID`, `modelYearID`, `temperature`, `relHumidity`; value `ratePerVehicle`. Unit: U.S. tons per vehicle per year, the run's time unit (for example, about 153 kg of CO2 from engine starts per passenger car). <!-- measured 2026-11-22; record kept by the maintainers --> <!-- source: moves_anywhere/defaults/CreateOutput.sql:320-338; catr/data_raw/rs_rate.xml:229-231 --> <!-- source: moves_anywhere/scripts/task_postprocess.R:138; moves_anywhere/scripts/task_pack.sh:121 --> |
| `rateperstart.csv` | The MOVES `rateperstart` table: rates per engine start. Key columns: the time columns, `zoneID`, `sourceTypeID`, `regClassID`, `SCC`, `fuelTypeID`, `modelYearID`, `pollutantID`, `processID`, `temperature`, `relHumidity`; value `ratePerStart`. Unit: U.S. tons per start. <!-- source: moves_anywhere/defaults/CreateOutput.sql:394-412; catr/data_raw/rs_rate.xml:229-231 --> <!-- source: moves_anywhere/scripts/task_postprocess.R:140; moves_anywhere/scripts/task_pack.sh:122 --> |
| `startspervehicle.csv` | The MOVES `startspervehicle` table: starts per vehicle. Key columns: the time columns, `zoneID`, `sourceTypeID`, `regClassID`, `SCC`, `fuelTypeID`, `modelYearID`; value `startsPerVehicle`. Unit: starts per vehicle (a count, not a mass). <!-- source: moves_anywhere/defaults/CreateOutput.sql:372-386 --> <!-- source: moves_anywhere/scripts/task_postprocess.R:141; moves_anywhere/scripts/task_pack.sh:122 --> |
| `rateperprofile.csv` | The MOVES `rateperprofile` table. The code notes it is usually empty. Key columns: `temperatureProfileID`, `yearID`, `dayID`, `hourID`, `pollutantID`, `processID`, `sourceTypeID`, `regClassID`, `SCC`, `fuelTypeID`, `modelYearID`, `temperature`, `relHumidity`; value `ratePerVehicle`. Unit: U.S. tons per vehicle, over the run's time unit; not measured, because the table was empty in the runs seen. <!-- source: moves_anywhere/defaults/CreateOutput.sql:347-364 --> <!-- source: moves_anywhere/scripts/task_postprocess.R:142; moves_anywhere/scripts/task_pack.sh:122 --> |
| `movesrun.csv` | The MOVES `movesrun` table: one row per run, including its `massUnits` ("ton") and `distanceUnits` ("mi"). The code notes it is usually small. <!-- measured 2026-11-22; record kept by the maintainers --> <!-- source: moves_anywhere/scripts/task_postprocess.R:143; moves_anywhere/scripts/task_pack.sh:122 --> |

Rate runs complete and write every table. Their numbers have not yet been compared with a reference. <!-- measured 2026-11; record kept by the maintainers -->

**Time.** The run file from this call averages over the whole year: `custom_rs()` keeps its default `.timeaggregation = "year"` for rate runs too. So `monthID`, `dayID` and `hourID` are 0 in every table, and `movesrun.csv` says `timeUnits` year. <!-- source: catr/R/custom_rs.R:67,170-179; measured 2026-11-22 on a rate run made with the same settings; record kept by the maintainers -->

**Units.** Mass is U.S. (short) tons and distance is miles, so the rates are U.S. tons per mile, per start, per hour of activity, and per vehicle per year. To get grams, multiply by 907,185. <!-- source: catr/data_raw/rs_rate.xml:229-231; measured 2026-11-22; record kept by the maintainers -->

For example, on a real rate run (Tompkins County, 2022), the median `ratePerDistance` for gasoline, diesel and E85 passenger cars (`sourceTypeID` 21; electric cars have 0), CO2 (`pollutantID` 90) and running exhaust (`processID` 1) on road type 4 is 0.000335. That is about 304 grams per mile. The file itself holds tons, not grams. <!-- measured 2026-11-22; record kept by the maintainers -->

**Check a rate run.** The run's manifest status is `ok`, and `rateperdistance.csv` is present and not empty. <!-- source: moves_anywhere/scripts/task_pack.sh:148-153 (success is judged by rateperdistance.csv); docs/RUN_MANIFEST.md:50 -->

## Not supported

State and national runs are not supported. They fail or give totals far too low. <!-- measured 2026-11; record kept by the maintainers -->

Run counties one at a time instead.

## Your own input tables: a worked example

Example: set the vehicle population yourself. The table is `sourcetypeyear` (vehicle population by vehicle type). <!-- source: docs/README_MOVES_inputs.md (Source Type Population: sourceTypeYear); moves_anywhere/inputs_ny/sourcetypeyear.csv:1 -->

1. Do the [Quick start](../README.md#quick-start) first, so `inputs/` holds `rs_custom.xml` and `parameters.json`.
2. Save your table as `inputs/sourcetypeyear.csv`, beside the run file. The columns to copy are the header of `moves_anywhere/inputs_ny/sourcetypeyear.csv`: `YearID`, `sourceTypeID`, `salesGrowthFactor`, `sourceTypePopulation`, `migrationrate` and `FIP`. <!-- source: moves_anywhere/inputs_ny/sourcetypeyear.csv:1 -->
3. Change `sourceTypePopulation` for one vehicle type, for example type 11 (motorcycles). Keep the county and year the same as your run file.
4. Run it as before: `bash moves_anywhere/run.sh inputs`. <!-- source: README.md, "Quick start" step 4 -->
5. Open `inputs/data.csv`. The change shows in the `vehicles` column of the rows for that `sourcetype`, and in the emissions that depend on it. <!-- source: catr/R/process_activity.R:42,95 (vehicles is activity type 6) -->

Any table in the list works the same way: save it as `inputs/<tablename>.csv`. The tables, and what the image does with each, are in [MOVES inputs](README_MOVES_inputs.md). A table you leave out is filled from MOVES defaults. <!-- source: README.md, "Quick start" step 3 -->

## Check your setup

The folder `moves_anywhere/inputs_ny` is a finished example: Tompkins County, NY, 2022. It holds the run file, `parameters.json`, input tables and the results of a run, including `data.csv`. <!-- source: moves_anywhere/inputs_ny/parameters.json; CHANGELOG.md:105 -->

1. Copy the folder, so the results in it are not overwritten: `cp -r moves_anywhere/inputs_ny my_check`. Delete the old results from the copy (`data.csv`, `movesoutput.csv`, `movesactivityoutput.csv`, `moveslog.txt`). Leftover generated files there (`diagnostics.txt`, `importer.xml`, `_*.csv`) are regenerated by the run and are harmless. <!-- source: moves_anywhere/scripts/compare_outputs.py:1-24 (compares the result files only) -->
2. Run the copy: `bash moves_anywhere/run.sh my_check`.
3. Compare your folder with the shipped one, using the exact check the maintainers use. It needs Python 3 on the host (on Windows the command may be `py` instead of `python`): `python -I moves_anywhere/scripts/compare_outputs.py moves_anywhere/inputs_ny my_check`. <!-- source: moves_anywhere/scripts/compare_outputs.py:1-24; docs/REPLICATION_KIT.md:40-41 -->

What to expect:

| Check | Expected |
|----|----|
| `compare_outputs.py` | A `PASS` line for each file. <!-- source: docs/REPLICATION_KIT.md:41; CHANGELOG.md:105 (OVERALL: PASS, maximum relative difference 0.0 for this example) --> |
| `data.csv` | 23,730 rows plus a header, the shipped file. <!-- source: moves_anywhere/inputs_ny/data.csv (23,731 lines) --> |
| `run_manifest.json` | A successful status. See [the run manifest](RUN_MANIFEST.md). <!-- source: docs/RUN_MANIFEST.md:50 (`status: ok`) --> |

The changelog records that a fresh run of this example matched the reference, with a largest relative difference of 0.0. <!-- source: CHANGELOG.md:105 -->
