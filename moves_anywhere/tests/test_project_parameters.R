# test_project_parameters.R ###################################################
#
# What:      Offline test of scripts/project_parameters.R (the one settings file of a project run).
# Does:      Writes small parameters.json files to temporary folders and checks: each required key
#            missing, each bad value, day words, geoid as a number, unknown keys ignored, a county file
#            and no file return NULL, the state lookup, and the agreement check against the project
#            fixture's run file (Tompkins 36109, 2022, month 7, day 5, hour 8): a pass and each mismatch.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from moves_anywhere/ or the repository root: Rscript tests/test_project_parameters.R
# Reads:     inputs_project/rs_custom.xml, inputs_ny/parameters.json
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

if(dir.exists("moves_anywhere/scripts")){ setwd("moves_anywhere") }
suppressPackageStartupMessages({ library(jsonlite); library(xml2) })
PROJECT_PARAMETERS_TEST = TRUE
source("scripts/project_functions.R")
source("scripts/project_parameters.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
msg = function(expr){ tryCatch({ suppressMessages(expr); "no error" }, error = function(e){ conditionMessage(e) }) }
made = character(0)
folder = function(x){
  d = tempfile("pp_"); dir.create(d); made <<- c(made, d)
  if(!is.null(x)){ writeLines(if(is.character(x)) x else toJSON(x, auto_unbox = TRUE), file.path(d, "parameters.json")) }
  d
}
good = list(level = "project", geoid = "36109", year = 2022, month = 7, day = "weekday", hour = 8)
with_ = function(...){ x = good; v = list(...); for(k in names(v)){ x[k] = list(v[[k]]) }; x }
read = function(x){ suppressMessages(project_params(folder(x))) }

# 1. A good file ####
p = read(good)
check(identical(p$geoid, "36109") && p$year == 2022L && p$month == 7L && p$day == 5L && p$hour == 8L, "good file values")
check(is.integer(p$year) && is.integer(p$day), "integers")
check(identical(p$pollutant, PROJECT_POLLUTANTS), "default pollutants")
check(is.null(p$roadtypes) && is.null(p$place) && is.null(p$max_links), "optional keys default to NULL")
check(identical(p$state, "NY"), "state from geoid")
check(read(with_(day = "weekend"))$day == 2L, "day weekend")
check(read(with_(day = 2))$day == 2L && read(with_(day = "Weekday"))$day == 5L, "day 2 and Weekday")
check(identical(read(with_(geoid = 6037))$geoid, "06037") && identical(read(with_(geoid = 6037))$state, "CA"), "numeric geoid padded")
check(identical(read(with_(roadtypes = c(5, 4, 4)))$roadtypes, c(4L, 5L)), "roadtypes sorted")
check(identical(read(with_(pollutant = c(2, 3)))$pollutant, c(2L, 3L)), "pollutant list")
check(identical(read(with_(place = "-76.6,42.4,-76.4,42.5"))$place, "-76.6,42.4,-76.4,42.5"), "place box")
check(identical(read(with_(place = "36109", max_links = 25))$max_links, 25L), "place FIPS and max_links")
check(!is.null(read(with_(age_source = "county", project_ages = "registration"))), "age keys accepted")

# 2. Unknown keys are ignored and listed ####
d = folder(with_(dtablename = "d36109_u1_o1", by = 1:3, mode = "inv"))
out = capture.output(p2 <- project_params(d), type = "message")
check(!is.null(p2) && setequal(p2$ignored, c("dtablename", "by", "mode")), "unknown keys ignored")
check(any(grepl("ignored keys: dtablename, by, mode", out)), "ignored keys logged")

# 3. County file, no file, other levels: NULL ####
check(is.null(project_params("inputs_ny")), "county file returns NULL")
check(is.null(project_params(folder(NULL))), "no file returns NULL")
check(is.null(read(with_(level = "county"))), "level county returns NULL")
check(is.null(read(good[-1])), "no level returns NULL")

# 4. Every required key missing ####
for(key in c("geoid", "year", "month", "day", "hour")){
  m = msg(project_params(folder(good[setdiff(names(good), key)])))
  check(grepl(paste0("parameters.json: ", key, " must be given"), m), paste("missing", key, "->", m))
}

# 5. Every bad value ####
bad = list(
  geoid = list("3610", "36109x", 123456, 36109.5, list("36109", "36011"), "99001"),
  year = list(1989, 2061, 2022.5, "twenty"),
  month = list(0, 13, "July", 7.5),
  day = list(1, 3, "monday", 5.5),
  hour = list(0, 25, "8am", 8.5),
  pollutant = list(c(2, -1), "CO", c(2.5)),
  roadtypes = list(c(0, 4), c(6), "arterial"),
  place = list("1,2,3", "-76.4,42.4,-76.6,42.5", "Ithaca", "361090"),
  max_links = list(0, -5, 2.5, "many")
)
for(key in names(bad)){
  for(v in bad[[key]]){
    m = msg(read(do.call(with_, setNames(list(v), key))))
    check(grepl(paste0("parameters.json: ", key, " must be"), m), paste("bad", key, deparse(v), "->", m))
  }
}
check(grepl("not valid JSON", msg(project_params(folder("{ level: project")))), "invalid JSON refused")

# 6. Agreement with a supplied run file ####
rs = "inputs_project/rs_custom.xml"
check(msg(project_params_agree(read(good), rs)) == "no error", "agreement passes on the fixture")
mism = list(geoid = "36011", year = 2023, month = 8, day = "weekend", hour = 9)
for(key in names(mism)){
  m = msg(project_params_agree(read(do.call(with_, setNames(list(mism[[key]]), key))), rs))
  check(grepl(paste0("disagrees on ", key, ":"), m), paste("mismatch", key, "->", m))
}

# 7. Shell lines ####
sh = suppressMessages(project_params_shell(folder(with_(place = "36109", max_links = 10))))
check(all(c("PP_LEVEL='project'", "PP_GEOID='36109'", "PP_STATE='NY'", "PP_PLACE='36109'", "PP_MAX_LINKS='10'") %in% sh), "shell lines")
check(length(project_params_shell("inputs_ny")) == 0, "no shell lines for a county file")
check(length(PROJECT_STATES) == 52, "52 state codes")

unlink(made, recursive = TRUE)
if(length(failures) > 0){ cat("FAIL\n", paste0("  ", failures, collapse = "\n"), "\n"); quit(status = 1) }
cat("PASS test_project_parameters.R\n")
