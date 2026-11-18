# project_parameters.R ########################################################
#
# What:      The settings file of a project-scale run: <BUCKET>/parameters.json with "level": "project".
# Does:      project_params reads parameters.json and returns NULL for a county run (no file, or level
#            not "project"); for a project run it checks every key and returns the values normalised
#            (geoid as 5 digits, day as 5 or 2, integers). project_params_agree checks that a supplied
#            rs_custom.xml names the same county, year, month, day type and hour. project_state turns a
#            county FIPS code into its state's two letters (for the link builder). Run as a script it
#            prints the values as shell lines ("env") or runs the agreement check ("agree <runspec>").
# Called by: task_runspec.R (sourced); launch.sh, the project step between steps 1 and 2 (as a script);
#            tests/test_project_parameters.R
# Reads:     <BUCKET>/parameters.json; the run file (project_params_agree, through project_spec)
# Writes:    nothing (prints the ignored keys and, as a script, shell lines or one refusal line)
# Needs:     jsonlite; project_params_agree also needs xml2 and project_functions.R (project_spec)
# Exits:     as a script: 0 ok; 1 and one line "parameters: <reason>" on stderr if a key is refused or
#            the run file disagrees with parameters.json
###############################################################################

# 1. Allowed keys ####

# Keys a project parameters.json may carry; any other key is ignored (county files carry many)
PROJECT_KEYS = c("level", "geoid", "year", "month", "day", "hour", "pollutant", "roadtypes", "place",
                 "max_links", "age_source", "project_ages")
# The pollutants task_runspec.R uses when the file names none
PROJECT_POLLUTANTS = c(98L, 3L, 2L, 31L, 33L, 110L, 100L, 106L, 107L, 116L, 117L)

# State FIPS code (first two digits of a county FIPS) to postal code: 50 states, DC and PR
PROJECT_STATES = c(
  "01" = "AL", "02" = "AK", "04" = "AZ", "05" = "AR", "06" = "CA", "08" = "CO", "09" = "CT", "10" = "DE",
  "11" = "DC", "12" = "FL", "13" = "GA", "15" = "HI", "16" = "ID", "17" = "IL", "18" = "IN", "19" = "IA",
  "20" = "KS", "21" = "KY", "22" = "LA", "23" = "ME", "24" = "MD", "25" = "MA", "26" = "MI", "27" = "MN",
  "28" = "MS", "29" = "MO", "30" = "MT", "31" = "NE", "32" = "NV", "33" = "NH", "34" = "NJ", "35" = "NM",
  "36" = "NY", "37" = "NC", "38" = "ND", "39" = "OH", "40" = "OK", "41" = "OR", "42" = "PA", "44" = "RI",
  "45" = "SC", "46" = "SD", "47" = "TN", "48" = "TX", "49" = "UT", "50" = "VT", "51" = "VA", "53" = "WA",
  "54" = "WV", "55" = "WI", "56" = "WY", "72" = "PR"
)

# 2. Helpers ####

#' Stop with one line naming the key and its allowed values
#' @param key the key
#' @param allowed what the key may hold
project_refuse = function(key, allowed){
  stop(paste0("parameters.json: ", key, " must be ", allowed), call. = FALSE)
}

#' One whole number from a JSON value (number or digit string), or NA
#' @param v the value
project_int = function(v){
  if(is.null(v) || length(v) != 1 || is.na(v)){ return(NA_integer_) }
  if(is.character(v)){
    v = trimws(v)
    if(!grepl("^-?[0-9]+$", v)){ return(NA_integer_) }
    return(suppressWarnings(as.integer(v)))
  }
  if(is.numeric(v) && v == round(v) && abs(v) < .Machine$integer.max){ return(as.integer(v)) }
  NA_integer_
}

#' A list of whole numbers from a JSON value, or NULL if any element is not one
#' @param v the value
project_ints = function(v){
  if(is.null(v) || length(v) == 0){ return(NULL) }
  out = vapply(as.list(unlist(v)), project_int, integer(1))
  if(anyNA(out)){ return(NULL) }
  out
}

#' The state's two letters for a county FIPS code
#' @param geoid 5-digit county FIPS code (string)
project_state = function(geoid){
  code = PROJECT_STATES[substr(sprintf("%05s", geoid), 1, 2)]
  if(is.na(code)){ project_refuse("geoid", "a county FIPS code in one of the 50 states, DC or PR") }
  unname(code)
}

# 3. Read and check ####

#' The settings of a project run, or NULL for a county run
#' @param BUCKET folder that holds parameters.json
#' @return NULL, or a list: level, geoid (5-digit string), year, month, day (5 or 2), hour, pollutant,
#'   roadtypes (NULL = from link.csv), place (NULL or string), max_links (NULL or integer), state,
#'   age_source, project_ages, ignored (names of ignored keys)
project_params = function(BUCKET = "inputs"){
  path = file.path(BUCKET, "parameters.json")
  if(!file.exists(path)){ return(NULL) }
  p = tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE),
               error = function(e){ stop("parameters.json: not valid JSON (", conditionMessage(e), ")", call. = FALSE) })
  if(!is.list(p)){ return(NULL) }
  level = p$level
  if(is.null(level) || length(level) != 1 || !is.character(level) || tolower(trimws(level)) != "project"){ return(NULL) }

  ignored = setdiff(names(p), PROJECT_KEYS)
  if(length(ignored) > 0){ message("parameters.json: ignored keys: ", paste(ignored, collapse = ", ")) }

  # Required keys
  for(key in c("geoid", "year", "month", "day", "hour")){
    if(is.null(p[[key]])){
      allowed = switch(key, geoid = "a 5-digit county FIPS code", year = "a year from 1990 to 2060",
                       month = "a month from 1 to 12", day = "\"weekday\", \"weekend\", 5 or 2",
                       hour = "an hour from 1 to 24 (8 is 7:00 to 7:59)")
      project_refuse(key, paste0("given for a project run: ", allowed))
    }
  }

  # geoid: string of 5 digits, or a number (leading zero restored)
  g = p$geoid
  geoid = NA_character_
  if(length(g) == 1 && is.character(g) && grepl("^[0-9]{5}$", trimws(g))){ geoid = trimws(g) }
  if(length(g) == 1 && is.numeric(g) && !is.na(project_int(g)) && g >= 1000 && g <= 99999){ geoid = sprintf("%05d", project_int(g)) }
  if(is.na(geoid)){ project_refuse("geoid", "a 5-digit county FIPS code, e.g. \"36109\"") }
  state = project_state(geoid)

  year = project_int(p$year)
  if(is.na(year) || year < 1990 || year > 2060){ project_refuse("year", "a year from 1990 to 2060") }
  month = project_int(p$month)
  if(is.na(month) || !month %in% 1:12){ project_refuse("month", "a month from 1 to 12") }
  hour = project_int(p$hour)
  if(is.na(hour) || !hour %in% 1:24){ project_refuse("hour", "an hour from 1 to 24 (8 is 7:00 to 7:59)") }

  d = p$day
  day = NA_integer_
  if(length(d) == 1 && is.character(d) && tolower(trimws(d)) %in% c("weekday", "weekend")){
    day = if(tolower(trimws(d)) == "weekday") 5L else 2L
  }else{
    day = project_int(d)
  }
  if(is.na(day) || !day %in% c(2L, 5L)){ project_refuse("day", "\"weekday\", \"weekend\", 5 or 2") }

  # Optional keys
  pollutant = PROJECT_POLLUTANTS
  if(!is.null(p$pollutant)){
    pollutant = project_ints(p$pollutant)
    if(is.null(pollutant) || any(pollutant < 1)){ project_refuse("pollutant", "a list of MOVES pollutant IDs (positive whole numbers)") }
    pollutant = unique(pollutant)
  }

  roadtypes = NULL
  if(!is.null(p$roadtypes)){
    roadtypes = project_ints(p$roadtypes)
    if(is.null(roadtypes) || !all(roadtypes %in% 1:5)){ project_refuse("roadtypes", "a list of road types from 1 to 5") }
    roadtypes = sort(unique(roadtypes))
  }

  place = NULL
  if(!is.null(p$place)){
    pl = p$place
    box = "^ *-?[0-9.]+ *, *-?[0-9.]+ *, *-?[0-9.]+ *, *-?[0-9.]+ *$"
    ok = length(pl) == 1 && is.character(pl) && (grepl("^[0-9]{5}$", trimws(pl)) || grepl(box, pl))
    if(ok && grepl(box, pl)){
      v = suppressWarnings(as.numeric(strsplit(pl, ",")[[1]]))
      ok = !anyNA(v) && v[1] < v[3] && v[2] < v[4] && all(abs(v[c(1, 3)]) <= 180) && all(abs(v[c(2, 4)]) <= 90)
    }
    if(!ok){ project_refuse("place", "a box \"west,south,east,north\" (degrees, west < east, south < north) or a 5-digit county FIPS code") }
    place = gsub(" ", "", trimws(pl))
  }

  max_links = NULL
  if(!is.null(p$max_links)){
    max_links = project_int(p$max_links)
    if(is.na(max_links) || max_links < 1){ project_refuse("max_links", "a positive whole number") }
  }

  list(level = "project", geoid = geoid, year = year, month = month, day = day, hour = hour,
       pollutant = pollutant, roadtypes = roadtypes, place = place, max_links = max_links, state = state,
       age_source = p$age_source, project_ages = p$project_ages, ignored = ignored)
}

#' Stop unless a supplied run file names the county, year, month, day type and hour of parameters.json
#' @param params the list from project_params()
#' @param runspec path to the supplied rs_custom.xml
#' @return TRUE (invisibly) when they agree; otherwise stops with one line naming the first mismatch
project_params_agree = function(params, runspec){
  spec = project_spec(runspec)
  pairs = list(
    geoid = list(spec$geoid, as.integer(params$geoid)),
    year = list(spec$year, params$year),
    month = list(spec$month, params$month),
    day = list(spec$day, params$day),
    hour = list(unique(c(spec$beginhour, spec$endhour)), params$hour)
  )
  for(key in names(pairs)){
    run = pairs[[key]][[1]]
    want = pairs[[key]][[2]]
    if(length(run) != 1 || is.na(run) || run != want){
      shown = if(length(run) == 0) "none" else paste(run, collapse = ",")
      stop(paste0("parameters.json: rs_custom.xml disagrees on ", key, ": run file ", shown,
                  ", parameters.json ", want), call. = FALSE)
    }
  }
  invisible(TRUE)
}

#' Shell lines (KEY='value') for launch.sh, or nothing for a county run
#' @param BUCKET folder that holds parameters.json
project_params_shell = function(BUCKET = "inputs"){
  p = project_params(BUCKET)
  if(is.null(p)){ return(character(0)) }
  q = function(x){ if(is.null(x)) "''" else shQuote(paste(x, collapse = ","), type = "sh") }
  c(paste0("PP_LEVEL=", q(p$level)), paste0("PP_GEOID=", q(p$geoid)), paste0("PP_YEAR=", q(p$year)),
    paste0("PP_STATE=", q(p$state)), paste0("PP_PLACE=", q(p$place)), paste0("PP_MAX_LINKS=", q(p$max_links)),
    paste0("PP_ROADTYPES=", q(p$roadtypes)))
}

# 4. Run (only when called as a script) ####

if(sys.nframe() == 0 && !exists("PROJECT_PARAMETERS_TEST")){
  args = commandArgs(trailingOnly = TRUE)
  mode = if(length(args) > 0) args[1] else "env"
  status = tryCatch({
    if(mode == "env"){
      writeLines(project_params_shell("inputs"))
    }else if(mode == "agree"){
      source("scripts/project_functions.R")
      p = project_params("inputs")
      if(!is.null(p)){ project_params_agree(p, if(length(args) > 1) args[2] else "inputs/rs_custom.xml") }
    }else{
      stop("parameters: unknown mode ", mode, call. = FALSE)
    }
    0L
  }, error = function(e){
    message(conditionMessage(e))
    1L
  })
  quit(save = "no", status = status)
}
