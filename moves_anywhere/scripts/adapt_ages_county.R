# adapt_ages_county.R #########################################################
#
# What:      county vehicle ages from EPA's NEI tables, for runs that ask for them
# Does:      Reads the setting AGE_SOURCE (environment) or "age_source" (inputs/parameters.json):
#            "national" (the default: the national table, exactly as before) or "county". With
#            "county", looks the run's county up in reference/nei_sourcetypeagedistribution.rds
#            (EPA's 2020 and 2023 NEI county age tables, ages 0 to 40). In 2020 or 2023 the county's
#            own rows are used. In any other year the national table for the run year is multiplied,
#            age by age, by the county-to-national ratio of the nearest inventory year (between 2020
#            and 2023 the two ratios are interpolated linearly), each ratio capped to 0.25 to 4, and
#            renormalised to 1 per vehicle type. Long-haul types 53 and 62 always keep the national
#            table. A missing file or a county not in it falls back to the national table; the run
#            never fails for that.
# Called by: adapt_sourcetypeagedistribution.R (sourced there), step 6 of launch.sh
# Reads:     inputs/parameters.json if present; scripts/reference/nei_sourcetypeagedistribution.rds
#            (data frame geoid, year, sourceTypeID, ageID, ageFraction)
# Writes:    inputs/_age_source.txt (one line, only when the setting is "county"), and a row in
#            inputs/_project_inputs.csv for project runs (project_note)
# Needs:     dplyr, jsonlite; project_functions.R (is_project, project_note) for project runs
###############################################################################

# 1. The setting ####

#' Which age table the run asked for: "national" (the default) or "county"
#' @param BUCKET inputs folder (may hold parameters.json)
#' @return "national" or "county"; stops on any other value
#' @description The environment variable AGE_SOURCE wins; else "age_source" in parameters.json.
ages_source_mode = function(BUCKET = "inputs"){
  value = Sys.getenv("AGE_SOURCE", unset = "")
  if(trimws(value) == ""){
    path = paste0(BUCKET, "/parameters.json")
    if(file.exists(path)){
      p = jsonlite::fromJSON(path)
      if(!is.null(p$age_source)){ value = as.character(p$age_source)[1] }
    }
  }
  value = tolower(trimws(value))
  if(is.na(value) || value == ""){ return("national") }
  if(!value %in% c("national", "county")){
    stop(paste0("age_source must be national or county (found ", value, ")"))
  }
  value
}

# 2. The note ####

#' Record which age table was used: _age_source.txt (one line) and, for project runs, project_note()
#' @param line one line, for example "ages: NEI 2020 county 36109"
#' @param source "county", "default" or "user" (the project_note source)
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder
ages_source_note = function(line, source, .runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  writeLines(line, paste0(BUCKET, "/_age_source.txt"))
  cat(paste0("\n---sourcetypeagedistribution: ", line, "\n"))
  if(exists("is_project", mode = "function") && exists("project_note", mode = "function")){
    if(isTRUE(is_project(.runspec))){ project_note("vehicle ages source", source, line, BUCKET) }
  }
  invisible(line)
}

# 3. The reference file ####

#' Read the NEI county age reference, or NULL when the file is missing or unreadable
#' @param path path to nei_sourcetypeagedistribution.rds
ages_county_reference = function(path = "scripts/reference/nei_sourcetypeagedistribution.rds"){
  if(!file.exists(path)){ return(NULL) }
  ref = tryCatch(readRDS(path), error = function(e){ NULL })
  if(is.null(ref) || !all(c("geoid", "year", "sourceTypeID", "ageID", "ageFraction") %in% names(ref))){ return(NULL) }
  ref
}

# 4. The year method ####

#' Each vehicle type's county-to-national ratio by age for the run year
#' @param county reference rows for one county (year, sourceTypeID, ageID, ageFraction)
#' @param national national rows (yearID, sourceTypeID, ageID, ageFraction) for the inventory years
#' @param .year run year
#' @param cap lower and upper cap on each ratio
#' @return data frame sourceTypeID, ageID, ratio, and the inventory years used (attribute "years")
ages_county_ratio = function(county, national, .year, cap = c(0.25, 4)){
  years = sort(unique(county$year))
  years = years[years %in% unique(national$yearID)]
  if(length(years) == 0){ return(NULL) }
  # The inventory years that frame the run year: one (nearest) outside them, two between them
  lo = years[years <= .year]; hi = years[years >= .year]
  if(length(lo) > 0 && length(hi) > 0){ use = unique(c(max(lo), min(hi))) }
  else{ use = years[which.min(abs(years - .year))] }
  one = function(t){
    c_t = county %>% filter(year == t) %>% select(sourceTypeID, ageID, county = ageFraction)
    n_t = national %>% filter(yearID == t) %>% select(sourceTypeID, ageID, national = ageFraction)
    inner_join(by = c("sourceTypeID", "ageID"), x = n_t, y = c_t) %>%
      # A zero national share carries no information: ratio 1
      mutate(ratio = ifelse(national > 0, county / national, 1), year = t) %>%
      select(sourceTypeID, ageID, year, ratio)
  }
  r = bind_rows(lapply(use, one))
  if(length(use) == 2){
    w = (.year - use[1]) / (use[2] - use[1])
    r = r %>%
      group_by(sourceTypeID, ageID) %>%
      filter(n() == 2) %>%
      summarize(ratio = (1 - w) * ratio[year == use[1]] + w * ratio[year == use[2]], .groups = "drop")
  }else{
    r = r %>% select(sourceTypeID, ageID, ratio)
  }
  r = r %>% mutate(ratio = pmin(pmax(ratio, cap[1]), cap[2]))
  attr(r, "years") = use
  r
}

#' The county age table for the run year, in the national table's columns and row order
#' @param national national rows for the run year AND the inventory years (2020, 2023), columns
#'   sourceTypeID, yearID, ageID, ageFraction (other columns are kept as they are)
#' @param reference the reference data frame (geoid, year, sourceTypeID, ageID, ageFraction)
#' @param .geoidchar 5-character county code
#' @param .year run year
#' @param national_types vehicle types that always keep the national table (long-haul 53, 62)
#' @return list(data = rows for the run year only, line = the note, used = TRUE if county rows were used)
ages_county_table = function(national, reference, .geoidchar, .year, national_types = c(53, 62)){
  base = national %>% filter(yearID == .year)
  fallback = function(why){ list(data = base, used = FALSE,
    line = paste0("ages: national default (age_source county asked for, but ", why, ")")) }
  if(is.null(reference)){ return(fallback("the NEI reference file is missing")) }
  county = reference %>%
    filter(as.character(geoid) == .geoidchar, !sourceTypeID %in% national_types) %>%
    select(year, sourceTypeID, ageID, ageFraction)
  if(nrow(county) == 0){ return(fallback(paste0("county ", .geoidchar, " is not in the NEI reference file"))) }

  if(.year %in% county$year){
    # An inventory year: the county's own rows
    add = county %>% filter(year == .year) %>% select(sourceTypeID, ageID, county = ageFraction)
    how = paste0("ages: NEI ", .year, " county ", .geoidchar, " (EPA county table for ", .year,
                 "); long-haul 53 and 62 national")
  }else{
    r = ages_county_ratio(county, national, .year)
    if(is.null(r) || nrow(r) == 0){ return(fallback(paste0("no national table for the NEI years ", paste(sort(unique(county$year)), collapse = " and ")))) }
    years = attr(r, "years")
    add = base %>%
      select(sourceTypeID, ageID, national = ageFraction) %>%
      inner_join(by = c("sourceTypeID", "ageID"), y = r) %>%
      mutate(county = national * ratio) %>%
      group_by(sourceTypeID) %>%
      filter(sum(county) > 0) %>%
      mutate(county = county / sum(county)) %>%
      ungroup() %>%
      select(sourceTypeID, ageID, county)
    far = min(abs(.year - c(2020, 2023))) > 10
    how = paste0("ages: NEI county ", .geoidchar, ", national ", .year, " x county-to-national ratio of ",
                 paste(years, collapse = " and "), if(length(years) == 2){ " (interpolated)" }else{ "" },
                 ", capped 0.25 to 4; long-haul 53 and 62 national",
                 if(far){ "; more than 10 years from the NEI years, the county tilt is an assumption" }else{ "" })
  }
  # Replace whole vehicle types only: a type the county table lacks keeps the national rows
  types = unique(add$sourceTypeID)
  out = base %>%
    left_join(by = c("sourceTypeID", "ageID"), y = add) %>%
    group_by(sourceTypeID) %>%
    mutate(ageFraction = if(sourceTypeID[1] %in% types){ ifelse(is.na(county), 0, county) }else{ ageFraction }) %>%
    ungroup() %>%
    select(-county)
  list(data = out, used = TRUE, line = how)
}
