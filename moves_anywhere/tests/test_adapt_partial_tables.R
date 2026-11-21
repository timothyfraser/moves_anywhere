# test_adapt_partial_tables.R #################################################
#
# What:      Offline test of the size-safe tally comparison in adapt_avft (scripts/adapt_fuel.R) and
#            adapt_sourcetypeagedistribution (scripts/adapt_sourcetypeagedistribution.R).
# Does:      A complete user table takes the "same" path (no default table is read) and the written
#            file equals the input rows; a user table for vehicle types 21 and 62 only no longer errors
#            and goes through the fill branch: avft keeps the user's rows, adds 0 for a missing stratum
#            of a supplied type and the default fractions for types not supplied at all; ages keep the
#            user's shares for 21 and 62 (to 1e-9) and the national default for the other types
#            (to 1e-12, summing to 1, no NA). The default tables come from a small SQLite database
#            standing in for MariaDB.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_adapt_partial_tables.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml (year 2022, county 36109)
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(DBI); library(RSQLite); library(dbplyr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/adapt_fuel.R")
source("moves_anywhere/scripts/adapt_sourcetypeagedistribution.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
near = function(a, b){ length(a) == length(b) && all(abs(a - b) < 1e-9) }
msg = function(expr){ tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) }) }

root = getwd()
runspec = normalizePath("moves_anywhere/inputs_project/rs_custom.xml")
year = 2022
types = c(11, 21, 31, 32, 41, 42, 43, 51, 52, 53, 54, 61, 62)
avft_n = c(111, 444, 444, 444, 555, 555, 555, 555, 555, 555, 555, 555, 444)

# Default tables, in SQLite, read through the adapters' own connect()/tbl() calls
db = tempfile("defaults_", fileext = ".sqlite")
svp = bind_rows(lapply(seq_along(types), function(i){
  data.frame(sourceTypeID = types[i], modelYearID = 1990 + seq_len(3), fuelTypeID = 1, engTechID = 1,
             regClassID = 30, stmyFraction = 0.5)
}),
  # A stratum of type 21 that the user's partial table does not have: must get 0
  data.frame(sourceTypeID = 21, modelYearID = 1991, fuelTypeID = 9, engTechID = 1, regClassID = 30, stmyFraction = 0.3))
default_ages = expand.grid(sourceTypeID = types, ageID = 0:40) %>%
  mutate(yearID = year, ageFraction = (ageID + 1) / sum(1:41)) %>%
  select(sourceTypeID, yearID, ageID, ageFraction)
con = dbConnect(SQLite(), db)
dbWriteTable(con, "samplevehiclepopulation", svp)
dbWriteTable(con, "sourcetypeagedistribution", default_ages)
dbDisconnect(con)

reads = 0
connect = function(type, dbname){ reads <<- reads + 1; dbConnect(SQLite(), db) }

made = character(0)
run_in = function(file, data, fun){
  d = tempfile("partial_"); dir.create(file.path(d, "inputs"), recursive = TRUE); made <<- c(made, d)
  write_csv(data, file.path(d, "inputs", file))
  reads <<- 0
  setwd(d); on.exit(setwd(root))
  m = msg(capture.output(fun(.runspec = runspec)))
  out = if(file.exists(file.path(d, "inputs", paste0("_", file)))){
    read_csv(file.path(d, "inputs", paste0("_", file)), show_col_types = FALSE) } else { NULL }
  list(msg = m, out = out, reads = reads)
}

# 1. avft, complete: the "same" path, output equals input ####
avft_full = bind_rows(lapply(seq_along(types), function(i){
  data.frame(sourceTypeID = types[i], modelYearID = 1950 + seq_len(avft_n[i]) %/% 4,
             fuelTypeID = 1 + seq_len(avft_n[i]) %% 4, engTechID = 1, fuelEngFraction = 0.25)
}))
r = run_in("avft.csv", avft_full, adapt_avft)
check(r$msg == "no error", paste("avft complete errors:", r$msg))
check(r$reads == 0, "avft complete read the default table (took the fill path)")
check(isTRUE(all.equal(as.data.frame(r$out), avft_full, check.attributes = FALSE)), "avft complete: written file differs from input")

# 2. avft, types 21 and 62 only: no error; user's rows unchanged; 0 elsewhere ####
avft_part = avft_full %>% filter(sourceTypeID %in% c(21, 62))
r = run_in("avft.csv", avft_part, adapt_avft)
check(r$msg == "no error", paste("avft partial errors:", r$msg))
check(r$reads == 1, "avft partial did not read the default table")
if(!is.null(r$out)){
  mine = r$out %>% semi_join(avft_part, by = c("sourceTypeID", "modelYearID", "fuelTypeID", "engTechID"))
  check(nrow(mine) == nrow(avft_part) && near(mine$fuelEngFraction, rep(0.25, nrow(avft_part))), "avft partial: user rows changed")
  added = r$out %>% anti_join(avft_part, by = c("sourceTypeID", "modelYearID", "fuelTypeID", "engTechID"))
  inside = added %>% filter(sourceTypeID %in% c(21, 62))
  check(nrow(inside) == 1 && inside$fuelTypeID == 9 && inside$fuelEngFraction == 0,
        "avft partial: missing stratum inside a user type not added with 0")
  others = added %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, modelYearID)
  want = svp %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, modelYearID)
  check(nrow(others) == nrow(want) && near(others$fuelEngFraction, want$stmyFraction),
        "avft partial: other types do not equal the default fractions")
  check(setequal(unique(r$out$sourceTypeID), types), "avft partial: not every vehicle type present")
  check(!anyNA(r$out), "avft partial: NA in output")
}

# 3. ages, complete: the "same" path, output equals input ####
ages_full = expand.grid(sourceTypeID = types, ageID = 0:40) %>%
  mutate(yearID = year, ageFraction = 1 / 41) %>%
  select(sourceTypeID, yearID, ageID, ageFraction) %>% arrange(sourceTypeID, ageID)
r = run_in("sourcetypeagedistribution.csv", ages_full, adapt_sourcetypeagedistribution)
check(r$msg == "no error", paste("ages complete errors:", r$msg))
check(r$reads == 0, "ages complete read the default table (took the fill path)")
check(isTRUE(all.equal(as.data.frame(r$out), ages_full, check.attributes = FALSE)), "ages complete: written file differs from input")

# 4. ages, types 21 and 62 only: no error; 21 and 62 equal to the user's to 1e-9 ####
ages_part = ages_full %>% filter(sourceTypeID %in% c(21, 62)) %>%
  mutate(ageFraction = ifelse(ageID < 10, 0.06, 0.4 / 31))
r = run_in("sourcetypeagedistribution.csv", ages_part, adapt_sourcetypeagedistribution)
check(r$msg == "no error", paste("ages partial errors:", r$msg))
check(r$reads == 1, "ages partial did not read the default table")
if(!is.null(r$out)){
  mine = r$out %>% filter(sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, ageID)
  check(near(mine$ageFraction, ages_part %>% arrange(sourceTypeID, ageID) %>% pull(ageFraction)), "ages partial: 21 and 62 differ from the user's")
  check(setequal(unique(r$out$sourceTypeID), types) && nrow(r$out) == 13 * 41, "ages partial: not 13 types x 41 ages")
  # A vehicle type with no user rows takes the national default for that type, unchanged
  other = r$out %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, ageID)
  want = default_ages %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, ageID)
  check(nrow(other) == nrow(want) && all(abs(other$ageFraction - want$ageFraction) < 1e-12),
        "ages partial: other types differ from the default (1e-12)")
  sums = other %>% group_by(sourceTypeID) %>% summarize(s = sum(ageFraction))
  check(near(sums$s, rep(1, 11)), "ages partial: other types do not sum to 1")
  check(!anyNA(r$out), "ages partial: NA in output")
}

unlink(c(made, db), recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n", paste0("  - ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS: test_adapt_partial_tables (avft and ages, complete and partial)\n")
