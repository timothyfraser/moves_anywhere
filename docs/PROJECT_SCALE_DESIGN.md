# How MOVES Anywhere supports project-scale runs

What MOVES needs at each scale, what MOVES Anywhere fills in, where each number comes from, what we
assumed, what we measured, and where this can be wrong.

Written 2026-11-17 for the people who maintain MOVES Anywhere and for anyone deciding whether to trust
a project-scale result from it. The short user guide is [README_project_scale.md](README_project_scale.md).
This document is the reasoning behind it. It is deliberately critical of our own work: section 9 lists
the ways it can mislead you.

Status when first written (2026-11-17): built on a branch, tested on one laptop, **not merged and not released**. Sections 5.4, 7.6 and 9 were updated for release 3.2.
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
| Link attributes other than traffic (vehicle mix, speed if unknown, grade, engine starts and soak times on a parking lot) | Yes, as county averages | Built. Measured on one county; city checks in Manhattan and Buffalo (section 7.5). |
| The links themselves (where the road is, how long, how much traffic) | Not from MOVES or its database. Would need road and traffic data from elsewhere | Built as a beta in release 3.2 from federal data (section 5.4). Daily counts, county speeds: a screening input, not project traffic data. |

- What drives a result: vehicle-miles first (traffic volume x length, which always come from the
  user), then the emission rate per mile. Across real roads volume varies by a factor of thousands and
  the CO2 rate by about two, so getting the traffic right matters most. The rate still matters for
  comparing scenarios on one road, and for NOx and particulates, where vehicle age and truck share move
  it by two to three times.
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
| County run with finer output ("link" or "edge" output) | County scale, but `geographicoutputdetail LINK` and hourly output. As we understand MOVES's documentation, a "link" at county scale is a road type within the county, not a real road segment. We have not verified that here | The run-file writer (`catr::custom_rs(.geoaggregation = "link", .timeaggregation = "hour")`) writes such a file. Tim Fraser ran this kind of run when he built MOVESAI and confirmed that it computes. There was no outside result to compare it with then, and there is none now. It was not re-run in this work, so nothing here adds to or subtracts from that. Re-running it with the tests we now have is on the task list (section 11). |
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
| Fuel supply and formulation | Yes, by fuel region | **Uses a fixed New York metropolitan fuel supply and formulation** shipped with the image (`scripts/fuelsupply.csv`, `scripts/fuelformulation.csv`), relabelled with the county's fuel region and the run's year | Fuel everywhere is like New York metro fuel. This matters little for CO2 and more for CO, NOx, particulates and evaporation. The default database does hold regional fuel, and the code path that would use it is commented out on purpose: the New York fuel stays the default for every county because MOVES's own fuel formulation tables are unreliable, and there are no good public tables to compare them against (decision D92, 2026-11-18) |
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
| Where the links are and how long | Not in MOVES. It is geography | Road network data. The link builder (beta, below) takes it from federal HPMS; a user can still supply their own |
| Traffic volume in the hour | Not in MOVES. County mileage says nothing about one road | Counts, a travel model. The link builder turns HPMS daily counts into hourly volumes (below) |
| Real link speeds | County averages are not a link | Probe data (costs money; the national NPMRDS set is restricted), a travel model |
| Grade | Not in MOVES | Elevation data (USGS) |
| Truck share on a specific link | The default is the county mix on that road type | Classification counts |
| Starts and idling at a specific lot | County averages describe the average vehicle, not a terminal | A site survey, parking turnover data |
| Local fuel | See 5.1 | A user-supplied `fuelsupply.csv` and `fuelformulation.csv` |

**The link builder (beta).** Release 3.2 adds `links.sh`, which builds the link table for a box or a
county from federal data: FHWA's HPMS (road sections, counts, truck counts, posted speed limits) and USGS
elevation (grade). It is labelled beta. It does not run MOVES, and it writes `link_sources.csv`, which
labels every value on every link `measured`, `derived` or `default`. The guide is
[README_link_sources.md](README_link_sources.md); what follows is only the reasoning that belongs here.

- **Road type.** HPMS functional class 1 is always restricted. Class 2 is restricted when its
  access-control code says full control or is missing, and unrestricted when it says partial or none.
  Classes 3 to 7 are always unrestricted. We first meant to let access control decide for every class,
  and checked it on real layers before shipping: states code "full control" on a large number of
  ordinary class 3 to 7 sections, which would have turned local roads into freeways. (We counted them
  in New York and Texas; that count is not kept in this repository, so no number is given here.)
- **Year factor.** A count is for its count year; the run is for another. The count is scaled by the
  county's vehicle-miles in the run year over its vehicle-miles in the count year. This moves a count with
  the county, not with the road. A layer without a count-year field gets no factor, and says so.
- **Field names differ by layer year.** FHWA renamed fields between yearly layers (for example `route_id`
  against `routeid`, `county_id` against `county_code`, and no section length in the 2020, 2022 and 2023
  layers). The first live build failed on this. The builder now reads each layer's own field list from
  its metadata and maps it to one set of names, for the section fetch and for the county statistics.
  The 2020 layer uses `route_id`, `begin_point` and `end_point`; the 2022 and 2023 layers use `routeid`,
  `beginpoint` and `endpoint`. The 2022 layer for New York, queried for a box in Ithaca, first failed with
  HTTP 500 because the builder asked it for the newer names; it works now. <!-- source: release/live_link_build/BUILD.md -->
- **Roads with no count.** HPMS counts almost no local streets. For each unrestricted road type the builder
  adds one remainder link carrying the county's leftover traffic for the run's hour: the county's
  vehicle-miles minus the miles already counted. Its length is the uncounted miles in the place, capped at
  half an hour of travel at the county speed, and every value on it is labelled `default`. Restricted road
  types are not filled. `--no-fill` switches the remainder off. The remainder is spread evenly over
  uncounted miles, which is an assumption: a downtown box gets the county's average local-street volume.
- **Link limit.** The command refuses more than 40 links unless `--max-links` is raised. The reason is
  measured MOVES time: 7 links took 621 s, 16 links 1,487 s and 32 links 1,882 s, on one laptop, one
  container, 2 CPUs. That is roughly a minute per link, and not a straight line (the 16- and
  32-link figures are different runs, not repeats).
- **What it does not give.** Speeds are the county default for the road type, capped by the posted limit;
  a posted limit is not a congested speed. Counts are daily and scaled to an hour with the county's hourly
  shares. Truck counts are missing on many minor roads. A federal count is not project traffic data.

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
be made, we label it in the results, and we recommend replacing it. The default also leaves out two
refinements MOVES applies to starts at county scale: the adjustment by month and the adjustment by
vehicle age.

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
| 1 | urban road, 25 mph, flat | 400 | 186,660 | 467 | 0.418 | 0 |
| 2 | same, 4% uphill | 400 | 269,937 | 675 | 0.685 | 0 |
| 3 | queue at 8 mph | 80 | 68,446 | 856 | 0.713 | 0 |
| 4 | freeway, 55 mph | 3,000 | 1,172,156 | 391 | 0.365 | 0 |
| 5 | urban road, speed left blank (default 25.59 mph) | 400 | 184,629 | 462 | 0.414 | 0 |
| 6 | urban road, stop-and-go speed trace | 400 | 201,166 | 503 | 0.452 | 0 |
| 7 | parking lot, 385 vehicles | 0 | 79,646 | | | 76.3 |

The reference results were regenerated with travel-weighted ages. <!-- source: release/gold_change.csv -->

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
3. **Third attempt, with MOVES's validation off in the run file: it ran** (521 s of MOVES). Carbon
   monoxide on the free-flow links: 3.47 g per vehicle-mile, against EPA's printed 2.74 (27% higher).
   On the queue link: 16.8 g per vehicle-hour, against 5.57 (three times higher). Passenger cars alone
   were 3.35 and 14.6, so the vehicle mix does not explain the gap. We cannot separate the MOVES
   version, the fleet ages, the fuel and the weather with what EPA printed. MOVES3 is also several
   versions old. We do not treat this as a validation, in either direction.

The Tompkins variant of the same three links (July 2022, so not comparable with EPA's January 2025
numbers) is informative by itself: 391 g CO2 and 3.68 g CO per mile at 45 mph, and 3.59 kg CO2 and
20.1 g CO per vehicle-hour on the 0 mph link. **A link at 0 mph is read by MOVES as every vehicle in
the volume idling for the whole hour** (1,000 vehicles gave 1,000.0 vehicle-hours in the output). That
is EPA's convention: you get a rate per vehicle-hour and scale it by the real delay. Taken as a total
it would be badly wrong.

### 7.4 An internal check: does a project run built only from defaults agree with a county run?

The idea: run Tompkins County at county scale for the same hour, with output by road type. Then build a
project run that imitates it: for each of two road types, one link per speed bin, with miles in
proportion to the county's speed distribution, and the default vehicle mix (32 links, 10,000 miles per
road type). Compare grams per mile by road type. Both runs use the same engine and the same county
tables, so a large gap would mean the project inputs we build do not mean what we think they mean.

Result (the 32-link run took 1,882 s of MOVES):

| Per mile, project against county | Urban freeways | Other urban roads |
|---|---|---|
| Average speed | identical (48.51 mph) | identical (25.59 mph) |
| CO2, energy, SO2 | +4.6% | +4.3% |
| Tyre wear | +0.4% | +1.7% |
| Brake wear | -6.6% | -3.5% |
| CO | +44% | +48% |
| Hydrocarbons | +88% | +85% |
| NOx | +114% | +94% |
| Exhaust PM2.5 | +188% | +165% |

The activity we build is right: the speeds agree to five figures. The gap is in the emission rates, and
it has the signature of vehicle age (little effect on CO2, a large effect on the pollutants that old
vehicles emit far more of).

The MOVES source explains it. At county scale MOVES converts the share of *vehicles* of each age into a
share of *travel*, weighting each age by how many miles vehicles of that age drive; newer vehicles drive
more (`TotalActivityGenerator.java`: "TravelFraction = FractionWithinHPMSVType x relativeMAR"). At
project scale it uses the registration share directly as the share of the traffic on the link
(`ProjectTAG.java`: "linkVolume x sourceTypeHourFraction x ageFraction"). For Tompkins County the
average car on the register is 12.1 years old; weighted by travel it is 9.8. For long-haul trucks the
figures are 13.9 and 8.3.

So the same county fleet, handed to MOVES the same way, gives about twice the NOx and two to three
times the exhaust particulates per mile at project scale. This is how MOVES works, not a fault in the
link tables, and it may be what EPA intends: at project scale the age table is meant to describe the
vehicles on that road. It is still a choice we make by default, and section 9 treats it as the most
important open question. The confirmation run is in 7.5: with travel-weighted ages the gap closes to under 2% for NOx and
exhaust particulates.

The same source file holds one more rule worth knowing: a vehicle's time on a link is capped at one
hour (`least(linkLength / linkAvgSpeed, 1.0)`). A link too long to cross in the hour is silently
shortened.

A by-product: the county-scale run used for this comparison (one hour, two road types; it was a county
run, not a link-level run) produced its MOVES results and then crashed in the existing summary step
(`Error in round(a, 1): non-numeric argument`). The summary step rounded a text value, "missing", which
it writes when the run has no vehicle-population rows. That fault is in release 3.1.0 and was fixed in
this release, with a test that replays the summary step on saved outputs (a county hour with no
population rows, the county reference folder and the project fixture). Why MOVES wrote no population rows
in that run is not settled. MOVES files vehicle population under road type 1, which that run did not
select, and that may be the whole reason, but we have not confirmed it.

### 7.5 Results added after this document was first written

(Filled in as the remaining runs finish. An empty row means not run yet.)

| Check | Result |
|---|---|
| EPA example, Washtenaw County, third attempt | Ran. CO 27% above EPA's printed MOVES3 figure on free-flow links, three times above it at idle; unexplained (section 7.3) |
| County run against project run built from defaults | CO2 within 5%; NOx, CO, hydrocarbons and exhaust PM2.5 1.5 to 2.9 times higher at project scale (section 7.4) |
| The same project links with travel-weighted vehicle ages (16 links, urban roads) | Agrees with the county run: CO2 +0.1%, CO -0.1%, hydrocarbons 0.0%, NOx +1.5%, exhaust PM2.5 +1.8%, tyre wear +1.4%, brake wear +3.4%. Vehicle age weighting accounts for the whole gap. 1,487 s of MOVES |
| Full test gate on the image built from the branch (14 steps now, including the county reference run, the summary replay, the project fixture and step 14, `epa`, for EPA's exercise (section 7.6), full gate only) | Passed (14 steps) on commit 282fb16, in 3,624 s, and earlier on 2758e4f and 8f48468. <!-- source: cloud_moves docs/audit/project_scale_2026-11/wave4/gate_full_282fb16.txt --> `run_gate.sh --fast` runs only static, compare-unit, build, project-unit, replay and the refusals of the project step, with no MOVES run; its summary says it is not a release gate. The gate script's own header puts it at 9 to 15 minutes with the image build |
| Fixture run twice: identical results | Passed (the `sha` step of the gate) |
| The fourth refusal (a road type with no link) | Offline test passes; the container test passed (the `project` step of the gate) |
| The county-against-project comparison again, with the new age default | with the travel-weighted default, the project run differs from the county run per mile by 0.04% (THC), -0.06% (CO), 1.53% (NOx), 0.08% (CO2), 1.83% (exhaust PM2.5), 3.37% (brake PM2.5) and 1.35% (tyre PM2.5) on urban unrestricted roads; with registration ages the same differences were 85.42%, 47.52%, 93.54%, 4.28%, 164.72%, -3.54% and 1.65%. <!-- source: release/county_vs_project_default.csv --> |
| Reference years 2019 and 2040, county-run settings | Both years ran with the same pollutant-process set a county run file gets (84 pairs). NOx and exhaust PM2.5 per mile fall on every road link from 2019 to 2040; CO2 per mile in 2040 is about 45% of 2019. MOVES took 876 s and 963 s on a busy machine. One range check (CO2 per mile between 250 and 700 g) failed on five links, so it is not a limit we rely on. <!-- source: release/years_2019_2040.csv, release/years_2019_2040_checks.csv --> |
| City checks: Manhattan (36061) and Buffalo (Erie County, 36029), 2022, link-builder boxes run in MOVES; grams per mile compared with the CAT county results for the same road type | CO2 per mile is within 7% of CAT on road types 4 and 5: Manhattan 1.07 and 1.05 times CAT, Buffalo 0.98 and 1.00. NOx per mile: Manhattan 1.05 and 1.02 times CAT, Buffalo 0.82 and 0.84. Exhaust PM2.5 per mile in Manhattan is 1.39 and 1.23 times CAT. Buffalo road type 3 rests on 0.2 vehicle-miles and should not be read. Traffic counts, Manhattan only: the link builder's 7:00 hour volumes are 1.38 times measured counts (median of 8 comparisons, range 0.87 to 1.96); at the Queens Midtown Tunnel the builder puts 59% of traffic toward Queens, while the measured flow at 7:00 is 58% toward Manhattan. No measured hourly counts were found for Buffalo. Both runs are beta link-builder inputs, not a validation of the model. <!-- source: cloud_moves docs/audit/project_scale_2026-11/wave3/manhattan_vs_cat_2022.csv, wave3/buffalo_vs_cat_2022.csv, wave3/counts_check.md --> |

### 7.6 EPA's MOVES5 course exercise

**What it is.** The US EPA's MOVES5 Hands-on Training Course (September 2025), Module 7, the project
exercise, with its Answer Key. It is EPA's own work: a truck terminal and its roads in Washtenaw County,
Michigan, January 2025, a weekday, 8 to 9 am, carbon monoxide, with six links and two vehicle types
(passenger cars and combination long-haul trucks). EPA is the source of every input and every result in
`moves_anywhere/inputs_epa_project/`, which holds EPA's files with the changes listed in its README
(a `FIPS` column added to the county tables, one column dropped from the off-network table, and four edits to the run file). Unlike the guidance
in section 7.3, this is the same MOVES version we run (MOVES5.0.0 and default database `movesdb20241112`,
in EPA's input and output databases and in our run), so a difference cannot be put down to the version.

**What was compared.** We decoded EPA's answer-key input and output databases (MySQL table files) and
compared them with the tables our adapters build from the same inputs. EPA's input database holds 18
tables in this comparison: 16 that our adapters also write, which we compared, and EPA's audit log and a
drive-schedule table, which have no counterpart in this run.
<!-- source: epa_moves5_exercise/tables_compare_full.csv -->

- Fourteen of the 16 are equal on every row EPA's table holds (the county table's barometric pressure
  differs by 2 parts in a hundred million). The other two, `zone` and `zoneroadtype`, differ in their
  allocation factors: EPA sets them to 1; our adapters set them to the county's share of the state
  (about 0.001). They did not change activity: population, starts and distance (miles) are equal to EPA's
  on every link and for both vehicle types in MOVES's activity output.
  <!-- source: epa_moves5_exercise/DIAGNOSIS_run1.md -->
- Our tables sometimes hold more rows than EPA's (our age table has all 13 vehicle types, EPA's has the
  two in the run; our state table lists all states). Those extra rows are not read by this run. A few
  tables carry extra columns that MOVES fills in itself.
- Twelve tables our adapters write have no counterpart in EPA's input database (for example the month,
  day and hour mileage shares and the speed distribution); they are county-run tables that a project run
  does not read.

**What the run showed.**
On the corrected run, all 21 of 21 CO rows are within 1% of EPA's, and the largest relative difference is 5.0e-8. The run took 188 s in all. <!-- source: epa_moves5_exercise/comparison_run1b.csv -->

**A first comparison was wrong, and why.** Our first run used the MOVES default fuel-technology table
(`avft`) and the default hotelling table, because an earlier decode of EPA's input database had read only 7
of its 25 tables and concluded that EPA's run had imported neither. The full decode shows that EPA's
importer filled both (its audit log records it), and that EPA's `avft` equals the course workbook's on all
888 rows. That first run was the mistake, not a finding about the tool: nine of its 21 CO rows were within
1% of EPA's, and the rest differed in ways the two tables explain (a 1.1% share of natural-gas trucks in the
default technology mix raised truck running CO by 4.5 to 7.2%; the default hotelling table runs 32.5 hours
of an auxiliary power unit where EPA's has none, giving 313.7 g against EPA's 0).
<!-- source: epa_moves5_exercise/DIAGNOSIS_run1.md -->
The two workbook tables were then put back into the run folder, and the corrected run is the one reported
here. We say so because a comparison like this is easy to bend: putting EPA's inputs back is matching the
experiment, not tuning our code, but a reader should know that the first result was different and why.

**What this does and does not show.** If the corrected run agrees with EPA's results, that shows our
adapters and run-file handling reproduce EPA's example on one county, one month and two vehicle types. It
does not show that county averages are right for a real site, which this exercise supplies by hand and
does not test. The tolerance and the rows outside it, if any, are in the marker above.

**Other runs.** The 2019 and 2040 reference-year runs: see section 7.5; NOx and exhaust PM2.5 per mile fall on every link, CO2 per mile in 2040 is about 45% of 2019. <!-- source: release/years_2019_2040.csv -->
**EPA's second run (drive schedules).** EPA's exercise has a second run that gives links drive schedules. It reproduces too: 21 of 21 rows, largest relative difference about 5e-8. <!-- source: epa_moves5_exercise/comparison_run2.csv -->

**The link builder's live build, in a run of MOVES.** A box in Ithaca, NY (`-76.499,42.438,-76.495,42.441`), the 2022 HPMS layer, Tompkins County 2022, July weekday, 8:00 to 8:59. The builder made 17 links (16 counted, one remainder) in 87 s, with 10.2% of values from defaults. <!-- source: release/live_link_build/BUILD.md --> MOVES took 371 s, the run finished with status ok, and every link is in `linkdata.csv`. 13 of the 16 road links are within 10% of the flat fixture's CO2 per mile; the three outliers are the steep links (+65% at +7.1% grade, -51% and -57% at -8.3% and -10.9%), as expected against a flat reference. <!-- source: release/live_link_build/RESULT.md --> The remainder link (0.001 mi) ran as an ordinary link. The builder ships as beta.

## 8. Design decisions that a reader should know about

### 8.1 A project run never writes `data.csv`

`data.csv` means "one county, one year" everywhere downstream, including the step that publishes
results into shared county data. A project result must never be mistaken for one. Project runs write
`linkdata.csv` instead (one row per link, pollutant, process, vehicle type and fuel; grams in the hour,
miles, hours, starts, vehicles). If someone copies a `parameters.json` from a county run into the
folder, there is still no `data.csv`; a test checks this.

Folders get reused, so the two kinds of result are also kept apart when an old file is lying around. A
project run refuses to start in a folder that already holds a `data.csv`. A county run in a folder that
holds an old `linkdata.csv` ignores it: each kind of run compresses, lists and uploads only its own
result. (The independent review found that the first version shipped whichever stale file was there.)

`sourcehours` in `linkdata.csv` is MOVES's "source hours operating": hours of driving on road links.
Extended idle and hotelling hours on a parking lot are not a column; they are in the raw
`movesactivityoutput.csv`. So a truck stop shows grams from idling next to zero `sourcehours`.

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
- Our own rules stand in for it: ten on the run file, three more on the folder (every selected road
  type has a link, the inspection rule above, and no county result already in the folder), plus checks
  on every link table. They are narrower than MOVES's validation. That is a real loss of protection;
  see section 9.

### 8.4 Refuse rather than repair

When an input is wrong the run stops with one line saying what to fix. It does not quietly edit the
user's run file or drop a link. The run folder is also the record of what was run (it is packed into the
replication kit), so silent repairs would make that record untrue.

### 8.5 What was left out on purpose

| Left out | Why |
|---|---|
| Volume from a daily traffic count | Designed (formula and test). One more thing to explain; not needed to prove the idea |
| Ordering project runs through the CAT website | The website's run ticket requires `data.csv.gz`. A project run sent that way ends as failed, which is the safe outcome |
| Building links from road data | Done later, as a beta (section 5.4); the first release of this document left it out |
| MOVES6 | Released in October 2026. The image is on MOVES5. Moving is planned for the whole image, not just this feature |
| MOVES-Matrix | See section 10 |

## 9. Red team: how this can be wrong or misused

Written by the people who built it, trying to break it. Ordered by how much damage each could do.

**Read this one first. It was found after the list was written, and it has been decided.** With the
county's registration ages, project-scale NOx, CO, hydrocarbons and exhaust particulates per mile are 1.5
to 2.9 times what a county-scale run gives for the same fleet, road type, hour and speeds (section 7.4).
CO2 is within 5%. Tim Fraser decided that the project-scale default is now **travel-weighted ages**: each
age's share of registered vehicles is multiplied by how many miles vehicles of that age drive, and
renormalised, which is what MOVES itself does at county scale. A project run does this before MOVES
reads the table. The switch back is `PROJECT_AGES=registration` in the environment, or
`"project_ages": "registration"` in `parameters.json`; the environment wins. A `sourcetypeagedistribution.csv`
that the user supplies is used as given, with no weighting. The measured effect of the default on the
county-against-project comparison: NOx 1.53% and exhaust PM2.5 1.83% above the county run per mile, CO2 0.08%, on urban unrestricted roads. <!-- source: release/county_vs_project_default.csv --> The earlier test of the
same idea (section 7.5) closed the gap to under 2% for NOx and exhaust particulates.

The same decision started a second option: **county ages**. The age table has three settings, chosen by
`AGE_SOURCE` in the environment (it wins) or `"age_source"` in `parameters.json`, the same at both scales
(`moves_anywhere/scripts/adapt_ages_county.R`). `national`, the default, is the national table for the run
year, as before. `county` is the county's own table from EPA's National Emissions Inventory county
databases, from the nearest inventory year (2020 or 2023), used as is. `county_adjusted` is the county's
own table in 2020 and 2023; in other years it is the national table times the county-to-national ratio of
the nearest inventory year, interpolated between 2020 and 2023, each ratio kept between 0.25 and 4.
Long-haul truck types (53 and 62) always keep the national table. The reference file is included in the image (11.8 MB; 3,223 counties for 2020 and 3,224 for 2023). The default is **national**, and it stays national until
the measured change in county results has been reviewed, because a county default changes every published
county result. What this still leaves open: the tool's default is a choice we made, not a measurement of a
real road. Anyone quoting project-scale criteria pollutants from defaults should say which age table was
used; `diagnostics.txt` and `_project_inputs.csv` record it, and `_age_source.txt` records the county
option.

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
   January. The external comparison in section 7.3 is affected by it. Keeping this default is now a
   decision (D92, 2026-11-18): MOVES's own fuel formulation tables are unreliable, and there are no good
   public tables to compare against. The effect is still not measured.
4. **We replaced MOVES's validation with our own, narrower checks.** With validation off, MOVES will
   run inputs it would otherwise reject. We check the cases we have met (hours, road types, mix sums,
   row counts, empty results). We have surely not met them all. A table that loads but is wrong in a way
   we did not think of would produce numbers.
5. **We only detect an empty result, not a partly empty one.** If MOVES produced CO2 but silently
   dropped a pollutant, or produced nothing for one link, the run would pass. There is no check that
   every link and every requested pollutant appears in the output. The review found one concrete way
   to get there: a user's soak-time table covering only some vehicle types switched off the defaults
   for all the others. That case is fixed (the gaps are now filled and counted in `diagnostics.txt`),
   but the general check is still missing. A user's own operating-mode table is also only checked for
   blanks, range and sums, not for whether its vehicle types and pollutants match the run.
6. **One hour is easy to misuse.** Multiplying one hour by 24, or by 8,760, is wrong: traffic, speeds,
   temperature and starts all change by hour. The tool does one hour per run and has no helper for many
   hours yet.
7. **A 0 mph link means "everyone idles for an hour".** See 7.3. The per-link table prints a large total
   with zero miles. `diagnostics.txt` now adds a note for each such link; `linkdata.csv` does not.
8. **One average speed is not a traffic stream.** A link at the mean speed understates the effect of
   congestion, because slow driving emits disproportionately. For intersections EPA recommends
   operating-mode distributions or drive schedules, not an average speed. The tool accepts both but
   defaults to neither.
9. **The default vehicle mix ignores what kind of road it is beyond MOVES's five road types.** An urban
   arterial carrying a port's trucks and a suburban collector get the same mix.
10. **Thin testing.** One county and one hour pass end to end. A second county failed twice for reasons
    we then found. That is two for two on "the first new case breaks something". Not tested at all:
    weekends, winter (beyond EPA's January exercise, section 7.6), rural road types, more than 32 links,
    evaporative emissions, air toxics, rate mode, electric vehicle shares, counties whose NEI
    data are thin, years outside the NEI range.
11. **The reference numbers are our own.** The test that compares a run with stored results proves the
    code did not change. It does not prove the stored results are right. The only outside comparison is
    with a MOVES3 example that cannot match exactly.
12. **Run time for real projects is still mostly unknown.** Seven links took 621 s of MOVES, 16 took 1,487 s
    and 32 took 1,882 s, on one laptop. A corridor study can have hundreds of links, and we have no
    measurement past 32. The link builder refuses more than 40 links by default for this reason.
13. **How it was built.** The code was written in one day by AI agents working from a written plan, with
    one orchestrating agent reviewing diffs and running every container test. The plan was reviewed
    independently before coding, and the code was reviewed once by a separate agent that had not
    written it. No person has read all of it. Defects found after the writing agents reported their
    units done: vehicle counts came out as zero in the results file; one test would have compared the
    new code with itself once committed; stale result files from an earlier run in the same folder were
    shipped with the wrong kind of run; a partial soak-time table dropped every default; a run file
    using single quotes was read as a project run by some scripts and a county run by others. All are
    fixed. The review found no way for the change to alter a county run in a clean folder. Assume there
    are more defects of the same kinds.
14. **County averages come from the default database's national tables**, not from the county, for
    speeds, road type shares, hourly shares, starts and ages. "County average" in this document often
    means "national pattern applied to the county's mileage". Only vehicle counts and annual mileage are
    county-specific (from NEI), and those are interpolated or projected for years NEI does not cover.
15. **County ages change the answer a lot, and the default has not moved.** With the earlier single
    `AGE_SOURCE=county` setting on a
    Tompkins County (NY, 2022) county run, against national ages: CO2 0.962, NOx 0.676, exhaust PM2.5 0.716,
    CO 0.722 and hydrocarbons 0.687 of the national-age result. Cars are 1.9 years younger and light trucks
    2.3 to 3.4 years younger. This came from a partial reference file (2020 for New York only; the full file is now in the image), so treat it
    as one measurement, not a calibration. It was made before the setting was split into `national`,
    `county` and `county_adjusted`, and has not been repeated for `county` or `county_adjusted`. The
    default stays `national` until the effect has been reviewed.
    <!-- source: release/county_ages_effect.csv -->

## 10. Reference data, and whether MOVES-Matrix is needed

We searched for published project-scale examples that include both inputs and results.

| Source | MOVES version | Has inputs | Has results | Use |
|---|---|---|---|---|
| EPA CO guidance EPA-420-B-21-047, Appendices A and B | MOVES3 | Printed in the text (fleet and fuel in figures) | Three printed CO values | Order-of-magnitude check (section 7.3) |
| EPA MOVES5 training files (September 2025), Module 7 | MOVES5 | Yes | Yes (EPA's answer-key databases) | Best version match. Used as an example and compared in section 7.6 |
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
| Finish the pending checks in 7.5 | Done: full gate passed on commit 282fb16 (and earlier on 2758e4f and 8f48468) | |
| Vehicle ages at project scale: registration or travel-weighted (section 7.4) | Decided: travel-weighted by default; `PROJECT_AGES=registration` switches back (section 9) | The reference results changed with it |
| County ages (`AGE_SOURCE=county` or `county_adjusted`) as the default at county scale | Open: `national` stays the default until the measured change is reviewed (section 9) | Changes every published county result; the one measurement predates the split into three settings |
| Hourly county runs crash in the summary step (section 7.4) | Fixed in this release, with a replay test | Why that run had no population rows is not settled |
| Warn or refuse when a link is too long to cross in the hour | Backlog | |
| Independent review of the code | Done once (section 9, item 13) | A person should still read it before any merge |
| Extended idle and hotelling hours as columns of `linkdata.csv` | Backlog | Today they are only in the raw activity file |
| Check a user's operating-mode table against the run's vehicle types and pollutants | Backlog | |
| Re-run county-scale runs with link and hourly output (section 3) and put them under test | Backlog | Run and confirmed to compute when MOVESAI was built; no automated test and no reference result exists |
| Check every link and pollutant appears in the output (red team 5) | Backlog | |
| Warn on 0 mph links in `diagnostics.txt` (red team 7) | Done: built (`task_summarize.R`); a flag in `linkdata.csv` stays in the backlog | |
| A flag on each `linkdata.csv` row for "used a default" (red team 1) | Backlog | |
| Regional fuel instead of New York's (red team 3) | Decided: New York fuel stays the default for every county (D92, 2026-11-18) | MOVES's own fuel formulation tables are unreliable, and there are no good public tables to compare them against. A user can still supply `fuelsupply.csv` and `fuelformulation.csv` |
| Many hours in one command | Backlog | Each hour is a separate MOVES run |
| Run time for 20, 50, 200 links | Backlog | |
| EPA's MOVES5 training exercise as a reference | Done (section 7.6) | The corrected run is the one reported |
| Daily-traffic shortcut | Designed, not built | |
| Links from road and traffic data | Built as a beta (`links.sh`, section 5.4 and [README_link_sources.md](README_link_sources.md)) | Federal data only; see the limits in that guide. Beta: tried on a few places, rules may change |
| Link builder: speeds are county defaults capped by the posted limit; counts are not hourly counts | Open | Section 5.4 |
| MOVES6 | Planned for the whole image | |

---

## For agents

- Code: `moves_anywhere/scripts/project_functions.R` (run-file rules, `project_read`, `project_runspec`,
  `project_check_im`), `adapt_link.R`, `adapt_offnetwork.R`, `importer_template_project.xml`,
  `importer.R` (project branch), `task_check_import.R`, `task_get_linkdata.R`; project branches in
  `task_adapt.R`, `task_importer.sh`, `task_postprocess.R`, `task_summarize.R`, `task_compress_outputs.sh`,
  `task_pack.sh`, `task_push_outputs.sh`, `task_runspec.R`.
- A run is a project run when `rs_custom.xml` contains `<modeldomain value="PROJECT"/>`. Every change to
  an existing script is behind that test, with three exceptions that reach county runs: the `AGE_SOURCE`
  setting (default `national`, the same age table as 3.1.0), the summary-step fix and the partial-table fix.
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
