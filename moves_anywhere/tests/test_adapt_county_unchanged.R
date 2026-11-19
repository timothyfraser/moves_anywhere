# test_adapt_county_unchanged.R ###############################################
#
# What:      Offline test that release 3.2's changes to adapt_avft (scripts/adapt_fuel.R) and
#            adapt_sourcetypeagedistribution (scripts/adapt_sourcetypeagedistribution.R) leave county
#            results unchanged whenever the user's table covers every vehicle type.
# Does:      3.2 changed three expressions (old ones copied below from origin/main, release 3.1.0):
#              1. is_same, both adapters:  all(tallynormal == tally)  became a join by sourceTypeID.
#              2. ages weighting:  ageFraction * (1 - weight)  became
#                 ifelse(weight == 1, ageFraction, ageFraction * (1 - weight)).
#              3. avft fill: vehicle types with no user rows take the default fractions (missingtypes).
#            (a) is_same: the 3.2 lines are read out of each current script and evaluated beside the
#                3.1.0 line on many tallies; wherever 3.1.0 gives an answer, 3.2 gives the same one.
#            (b) The current adapters are run end to end (SQLite standing in for MariaDB) on user tables
#                that cover every vehicle type, both on the "same" path and on the fill path (some ages
#                or strata missing), and their written files are compared, value for value with no
#                tolerance, to the 3.1.0 fill code written out here.
#            (c) A partial table (types 21 and 62 only) documents the intended difference: 3.1.0's
#                is_same errors; and had it got past that, its ages for the missing types are NaN
#                (0/0) and its avft fractions for the missing types are 0, where 3.2 keeps defaults.
# Called by: Developer tool and tests/run_gate.sh (project-unit step). Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_adapt_county_unchanged.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml (year 2022); the two adapter scripts
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(DBI); library(RSQLite); library(dbplyr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/adapt_fuel.R")
source("moves_anywhere/scripts/adapt_sourcetypeagedistribution.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
msg = function(expr){ tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) }) }
# Exact equality of two tables after sorting by their key columns (no tolerance)
same_table = function(a, b, keys){
  a = as.data.frame(a) %>% arrange(across(all_of(keys)))
  b = as.data.frame(b) %>% arrange(across(all_of(keys)))
  nrow(a) == nrow(b) && setequal(names(a), names(b)) &&
    all(vapply(names(a), function(n){ identical(as.numeric(a[[n]]), as.numeric(b[[n]])) }, logical(1)))
}

root = getwd()
runspec = normalizePath("moves_anywhere/inputs_project/rs_custom.xml")
year = 2022
types = c(11, 21, 31, 32, 41, 42, 43, 51, 52, 53, 54, 61, 62)
avft_n = c(111, 444, 444, 444, 555, 555, 555, 555, 555, 555, 555, 555, 444)

# 1. is_same: 3.2 lines from the scripts, 3.1.0 line written out ####
# The 3.2 lines (tallyjoin = ..., is_same = ...) are taken from each script, so editing them fails this test.
new_is_same_lines = function(file){
  l = readLines(file, warn = FALSE)
  j = grep("^\\s*tallyjoin = inner_join\\(", l, value = TRUE)
  s = grep("^\\s*is_same = ", l, value = TRUE)
  check(length(j) == 1 && length(s) == 1, paste("could not find exactly one tallyjoin and is_same line in", file))
  c(j[1], s[1])
}
is_same_new = function(lines, tally, tallynormal){
  e = new.env(); e$tally = tally; e$tallynormal = tallynormal
  for(x in lines){ eval(parse(text = x), envir = e) }
  e$is_same
}
# 3.1.0 (origin/main, both adapters): is_same = all(tallynormal == tally)
is_same_old = function(tally, tallynormal){ all(tallynormal == tally) }

tally_of = function(ids, n){ data.frame(sourceTypeID = rep(ids, n)) %>% group_by(sourceTypeID) %>% count() }
for(file in c("moves_anywhere/scripts/adapt_sourcetypeagedistribution.R", "moves_anywhere/scripts/adapt_fuel.R")){
  lines = new_is_same_lines(file)
  normal_n = if(grepl("fuel", file)){ avft_n } else { rep(41, 13) }
  tallynormal = tibble(sourceTypeID = types, n = normal_n)
  cases = list(
    complete_same   = tally_of(types, normal_n),
    complete_short  = tally_of(types, pmax(normal_n - 5, 1)),
    one_count_off   = tally_of(types, replace(normal_n, 4, normal_n[4] - 1)),
    one_type_extra  = tally_of(types, replace(normal_n, 13, normal_n[13] + 41)),
    wrong_type_id   = tally_of(c(types[-13], 99), normal_n),
    partial_21_62   = tally_of(c(21, 62), normal_n[c(2, 13)]),
    extra_type_99   = tally_of(c(types, 99), c(normal_n, 41))
  )
  for(nm in names(cases)){
    old = tryCatch(is_same_old(cases[[nm]], tallynormal), error = function(e){ NA })
    new = is_same_new(lines, cases[[nm]], tallynormal)
    check(is.logical(new) && length(new) == 1 && !is.na(new), paste(basename(file), nm, ": 3.2 is_same not TRUE/FALSE"))
    # Wherever 3.1.0 gave an answer (complete coverage: same row count), 3.2 must give the same one
    if(!is.na(old)){ check(identical(old, new), paste(basename(file), nm, ": 3.1.0 is_same", old, "but 3.2", new)) }
    # Expected answers
    check(identical(new, nm == "complete_same"), paste(basename(file), nm, ": 3.2 is_same is", new))
  }
  # (c) the intended difference: 3.1.0 errors on a partial table, 3.2 says FALSE
  check(is.na(tryCatch(is_same_old(cases$partial_21_62, tallynormal), error = function(e){ NA })),
        paste(basename(file), ": 3.1.0 is_same no longer errors on a partial table (test premise changed)"))
}

# Default tables, in SQLite, read through the adapters' own connect()/tbl() calls ####
db = tempfile("defaults_", fileext = ".sqlite")
svp = bind_rows(lapply(seq_along(types), function(i){
  data.frame(sourceTypeID = types[i], modelYearID = 1990 + seq_len(3), fuelTypeID = 1, engTechID = 1,
             regClassID = 30, stmyFraction = 0.2 + i / 100)
}))
default_ages = expand.grid(sourceTypeID = types, ageID = 0:40) %>%
  mutate(yearID = year, ageFraction = (ageID + 1) / sum(1:41)) %>%
  select(sourceTypeID, yearID, ageID, ageFraction)
con = dbConnect(SQLite(), db)
dbWriteTable(con, "samplevehiclepopulation", svp)
dbWriteTable(con, "sourcetypeagedistribution", default_ages)
dbDisconnect(con)

reads = 0
connect = function(type, dbname){ reads <<- reads + 1; dbConnect(SQLite(), db) }
read_default = function(f){ con = dbConnect(SQLite(), db); on.exit(dbDisconnect(con)); f(con) }

made = character(0)
run_in = function(file, data, fun){
  d = tempfile("unchanged_"); dir.create(file.path(d, "inputs"), recursive = TRUE); made <<- c(made, d)
  write_csv(data, file.path(d, "inputs", file))
  reads <<- 0
  setwd(d); on.exit(setwd(root))
  m = msg(capture.output(fun(.runspec = runspec)))
  out = if(file.exists(file.path(d, "inputs", paste0("_", file)))){
    read_csv(file.path(d, "inputs", paste0("_", file)), show_col_types = FALSE) } else { NULL }
  list(msg = m, out = out, reads = reads)
}
# One csv write-and-read (readr is not always exact to the last bit). The adapter reads the user file
# (one trip) and its output is written and read back here (a second), so the 3.1.0 reference takes the same trips.
roundtrip = function(x){ p = tempfile(fileext = ".csv"); write_csv(x, p); y = read_csv(p, show_col_types = FALSE); unlink(p); y }

# 3.1.0 fill code, copied from origin/main ####
# adapt_sourcetypeagedistribution.R lines 78-147 (the !is_same block), release 3.1.0
ages_fill_old = function(data, fakedata){
  extrarows = fakedata %>%
    select(sourceTypeID, yearID, ageID, ageFraction) %>%
    distinct() %>%
    anti_join(by = c("sourceTypeID", "yearID", "ageID"), x = ., y = data)
  data = bind_rows(data %>% mutate(group = "custom"), extrarows %>% mutate(group = "default")) %>% distinct()
  myweights = data %>%
    group_by(sourceTypeID, yearID) %>%
    summarize(weight = sum(group == "default") / sum(group == "default" | group == "custom"), .groups = "drop")
  data = data %>%
    left_join(by = c("sourceTypeID", "yearID"), y = myweights) %>%
    mutate(ageFraction = ageFraction * (1 - weight)) %>%
    select(-weight, -group)
  data %>% group_by(sourceTypeID, yearID) %>%
    mutate(ageFraction = ageFraction / sum(ageFraction, na.rm = TRUE)) %>% ungroup()
}
# adapt_fuel.R lines 439-470 (the !is_same block), release 3.1.0: no missingtypes block
avft_fill_old = function(data, fakedata){
  extrarows = fakedata %>%
    select(sourceTypeID, modelYearID, fuelTypeID, engTechID) %>%
    distinct() %>%
    anti_join(by = c("sourceTypeID", "modelYearID", "fuelTypeID", "engTechID"), y = data) %>%
    mutate(fuelEngFraction = 0)
  bind_rows(data, extrarows) %>% distinct()
}
fake_ages = function(){ read_default(function(con){ tbl(con, "sourcetypeagedistribution") %>% filter(yearID %in% !!year) %>% collect() }) }
fake_avft = function(){ read_default(function(con){
  tbl(con, "samplevehiclepopulation") %>%
    group_by(sourceTypeID, modelYearID, fuelTypeID, engTechID) %>%
    summarize(fuelEngFraction = sum(stmyFraction, na.rm = TRUE), .groups = "drop") %>% collect() }) }

age_keys = c("sourceTypeID", "yearID", "ageID")
avft_keys = c("sourceTypeID", "modelYearID", "fuelTypeID", "engTechID")

# 2. ages, every type, "same" path: 3.2 output == input == 3.1.0 output ####
set.seed(32)
ages_full = expand.grid(sourceTypeID = types, ageID = 0:40) %>%
  mutate(yearID = year, ageFraction = runif(n())) %>%
  group_by(sourceTypeID) %>% mutate(ageFraction = ageFraction / sum(ageFraction)) %>% ungroup() %>%
  select(sourceTypeID, yearID, ageID, ageFraction) %>% arrange(sourceTypeID, ageID)
r = run_in("sourcetypeagedistribution.csv", ages_full, adapt_sourcetypeagedistribution)
check(r$msg == "no error", paste("ages complete-same errors:", r$msg))
check(r$reads == 0, "ages complete-same took the fill path")
check(!is.null(r$out) && same_table(r$out, roundtrip(roundtrip(ages_full)), age_keys), "ages complete-same: 3.2 output differs from 3.1.0 (the input)")

# 3. ages, every type, fill path (ages 36-40 missing for every type but 11; 11 complete) ####
ages_gap = ages_full %>% filter(sourceTypeID == 11 | ageID <= 35)
r = run_in("sourcetypeagedistribution.csv", ages_gap, adapt_sourcetypeagedistribution)
check(r$msg == "no error", paste("ages complete-gap errors:", r$msg))
check(r$reads == 1, "ages complete-gap did not take the fill path")
old = roundtrip(ages_fill_old(roundtrip(ages_gap), fake_ages()))
check(!anyNA(old$ageFraction), "ages complete-gap: 3.1.0 result has NA/NaN (test input is not complete)")
check(!is.null(r$out) && same_table(r$out, old, age_keys), "ages complete-gap: 3.2 output differs from 3.1.0 (COUNTY RESULT CHANGE)")

# 4. avft, every type, "same" path ####
avft_full = bind_rows(lapply(seq_along(types), function(i){
  data.frame(sourceTypeID = types[i], modelYearID = 1950 + seq_len(avft_n[i]) %/% 4,
             fuelTypeID = 1 + seq_len(avft_n[i]) %% 4, engTechID = 1, fuelEngFraction = 0.25)
}))
r = run_in("avft.csv", avft_full, adapt_avft)
check(r$msg == "no error", paste("avft complete-same errors:", r$msg))
check(r$reads == 0, "avft complete-same took the fill path")
check(!is.null(r$out) && same_table(r$out, roundtrip(roundtrip(avft_full)), avft_keys), "avft complete-same: 3.2 output differs from 3.1.0 (the input)")

# 5. avft, every type, fill path: each type has 1991 fuel 1 (a default stratum) and 1992 fuel 2 (not one) ####
avft_gap = expand.grid(sourceTypeID = types, k = 1:2) %>%
  mutate(modelYearID = 1990 + k, fuelTypeID = k, engTechID = 1, fuelEngFraction = c(0.7, 0.3)[k]) %>%
  select(-k) %>% arrange(sourceTypeID, modelYearID)
r = run_in("avft.csv", avft_gap, adapt_avft)
check(r$msg == "no error", paste("avft complete-gap errors:", r$msg))
check(r$reads == 1, "avft complete-gap did not take the fill path")
old = roundtrip(avft_fill_old(roundtrip(avft_gap), fake_avft()))
check(nrow(old) == nrow(avft_gap) + 2 * 13, "avft complete-gap: 3.1.0 did not add the 2 zero strata per type (test premise)")
check(!is.null(r$out) && same_table(r$out, old, avft_keys), "avft complete-gap: 3.2 output differs from 3.1.0 (COUNTY RESULT CHANGE)")

# 6. The intended difference: types 21 and 62 only ####
ages_part = ages_full %>% filter(sourceTypeID %in% c(21, 62))
r = run_in("sourcetypeagedistribution.csv", ages_part, adapt_sourcetypeagedistribution)
check(r$msg == "no error", paste("ages partial errors in 3.2:", r$msg))
old = ages_fill_old(ages_part, fake_ages())
others_old = old %>% filter(!sourceTypeID %in% c(21, 62))
check(nrow(others_old) == 11 * 41 && all(is.nan(others_old$ageFraction)),
      "ages partial: 3.1.0 weighting no longer gives NaN for missing types (test premise changed)")
if(!is.null(r$out)){
  others_new = r$out %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, ageID)
  want = default_ages %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, ageID)
  check(nrow(others_new) == nrow(want) && all(abs(others_new$ageFraction - want$ageFraction) < 1e-12),
        "ages partial: 3.2 does not keep the national default for missing types")
}
avft_part = avft_gap %>% filter(sourceTypeID %in% c(21, 62))
r = run_in("avft.csv", avft_part, adapt_avft)
check(r$msg == "no error", paste("avft partial errors in 3.2:", r$msg))
old = avft_fill_old(avft_part, fake_avft())
check(all(old$fuelEngFraction[!old$sourceTypeID %in% c(21, 62)] == 0),
      "avft partial: 3.1.0 no longer gives 0 for missing types (test premise changed)")
if(!is.null(r$out)){
  others_new = r$out %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, modelYearID)
  want = svp %>% filter(!sourceTypeID %in% c(21, 62)) %>% arrange(sourceTypeID, modelYearID)
  check(nrow(others_new) == nrow(want) && all(abs(others_new$fuelEngFraction - want$stmyFraction) < 1e-12),
        "avft partial: 3.2 does not give missing types the default fractions")
}

unlink(c(made, db), recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n", paste0("  - ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS: test_adapt_county_unchanged.R\n")
