# make_nei_ages_reference.R ###################################################
#
# What:      Builds the county vehicle-age reference table from EPA's NEI county databases,
#            converted to the ages 0 to 40 that MOVES5 wants.
# Does:      Reads the age tables (countyID, yearID, sourceTypeID, ageID, ageFraction) extracted from
#            EPA's NEI 2020 and 2023 county databases. A table with ages 0 to 30 (2020) is converted
#            with EPA's own rule, ported from
#            /cat/EPA_MOVES_Model/database/ConversionScripts/Convert_MOVES3_input_to_MOVES5.sql:
#              - ages 0 to 29 unchanged;
#              - age 30 means "30 and older": new age 30 = old age 30 * 2 / ((max + 2) - 30), where
#                max is the vehicle type's maximum age (the SQL's maxage_tmp line);
#              - ages 31 to max follow a straight line from new age 30 down to zero at max + 1:
#                new30 / (30 - (max + 1)) * (age - 30) + new30;
#              - ages above 40 are summed into 40 (ages 41 and up are dropped after the sum);
#              - then types 53 and 62 are replaced by the national default for that year.
#            A table that already has ages 0 to 40 (2023) is used as given, except types 53 and 62
#            are replaced by the national default for that year too (the SQL does this for every
#            table it converts, and the long-haul tables in the NEI databases are not national
#            averages as the TSD says, so the same replacement is followed for 2023; see
#            docs/audit/project_scale_2026-11/sources/nei_county_ages.md).
#            Each county, year and vehicle type is then renormalised to sum to exactly 1.
# Called by: Developer tool. Not part of a run.
# Reads:     --in   one or more .csv or .csv.gz files, or folders of them (any mix)
#            --national  csv with sourceTypeID, yearID, ageID, ageFraction: the MOVES national default
#                        age table for every year in the inputs (needed for types 53 and 62)
# Writes:    --out  an .rds (saveRDS, gzip like the other files in moves_anywhere/scripts/reference/):
#            data frame geoid (5-character string), year, sourceTypeID, ageID (0 to 40), ageFraction
# Exits:     0; stops with a message on a missing county-type, a duplicate or an unknown vehicle type
#
# Usage (from the repository root):
#   Rscript moves_anywhere/dev/make_nei_ages_reference.R --in <file-or-folder> [<file-or-folder> ...] \
#       --national <national.csv> --out moves_anywhere/scripts/reference/nei_sourcetypeagedistribution.rds
#
# Export the national table from the image's default database (needs Docker; about 20 seconds):
#   MSYS_NO_PATHCONV=1 docker run --rm --name nei-national --entrypoint bash tmf77/moves-anywhere:v3.1.0 -c \
#     'service mysql start >/dev/null 2>&1; while ! mysqladmin ping --silent; do sleep 1; done;
#      mysql -N -B -e "select sourceTypeID,yearID,ageID,ageFraction from movesdb20241112.sourcetypeagedistribution
#      where yearID in (2020, 2023) order by 2,1,3"' | grep -v '^mysqld is alive' | tr '\t' ',' > national_body.csv
#   (echo "sourceTypeID,yearID,ageID,ageFraction"; cat national_body.csv) > national.csv
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr) })

# EPA's maxage_tmp line (Convert_MOVES3_input_to_MOVES5.sql line 24): maximum age per source type
max_age_table = data.frame(
  sourceTypeID = c(11, 21, 31, 32, 41, 42, 43, 51, 52, 53, 54, 61, 62),
  maxAgeID     = c(52, 62, 57, 55, 51, 51, 34, 35, 56, 56, 44, 43, 39))
long_haul = c(53L, 62L)

# convert_ages_30_to_40(): ports the SQL for one data frame with columns
# geoid, year, sourceTypeID, ageID (0 to 30), ageFraction. Returns ages 0 to 40.
convert_ages_30_to_40 = function(x){
  x = x %>% mutate(sourceTypeID = as.integer(sourceTypeID), ageID = as.integer(ageID))
  if(any(!x$sourceTypeID %in% max_age_table$sourceTypeID)){ stop("unknown sourceTypeID in age table") }
  keep = x %>% filter(ageID <= 29)
  tail = x %>% filter(ageID == 30) %>%
    inner_join(max_age_table, by = "sourceTypeID") %>%
    mutate(new30 = ageFraction * 2 / ((maxAgeID + 2) - 30))
  # ages 30 to 70 for every tail row; the line is zero past maxAgeID (SQL: NULL turned into 0)
  spread = tail %>%
    tidyr::crossing(age = 30:70) %>%
    mutate(ageID = as.integer(age),
           frac = ifelse(ageID <= maxAgeID, new30 / (30 - (maxAgeID + 1)) * (ageID - 30) + new30, 0)) %>%
    mutate(ageID = pmin(ageID, 40L)) %>%                      # ages above 40 are summed into 40
    group_by(geoid, year, sourceTypeID, ageID) %>%
    summarise(ageFraction = sum(frac), .groups = "drop")
  bind_rows(keep %>% select(geoid, year, sourceTypeID, ageID, ageFraction), spread) %>%
    arrange(geoid, year, sourceTypeID, ageID)
}

# build_ages_reference(): inputs is a data frame countyID, yearID, sourceTypeID, ageID, ageFraction;
# national is the default table. Returns geoid, year, sourceTypeID, ageID 0 to 40, ageFraction.
build_ages_reference = function(inputs, national){
  x = inputs %>% transmute(geoid = sprintf("%05d", as.integer(countyID)), year = as.integer(yearID),
                           sourceTypeID = as.integer(sourceTypeID), ageID = as.integer(ageID), ageFraction)
  if(anyDuplicated(x[, c("geoid", "year", "sourceTypeID", "ageID")]) > 0){ stop("duplicate county-year-type-age rows in the inputs") }
  # negative shares (EPA's data has some, e.g. type 54 in 13 Ohio counties): record, set to 0; a type with no
  # positive share left takes the national table for the year (applied after the conversion, below)
  negatives = x %>% filter(ageFraction < 0) %>% group_by(geoid, year, sourceTypeID) %>%
    summarise(ages = paste(sort(ageID), collapse = " "), negative_sum = sum(ageFraction), .groups = "drop")
  x = x %>% mutate(ageFraction = pmax(ageFraction, 0))
  all_zero = x %>% group_by(geoid, year, sourceTypeID) %>% summarise(s = sum(ageFraction), .groups = "drop") %>%
    filter(s <= 0) %>% select(geoid, year, sourceTypeID)
  # per county-year table: ages to 30 are converted, ages to 40 are used as given
  top =x %>% group_by(geoid, year) %>% summarise(top = max(ageID), .groups = "drop")
  if(any(!top$top %in% c(30L, 40L))){ stop("a county table has a top age that is neither 30 nor 40") }
  old = x %>% inner_join(top %>% filter(top == 30L) %>% select(geoid, year), by = c("geoid", "year"))
  new = x %>% inner_join(top %>% filter(top == 40L) %>% select(geoid, year), by = c("geoid", "year"))
  out = bind_rows(if(nrow(old) > 0) convert_ages_30_to_40(old), new)
  # long-haul types: national default for the year
  nat = national %>% transmute(year = as.integer(yearID), sourceTypeID = as.integer(sourceTypeID),
                               ageID = as.integer(ageID), nat = ageFraction)
  yrs = unique(out$year)
  if(any(!yrs %in% nat$year)){ stop("national table lacks a year present in the inputs") }
  nat_lh = nat %>% filter(sourceTypeID %in% long_haul)
  lh = out %>% distinct(geoid, year) %>% inner_join(nat_lh, by = "year", relationship = "many-to-many") %>%
    transmute(geoid, year, sourceTypeID, ageID, ageFraction = nat)
  # types with no positive share after the clamp: national table for the year
  az = all_zero %>% filter(!sourceTypeID %in% long_haul) %>%
    inner_join(nat, by = c("year", "sourceTypeID"), relationship = "many-to-many") %>%
    transmute(geoid, year, sourceTypeID, ageID, ageFraction = nat)
  out = bind_rows(out %>% filter(!sourceTypeID %in% long_haul) %>%
                    anti_join(az %>% distinct(geoid, year, sourceTypeID), by = c("geoid", "year", "sourceTypeID")), az, lh)
  # renormalise each county-year-type to sum to exactly 1; every type must have ages 0 to 40
  out = out %>% group_by(geoid, year, sourceTypeID) %>%
    mutate(n_ages = n(), ageFraction = ageFraction / sum(ageFraction)) %>% ungroup()
  if(any(out$n_ages != 41L)){ stop("a county-year-type does not have 41 ages") }
  types = out %>% group_by(geoid, year) %>% summarise(n = n_distinct(sourceTypeID), .groups = "drop")
  if(any(types$n != 13L)){ stop("a county-year does not have all 13 vehicle types") }
  out = out %>% select(geoid, year, sourceTypeID, ageID, ageFraction) %>% arrange(geoid, year, sourceTypeID, ageID)
  attr(out, "negatives") = as.data.frame(negatives)
  out
}

read_age_inputs = function(paths){
  files = unlist(lapply(paths, function(p){
    if(dir.exists(p)){ list.files(p, pattern = "\\.csv(\\.gz)?$", full.names = TRUE) } else { p }
  }))
  if(length(files) == 0){ stop("no input files found") }
  bind_rows(lapply(files, read_csv, col_types = "ciiid", progress = FALSE))
}

main = function(args){
  grab = function(flag){
    i = match(flag, args); if(is.na(i)){ return(character(0)) }
    rest = args[-seq_len(i)]; stop_at = which(startsWith(rest, "--"))
    if(length(stop_at) > 0){ rest = rest[seq_len(stop_at[1] - 1)] }; rest
  }
  paths = grab("--in"); nat = grab("--national"); out = grab("--out")
  if(length(paths) == 0 || length(nat) != 1 || length(out) != 1){ stop("usage: --in <paths...> --national <csv> --out <file.rds>") }
  t0 = Sys.time()
  res = build_ages_reference(read_age_inputs(paths), read_csv(nat, col_types = "iiid", progress = FALSE))
  neg = attr(res, "negatives"); attr(res, "negatives") = NULL
  saveRDS(res, file = out)
  write_csv(neg %>% transmute(geoid, year, sourceTypeID, ages, negative_sum), paste0(out, ".negatives.csv"))
  for(y in sort(unique(res$year))){
    ny = neg %>% filter(year == y)
    cat(sprintf("%d: negative shares set to 0: %d counties, types %s\n", y, n_distinct(ny$geoid),
                if(nrow(ny) == 0) "none" else paste(sort(unique(ny$sourceTypeID)), collapse = "/")))
  }
  cat(sprintf("rows %d, counties %d, years %s, size %.2f MB, %.0f s\n", nrow(res), n_distinct(res$geoid),
              paste(sort(unique(res$year)), collapse = "/"), file.size(out) / 1e6,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

# Runs only when asked on the command line (so the test can source this file for the functions)
if(!interactive() && "--out" %in% commandArgs(trailingOnly = TRUE)){ main(commandArgs(trailingOnly = TRUE)) }
