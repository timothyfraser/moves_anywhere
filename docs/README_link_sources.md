# Building project-scale links from federal road data (beta)

**Beta.** This command is new. It has been tried in a few places, and its rules may change in the next release. Read `link_summary.txt` and `link_sources.csv` before you run MOVES on its output.

A project-scale run estimates emissions on individual roads for one hour. It needs a table of road **links** (a link is one stretch of road): how long each link is, how many vehicles use it in the run's hour, how fast they go and how steep it is.

`links.sh` builds that table from public federal data, so you do not have to type it in. This guide says what the command does, where each number comes from, and where it can mislead you. To run a project-scale run itself, see [Project-scale runs](README_project_scale.md).

## What the command does

You give it a place and a folder that holds `rs_custom.xml` (a project run file, which MOVES calls a runspec). It looks up the federal road sections in that place (a section is a stretch of road with its own federal record), joins them into links, adds traffic and grade, and writes the link files into the same folder.

It does not run MOVES. When it ends, check the files, then run MOVES with `run.sh`.

```bash
bash moves_anywhere/links.sh <folder> --place "<west,south,east,north>" --state <two letters> [--max-links N] [--no-fill] [--overwrite] [--image IMAGE]
bash moves_anywhere/links.sh <folder> --place <5-digit FIPS> --state <two letters> [--max-links N] [--no-fill] [--overwrite] [--image IMAGE]
```

| Option | Meaning |
|---|---|
| `<folder>` | The folder with `rs_custom.xml`. The links are written here. Required. |
| `--place` | Required. Either a box, four numbers `west,south,east,north` in degrees (west less than east, south less than north), or a 5-digit county FIPS code. |
| `--state` | Required. Two letters, for example `NY`. |
| `--max-links N` | Refuse to write more than N links. Default 40. See "The link limit". |
| `--no-fill` | Do not add the remainder link that stands in for roads with no count. See "Roads with no count". |
| `--overwrite` | Replace an existing `link.csv`. Without it the command refuses. |
| `--image IMAGE` | The Docker image (the packaged software the command runs in) to use. Default `tmf77/moves-anywhere:v3`, or the environment variable `MOVES_IMAGE` if set. The published `v3` image is release 3.2.0 and contains the link builder. <!-- source: moves_anywhere/links.sh:19,88 -->

`links.sh` needs a folder with a project `rs_custom.xml`. No command turns `parameters.json` into one outside the image, so start from the run file of the shipped example (Tompkins County, NY, 2022, July weekday, hour 8):

```bash
mkdir my_run
cp moves_anywhere/inputs_project/rs_custom.xml my_run/
bash moves_anywhere/links.sh my_run --place 36109 --state NY
bash moves_anywhere/links.sh my_run --place "-76.52,42.42,-76.47,42.46" --state NY --overwrite
```

Then check `my_run/link_summary.txt`, delete `my_run/rs_custom.xml`, save a `my_run/parameters.json` (full file below) and run `bash moves_anywhere/run.sh my_run`. With no run file, the image writes a new one whose road types match your links:

```json
{"level": "project", "geoid": "36109", "year": 2022, "month": 7, "day": "weekday", "hour": 8}
```

If you keep a run file instead, it must name the same county, year, month, day type and hour as `parameters.json`, and every road type it selects needs a link, or the run is refused (see [When a run is refused](README_project_scale.md#when-a-run-is-refused)).

**Inside an ordinary run (no separate command).** The same builder runs from `parameters.json`:

- Put a project `parameters.json` (`"level": "project"`) with a `place`, and optionally `max_links`, in a folder with no `link.csv`.
- Run `bash moves_anywhere/run.sh <folder>`. The folder needs no `rs_custom.xml`.
- The image builds the links, taking the state from the first two digits of `geoid`.
- It writes a provisional run file for the builder, then the real one from the road types in the new `link.csv`, and runs MOVES in the same run.
- `parameters.json` has no key for `--no-fill`, so the remainder link stays on.
- A refusal stops the run with the same `links:` line.

To check the links before MOVES runs, use `links.sh`. The keys are listed in [Project-scale runs](README_project_scale.md).

Docker must be installed and running. When the command ends it returns an exit code: 0 means links were written, 2 a usage error or a missing input, and 3 that Docker is missing or not running. If the builder refuses (for example, too many links), it prints one line starting `links:` and writes the same line to `link_summary.txt`.

## What it writes

All files go into your folder.

| File | Contents |
|---|---|
| `link.csv` | The link table MOVES reads: `linkID, roadTypeID, linkLength, linkVolume, linkAvgSpeed, linkAvgGrade, linkDescription`. |
| `linksourcetypehour.csv` | The vehicle mix of each link, for links that have both truck counts. Written only when at least one link does. |
| `links.geojson` | The shape of each link as a line, for a map. Remainder links (see "Roads with no count") have no shape. |
| `link_sources.csv` | One row per value per link: `linkID, field, value, source, detail, data_year`. The source is `measured`, `derived` or `default`. |
| `link_summary.txt` | The layer used, links per road type, sections left out, the share of values that are defaults, count years, the year factor and the number of requests. |
| `sources/` | Every response the command received from the federal services, and `requests.csv` listing each request. |

## Where the data comes from

| Source | Owner | Year | Address |
|---|---|---|---|
| Highway Performance Monitoring System (HPMS), one layer per state, named `HPMS_FULL_<ST>_<YYYY>` | Federal Highway Administration (FHWA) | The layer nearest the run year. The 2025 layers are the newest. | `https://geo.dot.gov/server/rest/services/Hosted` (layer `/FeatureServer/0`) |
| 3D Elevation Program (3DEP) elevation service | U.S. Geological Survey (USGS) | Best available terrain model at each point | `https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer` |

Both are free and need no key. FHWA and USGS publish them as U.S. government data. This command uses no other road, traffic or elevation source.

HPMS gives each public road section a functional class, an urban code, a length, and fields for a daily vehicle count (AADT, annual average daily traffic), counts of single-unit and combination trucks, a posted speed limit, lanes and a direction factor.

The count fields are filled for nearly every arterial and collector but for almost no local street (see "Roads with no count"). Each section also carries the year of its count (`data_year`). The command picks the state layer whose year is nearest the run year; if two are equally near, the earlier one.

### Field names differ by layer year

FHWA renamed fields between years. The command asks each layer for its field names and maps them to one set. This table was checked on 2026-11-17 and 2026-11-18:

| Layer year | Route and mileposts | Count year | County | Urban | Length |
|---|---|---|---|---|---|
| 2020 | `route_id`, `begin_point`, `end_point` | `year_record` | `county_code` | `urban_code` | none (computed from mileposts) |
| 2022 | `routeid`, `beginpoint`, `endpoint` | `year_record` | `county_id` | `urban_id` | none |
| 2023 | `routeid`, `beginpoint`, `endpoint` | none | `county_id` | `urban_id` | none |
| 2024 | `route_id`, `begin_point`, `end_point` | `data_year` | `county_id` | `urban_id` | `sectionlength` |
| 2025 | `route_id`, `begin_point`, `end_point` | `data_year` | `county_id` | `urban_id` | `section_length` |

`county_id` is a number holding the 3-digit county code, not the 5-digit FIPS. A layer with no count-year field gets no year factor (see below).

## Measured, derived and default

Every value on every link has a label in `link_sources.csv`.

| Label | Meaning | Examples |
|---|---|---|
| `measured` | Taken from a federal record as it stands. | Daily count, posted speed limit, truck counts, the posted limit when it caps the speed. |
| `derived` | Computed from measured values. | Hourly volume, year factor, grade from elevation, link description from route and mileposts, the split of a two-way count. |
| `default` | A county or national average used because no record exists. | A link's road type when class 2 has no access-control code, the vehicle mix of a link without truck counts, grade 0 when it cannot be measured, every remainder link. |

`link_summary.txt` reports what share of all source rows are defaults. Look at it first.

## Road type

MOVES has five road types: off-network (1), rural restricted (2), rural unrestricted (3), urban restricted (4) and urban unrestricted (5). The command assigns only the four on-road types, 2 to 5, because HPMS sections are roads; off-network links (road type 1, such as a parking lot) are not built from HPMS.

"Restricted" means access is controlled, as on a freeway. The command decides from the HPMS functional class and, for class 2, the access-control code.

| HPMS functional class | Road type |
|---|---|
| 1, Interstate | Always restricted. |
| 2, other freeways and expressways | Restricted when access control is 1 (full control) or not coded. Unrestricted when it is 2 (partial) or 3 (none). A missing code is labelled `default`. |
| 3 to 7, or no class | Always unrestricted, whatever access control says. |

Rural or urban comes from the urban code (99999 or missing is rural). The access-control code decides only on class 2 because states code "full control" on thousands of ordinary arterials, collectors and local streets. If that code decided for every class, those roads would become freeways. On class 2 it separates real freeways from roads such as NY-13 through Ithaca, which are partly at grade.

## Hourly volume

HPMS gives a count per day. MOVES needs a count for one hour. The command makes it in three steps.

1. **Direction.** A count covers both directions. A two-way section becomes two links, a primary and an opposite one, with the share given by HPMS's direction factor when it is between 50 and 100 percent, otherwise half each. One-way sections stay one link.
2. **Year factor.** The count is for its count year, and the run may be for another year. The count is scaled by the county's vehicle-miles in the run year divided by the county's vehicle-miles in the count year (all vehicle types, from the same county reference data a county run uses). Equal years, or a year that cannot be looked up, give 1; the second case is labelled `default` and says why.
3. **Hour.** The scaled daily count is multiplied by the county's share of traffic in the run's month, in the run's day type and in the run's hour, for each vehicle type on the link's road type, and the results are summed. The month, day and hour shares are those the county adapters produce, so a link follows the same daily pattern as a county run.

Each link's vehicle mix is the county's default mix for its road type. When a link has both a single-unit and a combination truck count, the command uses those truck shares instead: the single-unit share goes to source types 52, 53 and 54 and the combination share to 61 and 62, each split by the county default.

HPMS single-unit counts include buses. Here, buses stay in the non-truck part of the mix, so the truck share is a little high and the bus share a little low.

## Speed

Each link's speed is the county's default average speed for its road type. Where the posted speed limit is lower than that default, the limit is used instead, and the row says so. Posted limits are a ceiling on free-flowing traffic, not a measure of the speed vehicles reach in traffic.

## Grade

For each link longer than 200 m, the command sends the link's line to the USGS elevation service and takes elevation samples every 25 m. It computes the average grade from end to end, in percent, signed along the link's direction. The opposite link gets the opposite sign. Grade is capped at plus or minus 12 percent. Grade is 0 and labelled `default`, with a reason, when:

- the link is under 200 m;
- the end-to-end grade and a line fitted through all samples disagree by more than 3 percentage points (a sign of a bridge or a cut);
- the request fails twice; or
- the response has no usable elevations.

## Roads with no count

HPMS counts nearly every arterial and collector but almost no local street. In Tompkins County, New York, 0.1 percent of the 939 miles of local streets and minor collectors have a count, against 99.8 percent of the miles of the higher classes. Without a fix, a run for a box would leave out the traffic on those streets.

The command fills the gap with the county's leftover traffic. For each unrestricted road type (3 and 5) it takes the county's vehicle-miles for the run's hour, subtracts the vehicle-miles already on counted sections, and gives the remainder to one extra link: the remainder link.

Its length is the uncounted miles in your place, capped at half an hour of travel at the county default speed. Its volume is the remainder divided by that length. Its grade is 0. Every value on it is labelled `default`.

Restricted road types are never filled; leftover traffic there is reported in the summary as unplaced. When counted traffic already exceeds the county total, the remainder is 0 and the summary flags it.

For a box, the remainder is shared by the uncounted miles in the box out of the uncounted miles in the county. This assumes equal traffic on every uncounted mile of the county, so a downtown box receives the county's average local-street volume.

The switch is `--no-fill`. With it no remainder link is added; the summary still prints the numbers.

## The link limit

The command refuses to write more than 40 links unless you set `--max-links`. The reason is run time: MOVES takes longer with more links.

Measured on one workstation: 7 links took 621 seconds of MOVES (100 pollutant-process pairs), 32 links took 1,882 seconds (31 pairs), and the 17-link live build took 371 seconds (84 pairs, the set a county run file gets).

Time grows with links and with pollutant-process pairs, not in proportion to either; the refusal message quotes the first two figures as a rough guide.
<!-- measured; record kept by the maintainers -->
 The limit counts remainder links. If a place gives too many links, make the box smaller, or raise the limit and expect a longer run.

## Tested

One live build, then one run of MOVES on its output (Tompkins County, NY, 2022, a July weekday, 8:00 to 8:59). The box was `-76.499,42.438,-76.495,42.441` in Ithaca, NY.

- The build used the 2022 HPMS layer, fetched 18 sections and wrote 17 links (16 counted road links and one remainder link) in 87 s. <!-- measured; record kept by the maintainers -->
- 10.2% of the 167 values in `link_sources.csv` were defaults. <!-- measured; record kept by the maintainers -->
- MOVES took 371 s for the 17 links, finished with status ok, and every link appears in `linkdata.csv`. <!-- measured; record kept by the maintainers -->
- 13 of the 16 road links were within 10% of the flat fixture's CO2 per mile. The three that were not are the steep links: +65% at +7.1% grade, and -51% and -57% at -8.3% and -10.9%. The fixture is flat, so higher CO2 per mile uphill and lower CO2 per mile on steep downhills are expected. <!-- measured; record kept by the maintainers -->
- The remainder link (0.001 mi, 90.9 vehicles an hour) ran as an ordinary link and is 0.014% of the run's vehicle-miles. <!-- measured; record kept by the maintainers -->
- A first attempt failed with HTTP 500 because the field names of the 2022 layer differ from the 2024 and 2025 layers; the builder now reads each layer's field list (see "Field names differ by layer year"). <!-- measured; record kept by the maintainers -->

This is one place and one hour. It shows that the builder's output runs in MOVES; it does not show the traffic numbers are right for any road.

### Against measured counts: Manhattan, 2022

A second build, in Manhattan (`-73.9760,40.7435,-73.9705,40.7470`, First Avenue to the FDR Drive, about East 34th to 37th Street; a July weekday, 7:00 to 7:59), wrote 19 links. Its hour volumes were compared with measured counts for the same hour of a weekday. <!-- measured; record kept by the maintainers -->

- The builder's volumes were higher than the counts in 6 of 8 one-direction comparisons: builder over measured, median 1.38, range 0.87 to 1.96. <!-- measured; record kept by the maintainers -->
- The best comparison is the Queens Midtown Tunnel approach, against the MTA's hourly toll counts for 20 weekdays of July 2022. Both directions together: 6,378 vehicles from the builder against 4,619 measured (1.38). The split was the wrong way round for this hour: the builder sent 59% toward Queens (HPMS's direction factor, which does not say which direction is the busy one), and 58% went toward Manhattan. <!-- measured; record kept by the maintainers -->
- The street counts are weaker: the nearest New York City counts are from 2015 to 2024, outside July, and some cover a single day.

So, in this place and hour, the builder's hour volumes were about 38% too high (median ratio 1.38, range 0.87 to 1.96), and its direction split at a peak hour should not be trusted. Give your own counts in `link.csv` when you have them.

## Limits and misuse

- **No counts on most local streets.** See the remainder above. Its volume is an average, not a measurement.
- **Posted limits are a ceiling, not congested speeds.** In traffic, vehicles go slower than the posted limit, and emission rates depend on that.
- **Bare-earth elevation.** The 3DEP model is the ground, not the road. A bridge deck can be many metres above it, so grade on bridges is flagged or set to 0. Links under 200 m are not graded.
- **Two-way roads.** A section's count is both directions together. It is split by the direction factor where HPMS gives one, otherwise half each. That is an assumption.
- **Count year.** Federal counts are for the year in `data_year`. The year factor scales them with county totals, not with the road's own growth.
- **Truck counts.** Many minor roads have no truck counts; their mix is the county default.
- **Federal counts look authoritative and are not project data.** EPA expects project traffic data for regulatory work (for example conformity or a permit). This table is for screening, teaching and comparing options, not for a submission.
- **Services can change.** The federal services have no promised uptime or rate limit. The command retries once after a server error and saves every response in `sources/`, so you can see what the services returned. The command cannot rebuild a table from those files; it fetches again each time.
