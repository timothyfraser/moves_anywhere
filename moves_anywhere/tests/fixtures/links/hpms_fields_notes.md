# HPMS layer fields (checked live 2026-11-17)

Layers: `HPMS_FULL_NY_2025`, `HPMS_FULL_TX_2025`, `HPMS_FULL_WY_2025` (`.../FeatureServer/0?f=json`, keyless).

- All three layers have the same 105 fields.
- County field: `county_id`, type `esriFieldTypeSmallInteger` (a number, not text). It holds the 3-digit
  county code (the last three digits of the 5-digit FIPS) without leading zeros: distinct values start
  1, 3, 5, 7 in all three states. NY `county_id=109` (Tompkins, FIPS 36109) returns 6,154 sections.
  There is no `county_code` field (a request naming it fails with HTTP 500).
- So the county `where` is `county_id=<as.integer(substr(fips, 3, 5))>`; the three states agree, so
  `links_county_where()` needs no run-time lookup.
- Every field of the plan's `outFields` list exists in all three layers under exactly the same lower-case
  names (`route_id, begin_point, end_point, f_system, urban_id, facility_type, through_lanes, aadt,
  aadt_single_unit, aadt_combination, k_factor, dir_factor, speed_limit, section_length, data_year`),
  and so does `objectid` (used for paging).
- GeoJSON responses omit properties that are null, so a section can lack a field; the parser makes it NA.
- The saved 40-feature fixture was requested before `k_factor`, `dir_factor` and `data_year` were added
  to `outFields`; it has none of them, which exercises the NA path.

## access_control (checked live 2026-11-18, unit B1)

- All three 2025 layers have `access_control`, type `esriFieldTypeSmallInteger`, alias `ACCESS_CONTROL`.
  The layer metadata gives no description and no domain for it (keys: modelName, nullable, editable,
  defaultValue, domain = null, name, alias, type). The meaning of the codes comes from the FHWA HPMS
  field manual: 1 full control, 2 partial control, 3 no control.
- Values seen (one `outStatistics` request per state, sections grouped by `access_control` and `f_system`):
  1, 2, 3 and missing; nothing else.
  - NY: f_system 1 is 1 on 48,202 sections (4,505 mi), missing on none; f_system 2 is 1 on 14,992
    (1,523 mi), 2 on 2,927 (241 mi), 3 on 812 (63 mi). Full control also appears on f_system 3-7
    (6,423 sections, 544 mi). 17,019 class-7 sections and 55,647 sections without f_system are missing it.
  - TX: f_system 1 is 1 on 44,279 (3,482 mi), missing on 1,912 (4,211 mi); f_system 2 is 1 on 20,758,
    2 on 96, 3 on 25, missing on 814. Full control on f_system 3-7: 43,196 sections (4,056 mi).
    Most class 4-7 mileage is missing it (about 302,700 mi).
  - WY: f_system 1 is 1 on 11,170 (913 mi) and missing on 11,210 (1,189 mi); f_system 2 is 1 on 43,
    missing on 42. Classes 4-7 are mostly 3 or missing.
- Live Ithaca box (1,961 sections): 1 = 36, 2 = 18, 3 = 1,703, missing = 204.
- Rule built in `links_road_type()` (link_build.R): f_system 1 is always restricted (road type 2 rural,
  4 urban); f_system 2 is restricted when `access_control` is 1 or missing (missing gives a `default`
  source row, "access control not coded; class 2 treated as restricted") and unrestricted (3, 5) when 2
  or 3; f_system 3-7 or missing is always unrestricted, with a note when `access_control` is 1.
- Why the field counts only on class 2: states code full control on sections MOVES should not treat as
  freeways. NY codes 1 on 6,423 class 3-7 sections (544 mi) and TX on 43,196 (4,056 mi, 12,244 of them
  class 5 collectors), so letting `access_control == 1` decide would turn arterials, collectors and
  locals into restricted roads. On class 2 it does the job it is needed for: NY has 2,927 partial and 812
  no-control class-2 sections (304 mi), such as NY-13 through Ithaca, which the class-only rule made
  restricted. Class 1 is coded 1 wherever it is coded (NY 48,202, TX 44,279, WY 11,170 sections).
- Live Ithaca box under this rule, sections by road type: 3 = 160, 4 = 34, 5 = 1,767 (class-only rule:
  4 = 54, 5 = 1,747); links: 3 = 32, 4 = 11, 5 = 367.
- `hpms_ny2025_ithaca_box_40_access.geojson`: the same 40 sections as `hpms_ny2025_ithaca_box_40.geojson`
  (matched on route_id, begin_point, end_point; f_system, urban_id, facility_type, aadt, lanes, speed and
  length identical), re-requested by those keys with `access_control`, `k_factor`, `dir_factor` and
  `data_year` in `outFields`. A box request with `resultRecordCount=40` no longer returns the same 40.
  On it, 6 of 15 links change road type: NY-13 (route 100061031, mileposts 14.97-16.12, f_system 2,
  access_control 2 or 3) goes from 4 to 5 in both directions.

## aadt_vt (checked 2026-11-18)

- `aadt_vt` is `esriFieldTypeString`, alias `AADT_VT`, in all three layers. What its values (such as the
  `A` seen on Wyoming local streets) mean, actual count versus estimate: not stated in the layer metadata
  (no description, no domain). The same holds for `aadt_single_unit_vt` and `aadt_combination_vt`.

## Field names by layer year (checked live 2026-11-18, unit B9)

One metadata request per layer (`.../FeatureServer/0?f=json`). Object id field is `objectid` in all.
NY 2022 and NY 2025 responses are kept as `hpms_ny2022_layer_meta.json` and `hpms_ny2025_layer_meta.json`.

| Layer | fields | route / mileposts | year | county | urban | length |
|---|---|---|---|---|---|---|
| NY 2020 | 76 | route_id, begin_point, end_point | year_record | county_code | urban_code | none |
| NY 2022 | 101 | routeid, beginpoint, endpoint | year_record | county_id | urban_id | none |
| NY 2023 | 89 | routeid, beginpoint, endpoint | none | county_id | urban_id | none |
| NY 2024 | 105 | route_id, begin_point, end_point | data_year | county_id | urban_id | sectionlength |
| NY 2025 | 105 | route_id, begin_point, end_point | data_year | county_id | urban_id | section_length |
| TX 2022 | 101 | routeid, beginpoint, endpoint | year_record | county_id | urban_id | none |
| TX 2025 | 105 | route_id, begin_point, end_point | data_year | county_id | urban_id | section_length |
| CA 2022 | 101 | routeid, beginpoint, endpoint | year_record | county_id | urban_id | none |
| CA 2025 | 105 | route_id, begin_point, end_point | data_year | county_id | urban_id | section_length |
| CA 2019 | 83 | route_id, begin_point, end_point | year_record | county_code | urban_code | none; no aadt_combination |

All have f_system, facility_type, through_lanes, aadt, aadt_single_unit, k_factor, dir_factor,
speed_limit and access_control. `links_fetch_hpms()` maps these through `LINKS_HPMS_ALIASES` (link_sources.R).
Not checked: whether county_code / urban_code hold the same values as county_id / urban_id.
