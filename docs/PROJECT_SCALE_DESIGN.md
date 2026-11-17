# How MOVES Anywhere supports project-scale runs

What MOVES needs at each scale, what MOVES Anywhere fills in, where each number comes from, what we
assumed, what we measured, and where this can be wrong.

Written 2026-11-17 for the people who maintain MOVES Anywhere and for anyone deciding whether to trust
a project-scale result from it. The short user guide is [README_project_scale.md](README_project_scale.md).
This document is the reasoning behind it. It is deliberately critical of our own work: section 9 lists
the ways it can mislead you.

Status on the day of writing: built on a branch, tested on one laptop, **not merged and not released**.
Every number below was measured on that day unless it says otherwise. Things we did not test are listed,
not hidden.

## 1. The short version

- MOVES is the US EPA's model for vehicle emissions. It runs at three scales. **County scale** estimates
  a whole county. **Project scale** estimates individual pieces of road for one hour. (National scale is
  not used here.)
- MOVES Anywhere exists because MOVES needs many input tables that most people do not have. For county
  runs it fills them in from public data, so a user can give a county and a year and nothing else.
- This work asks whether the same idea carries to project scale. The answer has three parts.

| Part | Can it be filled in? | State |
|---|---|---|
| County background (fuel, vehicle ages, weather, inspection programme) | Yes, by the same code as a county run | Works. Measured. |
| Link attributes other than traffic (vehicle mix, speed if unknown, grade, engine starts and soak times on a parking lot) | Yes, as county averages | Built. Measured on one county; one external comparison in progress. |
| The links themselves (where the road is, how long, how much traffic) | Not from MOVES or its database. Would need road and traffic data from elsewhere | Not built. A separate research question. |

- So the honest pitch is: **bring your links (length and traffic volume), and the image fills in the
  rest with county averages and tells you which values were defaults.** It is a screening and research
  tool. It does not replace project traffic data in a regulatory analysis.

## 2. Words used here

| Word | Meaning |
|---|---|
| Run file (runspec) | `rs_custom.xml`. The recipe for one MOVES run: where, when, which vehicles, which pollutants. |
| Link | One piece of road with one length, traffic volume, speed and grade. MOVES's `linkID`. |
| Road type | MOVES's code for the kind of road: 1 off-network, 2 rural freeway, 3 rural other, 4 urban freeway, 5 urban other. |
| Off-network link | A link with road type 1: a parking lot, terminal or truck stop. No driving. Engines start, trucks idle. |
| Source type | MOVES's 13 vehicle types (11 motorcycle, 21 passenger car, 31 passenger truck, ... 62 combination long-haul truck). |
| Process | How a pollutant is emitted: running exhaust, start exhaust, brake wear, tyre wear, extended idle, and so on. |
| Operating mode | A bin of engine load and speed. MOVES turns a speed, or a second-by-second speed trace, into shares of time in each bin. |
| Soak time | How long an engine was off before it starts. A cold start emits more. |
| Inventory | Total emissions (grams), as opposed to rates (grams per mile). |
| Default database | The database EPA ships with MOVES (`movesdb20241112` for MOVES5). It holds national defaults and some county data. |
| NEI | EPA's National Emissions Inventory. States submit county vehicle counts and mileage to it. |
| Adapter | A MOVES Anywhere script (`adapt_*.R`) that writes one MOVES input table for a run. |
| I/M programme | A vehicle inspection and maintenance programme. Some counties have one, most do not. |

## 3. Three kinds of analysis, and what is actually tested

MOVES Anywhere was written with three kinds of analysis in mind. They are not equally proven.

| Kind | What it is in MOVES terms | State in MOVES Anywhere |
|---|---|---|
| County inventory | County scale (`modeldomain SINGLE`), output by county, usually a whole year | In production since version 1. A test gate reproduces a reference county run byte for byte. |
| County run with finer output ("link" or "edge" output) | County scale, but `geographicoutputdetail LINK` and hourly output. As we understand MOVES's documentation, a "link" at county scale is a road type within the county, not a real road segment. We have not verified that here | The run-file writer (`catr::custom_rs(.geoaggregation = "link", .timeaggregation = "hour")`) writes such a file. **We have not run one end to end in this work**, and the results step (`data.csv`) was written for county-year totals. Treat it as untested. It is on the task list (section 11). |
| Project scale | `modeldomain PROJECT`: real links, one hour | This work. Built and tested as described below. |

One thing we did learn about the middle row: the helper for project runs calls `custom_rs()` with
`"link"` and `"hour"`, and the file it writes still has the county domain, twelve months, both day types
and 24 hours. So "link output" from the run-file writer alone does not make a project run. The new code
converts it.

## 4. What MOVES requires, scale by scale

This is the central table. "Needed" means MOVES uses the table at that scale. Sources: MOVES5's own
loader code (which tables each scale's loader accepts), the MOVES engine source, and our runs.

| Input (MOVES table) | What it is | County inventory | Project |
|---|---|---|---|
| `sourceTypeYear` | Number of vehicles of each type in the county | Needed | Not used |
| `sourceTypeYearVMT` (or the HPMS forms) | Miles driven per year by vehicle type | Needed | Not used |
| `monthVMTFraction`, `dayVMTFraction`, `hourVMTFraction` | How mileage splits across months, day types, hours | Needed | Not used |
| `roadTypeDistribution` | Share of each vehicle type's miles on each road type | Needed | Not used |
| `avgSpeedDistribution` | Share of driving time in each of 16 speed bins | Needed | Not used |
| Starts tables (7) | Engine starts per vehicle, by hour, and soak times | Optional (defaults apply) | Not used. Start activity comes from the off-network link |
| Idle tables (4) | Off-network idling | Optional | Not calculated at project scale |
| `sourceTypeAgeDistribution` | Share of each vehicle type by age | Needed | Needed |
| Fuel: `fuelSupply`, `fuelFormulation`, `fuelUsageFraction`, `AVFT` | Which fuels are sold, their properties, and engine technology shares | Needed | Needed. At project scale MOVES does not fall back to its default fuel supply |
| `zoneMonthHour` | Temperature and humidity by month and hour | Needed | Needed |
| `IMCoverage` | The inspection programme, if any | Needed (may be empty) | Needed (may be empty; see section 8.3) |
| Hotelling tables | Long-haul truck rest periods (extended idle, auxiliary power) | Optional | Needed if extended idle is modelled. Not copied from defaults |
| `onRoadRetrofit` | Retrofit programmes | Optional | Optional |
| **`link`** | Each link's road type, length (miles), volume (vehicles in the hour), average speed (mph), grade (percent) | Not used | **Needed** |
| **`linkSourceTypeHour`** | Share of each road link's traffic by vehicle type. Sums to 1 per link | Not used | **Needed for every road link** |
| **`driveScheduleSecondLink`** | A second-by-second speed trace for a link | Not used | Optional. Overrides the average speed |
| **`opModeDistribution`** | Shares of time in each operating mode, per link | Not used | Optional for road links. **Needed for engine starts**: MOVES does not compute soak times at project scale |
| **`offNetworkLink`** | For the parking lot: vehicles present, share that start in the hour, share in extended idle, share parked | Not used | **Needed if there is an off-network link**, for every vehicle type in the run |

Two rules that are not tables but behave like requirements at project scale:

- **One hour.** One hour, one day type, one month, one year, one county per run. MOVES refuses anything
  else (`Too many hours selected. Select exactly one first.`).
- **Road types must match.** Every road type selected in the run file needs at least one link, and every
  link's road type must be selected.

## 5. Who provides each input

"Default database" means the table has usable rows in EPA's database for any county. "MOVES Anywhere"
is what the image does when the user gives nothing. A user's own table always wins: put `<table>.csv`
in the folder and the adapter uses it.

### 5.1 Inputs shared by county and project runs

These are produced by the same adapters at both scales. Nothing here is new; it is described because a
project result inherits every one of these assumptions.

| Input | In the default database? | What MOVES Anywhere does by default | Assumption you are accepting |
|---|---|---|---|
| Vehicle ages | Yes, a national distribution for each year | Takes the national rows for the run's year | Your county's fleet has the national age profile |
| Fuel supply and formulation | Yes, by fuel region | **Uses a fixed New York metropolitan fuel supply and formulation** shipped with the image (`scripts/fuelsupply.csv`, `scripts/fuelformulation.csv`), relabelled with the county's fuel region and the run's year | Fuel everywhere is like New York metro fuel. This matters little for CO2 and more for CO, NOx, particulates and evaporation. The default database does hold regional fuel; the code path that would use it is commented out, and we did not find the reason recorded |
| Fuel usage, engine technology shares (`AVFT`) | Yes | Default tables, estimated where needed | National technology and fuel-use shares |
| Weather | Yes, by county, month and hour | Takes the county's default rows | A typical month, not the day you care about |
| Inspection programme | Yes, for counties that have one | Takes the county's rows; writes nothing if there are none | EPA's description of the programme is current |
| Hotelling | Yes, a national distribution | Copies the national distribution to the county's zone | National truck rest behaviour |

### 5.2 Inputs used only by county runs, reused here to build project defaults

A project run does not load these tables into MOVES. The image still writes them (the county adapters
run first), and the project adapters read them to work out link defaults.

| Input | In the default database? | What MOVES Anywhere does by default | Used at project scale for |
|---|---|---|---|
| Vehicle population | Only national totals with allocation factors | Built from NEI county data: interpolated between NEI years, projected outside them | Not used |
| Annual mileage by vehicle type | Same | Built from NEI county data, same method | The default vehicle mix |
| Month, day and hour mileage shares | Yes, national | Default rows | The default vehicle mix |
| Road type distribution | Yes, national | Default table | The default vehicle mix |
| Speed distribution | Yes, national, by road type and hour | Default rows | The default link speed |
| Starts per vehicle per day, share of starts by hour | Yes, national | Default rows | The default share of parked vehicles that start |
| Start soak-time distribution | Yes, national, by vehicle age and hour | Read straight from the default database | Default soak times |

### 5.3 Inputs used only by project runs

| Input | In the default database? | Who provides it | Default, if any |
|---|---|---|---|
| Link length | No | **The user. Always** | None |
| Link traffic volume | No | **The user. Always** | None (a daily-count shortcut was designed and left out of this release) |
| Link road type | No | **The user. Always** | None |
| Link average speed | No | The user, or a default | The county's average speed on that road type in that hour; or the mean of the link's drive schedule if one is given |
| Link grade | No | The user, or a default | 0 (flat) |
| County and zone of the link | No | Filled in | The run's county; zone = county x 10 |
| Vehicle mix on a road link | No | The user, or a default | The county's mix on that road type in that hour (section 6.1) |
| Drive schedule | No | The user, optional | None. Without one MOVES picks its own standard driving cycles for the link's speed |
| Operating modes for road links | No | The user, optional | None. MOVES derives them from speed and grade |
| Vehicles on a parking lot | No | **The user. Always** | None. Vehicle types left out get 0 |
| Share of parked vehicles that start in the hour | No | The user, or a default | County starts per vehicle per day x that hour's share of the day's starts, capped at 1 (section 6.3) |
| Share in extended idle; share parked | No | The user, or a default | 0 and 1 |
| Soak times for starts | No (not for projects) | The user, or a default | The national soak distribution for that hour, weighted by the county's vehicle ages (section 6.4) |

The row counts of the five project tables in the default database were not checked one by one; EPA's
guidance says there are no defaults for off-network inputs, and our runs needed every one of these
tables to be supplied.

### 5.4 What still has to be obtained, by anyone

| Thing | Why MOVES Anywhere cannot supply it today | Where it could come from |
|---|---|---|
| Where the links are and how long | Not in MOVES. It is geography | Road network data: federal HPMS, OpenStreetMap (share-alike licence) |
| Traffic volume in the hour | Not in MOVES. County mileage says nothing about one road | Counts, a travel model, HPMS daily traffic with hourly shapes |
| Real link speeds | County averages are not a link | Probe data (costs money; the national NPMRDS set is restricted), a travel model |
| Grade | Not in MOVES | Elevation data (USGS) |
| Truck share on a specific link | The default is the county mix on that road type | Classification counts |
| Starts and idling at a specific lot | County averages describe the average vehicle, not a terminal | A site survey, parking turnover data |
| Local fuel | See 5.1 | A user-supplied `fuelsupply.csv` and `fuelformulation.csv` |

## 6. The defaults, exactly

Notation: S is the set of vehicle types in the run; r is the link's road type; m, d, h are the run's
month, day type and hour. Every county table is read for the run's own year, month, day type and hour.

### 6.1 Vehicle mix on a road link

`weight[s] = annualMiles[s] x monthShare[s] x dayShare[s, r] x hourShare[s, r] x roadTypeShare[s, r]`

`mix[s] = weight[s] / sum of weights`

In words: the county's miles for each vehicle type, cut down to this month, day type, hour and road
type; then shares of the total. If the user gives a mix for some links, those links keep it and the
others get the default. If the county mileage table is missing (the user supplied mileage in another
form), the run stops and asks for a mix rather than guess.

Assumption: every link on a road type carries the county's average traffic for that road type. A truck
route, a bus lane and a residential street all get the same mix. This is the default most likely to be
wrong for a real project.

### 6.2 Average speed of a road link

For each vehicle type, `v[s] = sum over the 16 speed bins of (share of time in bin x bin speed)`.
The link speed is `1 / sum over s of (mix[s] / v[s])`: total miles divided by total hours.

Assumption: the link moves at the county's average speed for that road type in that hour (25.59 mph for
urban non-freeway roads in Tompkins County at 8 am on a July weekday). Emissions are not linear in
speed, so one link at the average speed is not the same as real traffic spread over many speeds. Section
7.4 is the test that measures that gap.

### 6.3 Share of parked vehicles that start their engine in the hour

`startFraction[s] = min(1, startsPerVehiclePerDay[s, d] x shareOfStartsInHour[s, d, h])`

For Tompkins County at 8 am on a weekday this gives 0.19 for passenger cars and 0.019 for long-haul
trucks.

Assumption: vehicles in this lot behave like the average vehicle in the county. That is wrong for most
real lots (a commuter car park at 5 pm, a depot at 6 am). EPA's guidance says there are no default
values for these inputs and that they should come from the project. We provide a default so a run can
be made, we label it in the results, and we recommend replacing it.

### 6.4 Soak times

MOVES needs, for each vehicle type, the share of starts in each of 8 soak-time bins. At county scale it
works these out. At project scale it does not; it uses whatever table it is given. We give it MOVES's
own national table for that day type and hour, averaged over vehicle ages using the county's age
distribution, and repeated for every start pollutant in the run.

Assumption: starts at this site follow the national pattern of how long engines were off. In the data
we used, the national table was identical across ages, so the age weighting changed nothing.

### 6.5 Everything else

`linkAvgGrade` 0; `linkDescription` empty; extended idle share 0; parked share 1; a parking lot's
length, volume and speed 0.

Every default that was used in a run is written to `diagnostics.txt` and `_project_inputs.csv` in the
run folder, for example `link 5 linkAvgSpeed | default | 25.59 mph from avgspeeddistribution`.

## 7. What was measured

All on one laptop (Windows, Docker Desktop), one container at a time, 2 CPUs and 6 GB unless noted.
Image: MOVES5 (commit `2c4cd1ab`), default database `movesdb20241112`.

### 7.1 The reference run (the fixture)

Tompkins County, NY, 2022, a July weekday, 8 to 9 am. Seven links. No county tables supplied: every
one came from the adapters. This is `moves_anywhere/inputs_project/`.

| Link | What | Miles | CO2 (g) | CO2 g/mile | NOx g/mile | Starts |
|---|---|---|---|---|---|---|
| 1 | urban road, 25 mph, flat | 400 | 194,936 | 487 | 0.784 | 0 |
| 2 | same, 4% uphill | 400 | 282,026 | 705 | 1.31 | 0 |
| 3 | queue at 8 mph | 80 | 71,163 | 890 | 1.25 | 0 |
| 4 | freeway, 55 mph | 3,000 | 1,218,645 | 406 | 0.781 | 0 |
| 5 | urban road, speed left blank (default 25.59 mph) | 400 | 192,820 | 482 | 0.777 | 0 |
| 6 | urban road, stop-and-go speed trace | 400 | 210,017 | 525 | 0.865 | 0 |
| 7 | parking lot, 385 vehicles | 0 | 86,078 | | | 76.3 |

- Miles equal volume x length, and hours equal miles / speed, exactly as the MOVES engine source says.
- The pattern is physically sensible: uphill costs 45% more CO2; a slow queue emits almost twice as
  much per mile as free flow; the freeway is the cleanest per mile.
- The whole pipeline (one command, `run.sh`) took 693 seconds: 32 s to fill in tables, 14 s to load them,
  621 s of MOVES, 6 s to write results. An earlier run of the same links took 502 s of MOVES with no CPU
  limit. Timings on this laptop vary by a third.
- The same seven links run by hand earlier in the day, before any of this code existed, gave the same
  per-link numbers to four to six significant figures. That shows the new code reproduces the
  experiment. It does not show the experiment was right.

### 7.2 Refusals

MOVES accepts a bad project command, does nothing, and reports success (`BUILD SUCCESSFUL`, exit code
0). The loader does the same when a table fails to load. So the image checks first, and checks again
afterwards.

| Test | Result |
|---|---|
| Run file asks for hours 8 to 9 | Stopped in the first step: `more than one hour (8 to 9)` |
| No `link.csv` | Stopped: `link.csv is missing from the inputs folder` |
| A vehicle mix that sums to 0.9 | Stopped: `vehicle mix for link 1 sums to 0.9, not 1` |
| Row count of each loaded link table against its file | 7, 78, 300, 13 and 1,768 rows, all equal |

The three refused runs took 46 seconds in total.

### 7.3 An external example: EPA's carbon monoxide guidance

We looked for a published project-scale example with both inputs and results. We found no MOVES5 one.
EPA's guidance "Using MOVES3 in Project-Level Carbon Monoxide Analyses" (EPA-420-B-21-047), Appendix A,
prints one: an intersection in Washtenaw County, Michigan, 2025, January, 7 to 8 am. Two free-flow
links of 0.1875 miles at 45 mph and a queue link at 0 mph, 1,000 vehicles each. EPA's printed results
(from MOVES3, with EPA's own fleet and fuel inputs, which we did not copy): 2.74 g CO per vehicle-mile on
the free-flow links and 5.57 g CO per vehicle-hour on the queue.

This cannot match digit for digit: different MOVES version, and our county-average fleet instead of
EPA's. It is an order-of-magnitude check and a test of a second county in a cold month.

What happened, in order, because the failures are the useful part:

1. **First attempt: MOVES refused.** Our run file still listed road types 1 and 4, and the three links
   were all road type 5. MOVES said `link is missing roadTypeID(s) 1,4`, produced nothing, and exited 0.
   Our "no results" check caught it and the run was reported as failed. We added a rule that stops the
   run earlier with a plain reason.
2. **Second attempt: MOVES refused silently.** No message at all. We isolated the cause by experiment:
   the same three links ran with Tompkins County's tables (330 s), and Tompkins County with an empty
   inspection table failed the same silent way. Washtenaw County has no inspection programme. With
   MOVES's own input validation switched on, an empty inspection table counts as "not ready", and the
   command line prints nothing. The MOVES window has a "No I/M Program" tick box for this; the command
   line has no equivalent. County run files written by `catr` switch that validation off, which is why
   county runs never met the problem. We added a rule that says so up front (section 8.3).
3. **Third attempt:** results are recorded in section 7.5 when the run finishes.

The Tompkins variant of the same three links (July 2022, so not comparable with EPA's January 2025
numbers) is informative by itself: 391 g CO2 and 3.68 g CO per mile at 45 mph, and 3.59 kg CO2 and
20.1 g CO per vehicle-hour on the 0 mph link. **A link at 0 mph is read by MOVES as every vehicle in
the volume idling for the whole hour** (1,000 vehicles gave 1,000.0 vehicle-hours in the output). That
is EPA's convention: you get a rate per vehicle-hour and scale it by the real delay. Taken as a total
it would be badly wrong.

### 7.4 An internal check: does a project run built only from defaults agree with a county run?

Designed, inputs built, not yet run at the time of writing. Results go in section 7.5.

The idea: run Tompkins County at county scale for the same hour, with output by road type. Then build a
project run that imitates it: for each of two road types, one link per speed bin, with miles in
proportion to the county's speed distribution, and the default vehicle mix (32 links, 10,000 miles per
road type). Compare grams per mile by road type. Both runs use the same engine and the same county
tables, so a large gap would mean the project inputs we build do not mean what we think they mean.

### 7.5 Results added after this document was first written

(Filled in as the remaining runs finish. An empty row means not run yet.)

| Check | Result |
|---|---|
| EPA example, Washtenaw County, third attempt | |
| County run against project run built from defaults | |
| Full test gate on the image built from the branch (12 steps, including the county reference run) | |
| Fixture run twice: identical results | |
| The fourth refusal (a road type with no link) | |

## 8. Design decisions that a reader should know about

### 8.1 A project run never writes `data.csv`

`data.csv` means "one county, one year" everywhere downstream, including the step that publishes
results into shared county data. A project result must never be mistaken for one. Project runs write
`linkdata.csv` instead (one row per link, pollutant, process, vehicle type and fuel; grams in the hour,
miles, hours, starts, vehicles). If someone copies a `parameters.json` from a county run into the
folder, there is still no `data.csv`; a test checks this.

### 8.2 County runs must not change

Every edit to an existing script sits behind one question: does the run file say `PROJECT`? A county run
executes the statements it executed before. The loader file written for the county reference run is
byte-identical to the one the released version writes (tested), and the release gate reruns the county
reference and compares its results.

### 8.3 MOVES's own validation

MOVES can check every input table before a run. We would like it on: it caught our first mistake with a
clear message. But it cannot be on in a county without an inspection programme (section 7.3), and it
fails without a message when it fails that way. So:

- If the run file has validation on and the county has no inspection table, the run stops with
  `no I/M programme here: set skipdomaindatabasevalidation to true`.
- The helper that writes project run files switches validation off, as `catr` does for county files.
- Our own rules (12 for the run file, plus checks on every link table) stand in for it. They are
  narrower than MOVES's validation. That is a real loss of protection; see section 9.

### 8.4 Refuse rather than repair

When an input is wrong the run stops with one line saying what to fix. It does not quietly edit the
user's run file or drop a link. The run folder is also the record of what was run (it is packed into the
replication kit), so silent repairs would make that record untrue.

### 8.5 What was left out on purpose

| Left out | Why |
|---|---|
| Volume from a daily traffic count | Designed (formula and test). One more thing to explain; not needed to prove the idea |
| Ordering project runs through the CAT website | The website's run ticket requires `data.csv.gz`. A project run sent that way ends as failed, which is the safe outcome |
| Building links from road data | A separate research project |
| MOVES6 | Released in October 2026. The image is on MOVES5. Moving is planned for the whole image, not just this feature |
| MOVES-Matrix | See section 10 |

## 9. Red team: how this can be wrong or misused

Written by the people who built it, trying to break it. Ordered by how much damage each could do.

1. **Defaults that look like data.** A user gives lengths and volumes, gets grams to six digits, and
   forgets that the vehicle mix, speed, fuel, fleet age and start behaviour were county or national
   averages. The output is precise and may be far from the truth for that road. Mitigation: every
   default used is listed in `diagnostics.txt`. Weakness: nothing forces anyone to read it, and
   `linkdata.csv` carries no flag on each row.
2. **Regulatory misuse.** EPA's hot-spot guidance expects project-specific traffic data and states that
   off-network inputs have no defaults. A result from this tool with defaults is not a conformity
   analysis. The guide says so. A PDF of results will not.
3. **The fuel is New York's.** Unless the user supplies fuel tables, every county gets a New York
   metropolitan fuel supply and formulation. This is how county runs already work, so project runs
   inherit it. We did not measure how much it changes CO, NOx or particulates in, say, Michigan in
   January. The external comparison in section 7.3 is affected by it.
4. **We replaced MOVES's validation with our own, narrower checks.** With validation off, MOVES will
   run inputs it would otherwise reject. We check the cases we have met (hours, road types, mix sums,
   row counts, empty results). We have surely not met them all. A table that loads but is wrong in a way
   we did not think of would produce numbers.
5. **We only detect an empty result, not a partly empty one.** If MOVES produced CO2 but silently
   dropped a pollutant, or produced nothing for one link, the run would pass. There is no check that
   every link and every requested pollutant appears in the output.
6. **One hour is easy to misuse.** Multiplying one hour by 24, or by 8,760, is wrong: traffic, speeds,
   temperature and starts all change by hour. The tool does one hour per run and has no helper for many
   hours yet.
7. **A 0 mph link means "everyone idles for an hour".** See 7.3. The per-link table prints a large total
   with zero miles and no warning.
8. **One average speed is not a traffic stream.** A link at the mean speed understates the effect of
   congestion, because slow driving emits disproportionately. For intersections EPA recommends
   operating-mode distributions or drive schedules, not an average speed. The tool accepts both but
   defaults to neither.
9. **The default vehicle mix ignores what kind of road it is beyond MOVES's five road types.** An urban
   arterial carrying a port's trucks and a suburban collector get the same mix.
10. **Thin testing.** One county and one hour pass end to end. A second county failed twice for reasons
    we then found. That is two for two on "the first new case breaks something". Not tested at all:
    weekends, winter (beyond the example in progress), rural road types, more than 7 links (until 7.4
    runs), evaporative emissions, air toxics, rate mode, electric vehicle shares, counties whose NEI
    data are thin, years outside the NEI range.
11. **The reference numbers are our own.** The test that compares a run with stored results proves the
    code did not change. It does not prove the stored results are right. The only outside comparison is
    with a MOVES3 example that cannot match exactly.
12. **Run time is unknown for real projects.** Seven links took about ten minutes. A corridor study can
    have hundreds of links. We do not know how time grows.
13. **How it was built.** The code was written in one day by AI agents working from a written plan, with
    one orchestrating agent reviewing diffs and running every container test. The plan was reviewed
    independently before coding. The code has not yet had an independent review, and no person has read
    all of it. Two defects were found after the agents reported their units done (vehicle counts came
    out as zero in the results file; one test would have compared the new code with itself once it was
    committed). Assume there are more.
14. **County averages come from the default database's national tables**, not from the county, for
    speeds, road type shares, hourly shares, starts and ages. "County average" in this document often
    means "national pattern applied to the county's mileage". Only vehicle counts and annual mileage are
    county-specific (from NEI), and those are interpolated or projected for years NEI does not cover.

## 10. Reference data, and whether MOVES-Matrix is needed

We searched for published project-scale examples that include both inputs and results.

| Source | MOVES version | Has inputs | Has results | Use |
|---|---|---|---|---|
| EPA CO guidance EPA-420-B-21-047, Appendices A and B | MOVES3 | Printed in the text (fleet and fuel in figures) | Three printed CO values | Order-of-magnitude check (section 7.3) |
| EPA MOVES5 training files (September 2025), Module 7 | MOVES5 | Probably; contents not confirmed | Not confirmed | Best version match. Not downloaded yet |
| EPA 2018 PM hot-spot course files | MOVES2014a | Yes (stated) | Yes (stated) | Old version: a pipeline check only |
| FHWA 2023 CO categorical finding | MOVES3 | On request by email | On request | Not pursued |
| EPA's MOVES repository on GitHub | MOVES6 | No project example | No | Not a test source |

**MOVES-Matrix** (Georgia Institute of Technology) is a very large lookup table of MOVES emission rates,
built by running MOVES about 180,000 times for its latest version, with a script that applies the rates to links
without running MOVES. Its published files state a Creative Commons Attribution 4.0 licence, which
would allow use with attribution. We do not need it and do not use it: MOVES Anywhere runs MOVES itself,
so it already has the rates, for the current MOVES version and any county. The public MOVES-Matrix data
are for MOVES4 and one county (Fulton County, Georgia). Its real advantage is speed (no MOVES run), which
matters for network-wide or year-long hourly work. That is a possible future direction, not a
dependency.

## 11. Open questions and the task list

| Item | Kind | Note |
|---|---|---|
| Finish the three pending checks in 7.5 | In progress | |
| Independent review of the code | To do | Before any merge |
| Test county-scale runs with link and hourly output (section 3) | Backlog | Long assumed to work, never tested end to end |
| Check every link and pollutant appears in the output (red team 5) | Backlog | |
| Warn on 0 mph links in `diagnostics.txt` (red team 7) | Backlog | |
| A flag on each `linkdata.csv` row for "used a default" (red team 1) | Backlog | |
| Regional fuel instead of New York's (red team 3) | Backlog, affects county runs too | Needs the reason the regional path was disabled |
| Many hours in one command | Backlog | Each hour is a separate MOVES run |
| Run time for 20, 50, 200 links | Backlog | |
| EPA's MOVES5 training exercise as a reference | Needs a decision | Requires downloading EPA's training archive |
| Daily-traffic shortcut | Designed, not built | |
| Links from road and traffic data | Research | The part nobody appears to have built |
| MOVES6 | Planned for the whole image | |

---

## For agents

- Code: `moves_anywhere/scripts/project_functions.R` (run-file rules, `project_read`, `project_runspec`,
  `project_check_im`), `adapt_link.R`, `adapt_offnetwork.R`, `importer_template_project.xml`,
  `importer.R` (project branch), `task_check_import.R`, `task_get_linkdata.R`; project branches in
  `task_adapt.R`, `task_importer.sh`, `task_postprocess.R`, `task_summarize.R`, `task_compress_outputs.sh`,
  `task_pack.sh`, `task_push_outputs.sh`, `task_runspec.R`.
- A run is a project run when `rs_custom.xml` contains `<modeldomain value="PROJECT"/>`. Every change to
  an existing script is behind that test.
- Tests: `moves_anywhere/tests/test_project_functions.R`, `test_adapt_link.R`, `test_adapt_offnetwork.R`,
  `test_importer_project.R`, `test_linkdata.R`, `test_runspec_project.R` (run with `Rscript` from the
  repository root, no Docker); `test_pack_project.sh`; `test_project.sh --image <image>` (Docker); gate
  steps `project-unit` and `project` in `tests/run_gate.sh`.
- Facts about MOVES in this document were read from the MOVES5 source inside the image
  (`/cat/EPA_MOVES_Model/gov/epa/otaq/moves/master/...`: `framework/importers/ImporterManager.java`,
  `framework/MOVESAPI.java`, `implementation/importers/*Importer.java`, `implementation/ghg/ProjectTAG.java`,
  `database/LinksImporter.sql`) or measured in a run. Where neither, the text says so.
- When you add a result to section 7.5, add the folder or file that holds the evidence.
- Do not soften section 9. Add to it.
