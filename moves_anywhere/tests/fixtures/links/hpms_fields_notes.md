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
