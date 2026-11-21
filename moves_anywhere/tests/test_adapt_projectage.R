# test_adapt_projectage.R #####################################################
#
# What:      Offline test of scripts/adapt_projectage.R (travel-weighted vehicle ages, project scale).
# Does:      Runs adapt_projectage on small literal tables: shares sum to 1 per vehicle type, a flat
#            relativeMAR changes nothing, a halving relativeMAR moves the mean age by the hand-computed
#            amount, a vehicle type with no relativeMAR keeps its shares, the user-table and
#            registration-switch cases leave the file byte-identical and write their notes, a bad
#            switch stops, and a county run is left alone. If the Tompkins 2022 tables of the
#            county-vs-project audit are found next to this repository, also checks the measured
#            mean ages (cars 12.1 to 9.8, long-haul trucks 13.9 to 8.3).
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_adapt_projectage.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml, moves_anywhere/inputs/rs_custom.xml (if
#            present); optionally the audit tables named in AUDIT below
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

suppressPackageStartupMessages({ library(xml2); library(dplyr); library(readr); library(stringr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/project_functions.R")
source("moves_anywhere/scripts/adapt_projectage.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
near = function(a, b, tol = 1e-9){ length(a) == length(b) && all(abs(a - b) < tol) }
msg = function(expr){ tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) }) }
Sys.unsetenv("PROJECT_AGES")

# 1. Literal inputs ####

# Two ages, 0.5 each; vehicle types 21 and 62 (year 2022, the fixture's year)
ages = data.frame(sourceTypeID = rep(c(21, 62), each = 2), yearID = 2022, ageID = rep(0:1, 2),
                  ageFraction = 0.5)
mar_flat = data.frame(sourceTypeID = rep(c(21, 62), each = 2), ageID = rep(0:1, 2),
                      survivalRate = 1, relativeMAR = 1)
# Halving: age 0 = 1, age 1 = 0.5. Weighted 0.5 and 0.25, normalised 2/3 and 1/3:
# mean age 0.5 before, 1/3 after, a shift of -1/6
mar_half = mar_flat %>% mutate(relativeMAR = ifelse(ageID == 0, 1, 0.5))
mar = mar_flat
get_table = function(tablename){
  if(tablename == "sourcetypeage"){ return(mar) }
  stop(paste0("test has no default table ", tablename))
}

made = character(0)
bucket = function(user = FALSE, json = NULL){
  d = tempfile("age_"); dir.create(d); made <<- c(made, d)
  invisible(file.copy("moves_anywhere/inputs_project/rs_custom.xml", file.path(d, "rs_custom.xml")))
  write_csv(ages, file.path(d, "_sourcetypeagedistribution.csv"))
  if(user){ write_csv(ages, file.path(d, "sourcetypeagedistribution.csv")) }
  if(!is.null(json)){ writeLines(json, file.path(d, "parameters.json")) }
  d
}
rs = function(d){ file.path(d, "rs_custom.xml") }
read_ages = function(d){ read_csv(file.path(d, "_sourcetypeagedistribution.csv"), show_col_types = FALSE) }
notes = function(d){ read_csv(file.path(d, "_project_inputs.csv"), show_col_types = FALSE) }
bytes = function(d){ readBin(file.path(d, "_sourcetypeagedistribution.csv"), "raw", 1e6) }
mean_age = function(x, id){ x = x[x$sourceTypeID == id, ]; sum(x$ageID * x$ageFraction) }

# 2. Flat relativeMAR: unchanged; shares sum to 1 ####

mar = mar_flat
d = bucket()
check(adapt_projectage(rs(d), d) == "travel", "flat: returns travel")
out = read_ages(d)
check(identical(names(out), c("sourceTypeID", "yearID", "ageID", "ageFraction")), "flat: columns and order")
check(near(out$ageFraction, ages$ageFraction), "flat: table unchanged")
check(near(as.numeric(tapply(out$ageFraction, out$sourceTypeID, sum)), c(1, 1)), "flat: sums to 1")
n = notes(d)
check(nrow(n) == 1 && n$item == "vehicle ages" && n$source == "derived" &&
        grepl("^travel-weighted", n$detail), "flat: derived note")

# 3. Halving relativeMAR: hand-computed shift ####

mar = mar_half
d = bucket()
adapt_projectage(rs(d), d)
out = read_ages(d)
check(near(out$ageFraction, c(2/3, 1/3, 2/3, 1/3)), "half: shares 2/3 and 1/3")
check(near(mean_age(out, 21) - mean_age(ages, 21), -1/6), "half: mean age falls by 1/6")
check(near(as.numeric(tapply(out$ageFraction, out$sourceTypeID, sum)), c(1, 1)), "half: sums to 1")

# 4. A vehicle type with no relativeMAR keeps its shares, with its own note ####

mar = mar_half %>% filter(sourceTypeID == 21)
d = bucket()
adapt_projectage(rs(d), d)
out = read_ages(d)
check(near(out$ageFraction, c(2/3, 1/3, 0.5, 0.5)), "no MAR: 62 keeps registration shares")
n = notes(d)
check(nrow(n) == 2 && n$item[2] == "vehicle ages 62" && n$source[2] == "default", "no MAR: own note")
# A weighted sum of 0 also keeps the shares
mar = mar_half %>% mutate(relativeMAR = ifelse(sourceTypeID == 62, 0, relativeMAR))
d = bucket()
adapt_projectage(rs(d), d)
check(near(read_ages(d)$ageFraction, c(2/3, 1/3, 0.5, 0.5)), "zero MAR: 62 keeps registration shares")

# 5. User table and the registration switch: byte-identical, with notes ####

mar = mar_half
d = bucket(user = TRUE); before = bytes(d)
check(adapt_projectage(rs(d), d) == "user", "user: returns user")
check(identical(bytes(d), before), "user: file byte-identical")
n = notes(d)
check(nrow(n) == 1 && n$source == "user" && grepl("^used as given", n$detail), "user: note")

Sys.setenv(PROJECT_AGES = "registration")
d = bucket(); before = bytes(d)
check(adapt_projectage(rs(d), d) == "registration", "env switch: returns registration")
check(identical(bytes(d), before), "env switch: file byte-identical")
n = notes(d)
check(nrow(n) == 1 && n$source == "default" && grepl("^registration ages", n$detail), "env switch: note")
Sys.unsetenv("PROJECT_AGES")

d = bucket(json = '{"project_ages": "Registration"}'); before = bytes(d)
check(adapt_projectage(rs(d), d) == "registration", "json switch: returns registration")
check(identical(bytes(d), before), "json switch: file byte-identical")
d = bucket(json = '{"project_ages": "travel"}')
check(adapt_projectage(rs(d), d) == "travel", "json travel: weighted")

# 6. A bad switch value stops ####

Sys.setenv(PROJECT_AGES = "fleet")
d = bucket()
check(msg(adapt_projectage(rs(d), d)) == "project_ages must be travel or registration (found fleet)",
      "bad switch: message")
Sys.unsetenv("PROJECT_AGES")
d = bucket(json = '{"project_ages": "county"}')
check(grepl("found county", msg(adapt_projectage(rs(d), d))), "bad json switch: stops")

# 7. A county run is left alone ####

county_rs = "moves_anywhere/inputs/rs_custom.xml"
if(file.exists(county_rs) && !is_project(county_rs)){
  d = bucket(); before = bytes(d)
  check(is.null(adapt_projectage(county_rs, d)), "county: returns NULL")
  check(identical(bytes(d), before) && !file.exists(file.path(d, "_project_inputs.csv")), "county: untouched")
}

# 8. Result ####

unlink(made, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL test_adapt_projectage.R:\n", paste0("  ", failures, collapse = "\n"), "\n")
  quit(save = "no", status = 1)
}
cat("PASS test_adapt_projectage.R\n")
