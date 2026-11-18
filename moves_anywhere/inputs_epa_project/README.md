# inputs_epa_project

A project-scale test case taken from EPA's own training exercise: a truck terminal and its roads in Washtenaw County, MI (26161), January 2025, a weekday, 8 to 9 am (hour 9), carbon monoxide (CO).
Six links: five road links (road type 5) and one off-network link (the terminal, road type 1, link 6). Source types 21 (passenger car) and 62 (combination long-haul truck).

Source: US EPA, MOVES5 Hands-on Training Course, September 2025, Module 7 (Project Exercise), Answer Key. EPA is the source of every number in this folder; nothing was changed except as listed below.
Rebuild the tables with `moves_anywhere/tests/make_epa_project_fixture.py <training zip> <this folder>`; the run file and the two `epa_*` files are not made by that script (see below).

## Files

| File | What it is |
|----|----|
| `rs_custom.xml` | EPA's `project_exercise.mrs` with four changes (below). |
| `link.csv`, `linksourcetypehour.csv`, `offnetworklink.csv`, `opmodedistribution.csv` | The project tables, as EPA's workbooks give them. |
| `sourcetypeagedistribution.csv`, `fuelsupply.csv`, `fuelformulation.csv`, `fuelusagefraction.csv`, `avft.csv`, `zonemonthhour.csv` | The county tables, with a `FIPS` column (26161) added to match `inputs_ny`. |
| `driveschedulesecondlink_run2.csv` | EPA's second run (link 6 replaced by drive schedules). The name keeps a run from picking it up; rename it to `driveschedulesecondlink.csv` for the second run. |
| `hotellingactivitydistribution.csv` | EPA's hotelling activity distribution (zone 261610), under its MOVES table name, so a run uses it in place of MOVES's default hotelling data. Columns `zoneID`, `fuelTypeID`, `beginModelYearID`, `endModelYearID`, `opModeID`, `opModeFraction`, plus `FIPS` (26161). |
| `epa_movesoutput.csv`, `epa_movesactivityoutput.csv` | EPA's results, decoded from the MySQL table files in the Answer Key. `movesoutput` holds 42 rows: run 1 (average speeds, 21 rows) and run 2 (drive schedules, 21 rows). Grams of CO by link, process and source type. |

## What was converted

- The workbooks were read as XML inside the xlsx; only the data sheet of each was kept. Helper sheets (County, Zone, RoadType, SourceUseType, HourDay, OperatingMode, PollutantProcessAssoc and so on) were dropped.
- `offnetworklink.csv`: the `zoneID` column was dropped (MOVES Anywhere takes `sourceTypeID`, `vehiclePopulation`, `startFraction`, `extendedIdleFraction`, `parkedVehicleFraction`). EPA gives zero population for source type 21 and 800 trucks for source type 62.
- County tables: a `FIPS` column set to 26161 was added; column names are otherwise EPA's.
- Numbers were written plainly (`1E-3` as `0.001`); nothing was rounded.
- The answer key tables had only `.frm` and `.MYD` files; they were loaded into MariaDB (image `tmf77/moves-anywhere:v3.1.0`), repaired from the `.frm`, and written out with `SELECT *`. Empty fields are blank.

## Changes to the run file

1. `inputdatabase`: empty, now `localhost` / `movesdb20241112` (as `inputs_project`).
2. `outputdatabase`: `project_exercise_out`, now `localhost` / `moves`.
3. `scaleinputdatabase`: `project_exercise_in`, now `custom` (project rule 10).
4. `skipdomaindatabasevalidation`: `false`, now `true` (Washtenaw County has no I/M programme; project rule 12).

Every selection (county, year, month, day, hour, road types, source and fuel types, CO, processes 1, 2, 15, 16, 17, 90, 91, output detail, units) is EPA's. The energy unit stays Joules.

## Left out

- Link 6 drive schedule (EPA's second run) is in `driveschedulesecondlink_run2.csv`.
- EPA's `project post-processing.sql` and the `_in` / `_out` MySQL folders are not copied.
