# README `/reference`

A folder containing a series of `.csv` or `.rds` files containing MOVES Input data for reference.

- ./hpmsvtypeyear.csv
- ./nei_sourcetypeyear.rds
- ./nei_sourcetypeyearvmt.rds
- ./nei_vmt_by_sourcetype_roadtype.rds
- ./sourcetypeyear.csv
- ./urban_areas.rds
- ./urban.rds
- ./VMT.rds
- ./VPOP.rds
- ./nei_sourcetypeagedistribution.rds: county vehicle-age shares (`geoid, year, sourceTypeID, ageID` 0 to 40, `ageFraction`), from EPA's NEI 2020 and 2023 county databases (gaftp.epa.gov, `CDBs_for_all_counties`). 3,223 counties in 2020 and 3,224 in 2023, 13 source types each, sums to 1 per county, type and year. Built by `dev/make_nei_ages_reference.R`; the 2020 tables (MOVES3, ages 0 to 30) are converted with EPA's MOVES3-to-MOVES5 age conversion, the 2023 tables are used as given, and long-haul types 53 and 62 take the national table. In 13 Ohio counties (39001, 39015, 39069, 39071, 39075, 39105, 39111, 39117, 39121, 39125, 39149, 39161, 39163; 2020, motor homes, type 54) the conversion gave small negative shares (sums from -0.0001 to -0.108), which were set to 0 before renormalising. Used only when `AGE_SOURCE=county`.
