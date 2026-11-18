# test_adapt_ages_county.R ####################################################
#
# What:      Offline test of the age_source setting (scripts/adapt_ages_county.R and
#            scripts/adapt_sourcetypeagedistribution.R).
# Does:      Setting absent or national: the written _sourcetypeagedistribution.csv is byte-identical
#            to the released v3.1.0 adapter's output (and to the default rows written as they are), and
#            no _age_source.txt appears. County in an inventory year (2020): the county rows of the
#            reference to 1e-9, long-haul 53 and 62 national. County in 2030: sums to 1, equals the
#            national 2030 table x the capped 2023 ratio, renormalised. County not in the file, or no
#            file: national rows with the fallback line. A user table: the user table wins. A value
#            other than national or county stops. The default tables come from a small SQLite
#            database standing in for MariaDB; the reference is a small fake .rds in a temp folder.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_adapt_ages_county.R
# Reads:     moves_anywhere/inputs_ny/rs_custom.xml (county 36109, year rewritten per check);
#            git show v3.1.0:moves_anywhere/scripts/adapt_sourcetypeagedistribution.R (read-only)
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(DBI); library(RSQLite); library(dbplyr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/adapt_ages_county.R")
source("moves_anywhere/scripts/adapt_sourcetypeagedistribution.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
msg = function(expr){ tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) }) }

root = getwd()
types = c(11, 21, 31, 32, 41, 42, 43, 51, 52, 53, 54, 61, 62)
years = c(2020, 2022, 2023, 2030)

# FAKE DATA: national default ages, a different smooth shape per type and year
default_ages = expand.grid(sourceTypeID = types, ageID = 0:40, yearID = years) %>%
  mutate(w = exp(-ageID / (8 + sourceTypeID %% 7 + (yearID - 2020) / 5))) %>%
  group_by(sourceTypeID, yearID) %>% mutate(ageFraction = w / sum(w)) %>% ungroup() %>%
  select(sourceTypeID, yearID, ageID, ageFraction) %>% arrange(yearID, sourceTypeID, ageID)
db = tempfile("ages_defaults_", fileext = ".sqlite")
con = dbConnect(SQLite(), db); dbWriteTable(con, "sourcetypeagedistribution", default_ages); dbDisconnect(con)
connect = function(type, dbname){ dbConnect(SQLite(), db) }

# FAKE DATA: the NEI reference for county 36109, 2020 and 2023: younger fleets, one extreme age
ref = expand.grid(geoid = "36109", year = c(2020, 2023), sourceTypeID = types, ageID = 0:40,
                  stringsAsFactors = FALSE) %>%
  mutate(w = exp(-ageID / (5 + sourceTypeID %% 5)) * ifelse(ageID == 3, 30, 1)) %>%
  group_by(geoid, year, sourceTypeID) %>% mutate(ageFraction = w / sum(w)) %>% ungroup() %>%
  select(geoid, year, sourceTypeID, ageID, ageFraction)
refdir = tempfile("ages_ref_"); dir.create(refdir)
refpath = file.path(refdir, "nei_sourcetypeagedistribution.rds"); saveRDS(ref, refpath)

# The released adapter, for the byte comparison (skipped, and reported, if git cannot read it)
released = tempfile("released_", fileext = ".R")
got = tryCatch(system2("git", c("show", "v3.1.0:moves_anywhere/scripts/adapt_sourcetypeagedistribution.R"),
                       stdout = released, stderr = FALSE), error = function(e){ 1 })
old = new.env()
if(identical(as.integer(got), 0L)){ sys.source(released, envir = old) }

base_rs = readLines("moves_anywhere/inputs_ny/rs_custom.xml", warn = FALSE)
made = character(0)
run_in = function(year, fun = adapt_sourcetypeagedistribution, user = NULL, env = "", params = NULL,
                  geoid = NULL, reference = refpath){
  d = tempfile("ages_"); dir.create(file.path(d, "inputs"), recursive = TRUE); made <<- c(made, d)
  rs = gsub('<year key="[0-9]+"/>', paste0('<year key="', year, '"/>'), base_rs)
  if(!is.null(geoid)){ rs = gsub('36109', geoid, rs) }
  writeLines(rs, file.path(d, "rs.xml"))
  if(!is.null(user)){ write_csv(user, file.path(d, "inputs", "sourcetypeagedistribution.csv")) }
  if(!is.null(params)){ writeLines(params, file.path(d, "inputs", "parameters.json")) }
  Sys.setenv(AGE_SOURCE = env)
  setwd(d); on.exit({ setwd(root); Sys.unsetenv("AGE_SOURCE") })
  args = list(.runspec = file.path(d, "rs.xml"))
  if(".reference" %in% names(formals(fun))){ args$.reference = reference }
  m = msg(capture.output(do.call(fun, args)))
  f = file.path(d, "inputs", "_sourcetypeagedistribution.csv")
  note = file.path(d, "inputs", "_age_source.txt")
  list(msg = m, bytes = if(file.exists(f)){ readBin(f, "raw", file.size(f)) }else{ NULL },
       out = if(file.exists(f)){ read_csv(f, show_col_types = FALSE) }else{ NULL },
       note = if(file.exists(note)){ readLines(note) }else{ NULL })
}
nat = function(y){ default_ages %>% filter(yearID == y) }
user = default_ages %>% filter(yearID == 2022) %>% mutate(ageFraction = 1 / 41)

# 1. Absent, national (environment), national (parameters.json): byte-identical, no note ####
for(y in c(2022, 2020)){
  a = run_in(y)
  want = tempfile(fileext = ".csv"); write_csv(nat(y), want); want = readBin(want, "raw", file.size(want))
  check(a$msg == "no error", paste("absent", y, "errors:", a$msg))
  check(identical(a$bytes, want), paste("absent", y, ": not the default rows byte for byte"))
  check(is.null(a$note), paste("absent", y, ": _age_source.txt written"))
  if(exists("adapt_sourcetypeagedistribution", envir = old)){
    r = run_in(y, fun = get("adapt_sourcetypeagedistribution", envir = old))
    check(identical(a$bytes, r$bytes), paste("absent", y, ": differs from the released adapter"))
  }
  e = run_in(y, env = "national"); p = run_in(y, params = '{"age_source": "national"}')
  check(identical(a$bytes, e$bytes) && identical(a$bytes, p$bytes), paste("national", y, ": differs from absent"))
  check(is.null(e$note) && is.null(p$note), paste("national", y, ": _age_source.txt written"))
}
# A user table with the setting absent: byte-identical to the released adapter
u = run_in(2022, user = user)
if(exists("adapt_sourcetypeagedistribution", envir = old)){
  r = run_in(2022, fun = get("adapt_sourcetypeagedistribution", envir = old), user = user)
  check(identical(u$bytes, r$bytes), "user table, absent: differs from the released adapter")
}
check(is.null(u$note), "user table, absent: _age_source.txt written")

# 2. County, inventory year 2020: the reference rows to 1e-9; 53 and 62 national ####
c20 = run_in(2020, env = "county")
check(c20$msg == "no error", paste("county 2020 errors:", c20$msg))
if(!is.null(c20$out)){
  got20 = c20$out %>% arrange(sourceTypeID, ageID)
  want20 = ref %>% filter(year == 2020, !sourceTypeID %in% c(53, 62)) %>% arrange(sourceTypeID, ageID)
  mine = got20 %>% filter(!sourceTypeID %in% c(53, 62))
  check(nrow(mine) == nrow(want20) && all(abs(mine$ageFraction - want20$ageFraction) < 1e-9), "county 2020: not the reference rows (1e-9)")
  lh = got20 %>% filter(sourceTypeID %in% c(53, 62))
  lhw = nat(2020) %>% filter(sourceTypeID %in% c(53, 62)) %>% arrange(sourceTypeID, ageID)
  check(all(abs(lh$ageFraction - lhw$ageFraction) < 1e-12), "county 2020: 53 and 62 not national")
  check(nrow(got20) == 13 * 41 && all(got20$yearID == 2020), "county 2020: not 13 types x 41 ages of 2020")
}
check(identical(c20$note, "ages: NEI 2020 county 36109 (EPA county table for 2020); long-haul 53 and 62 national"),
      paste("county 2020 note:", paste(c20$note, collapse = " / ")))
# parameters.json gives the same result
p20 = run_in(2020, params = '{"age_source": "county"}')
check(identical(c20$bytes, p20$bytes), "county 2020 via parameters.json differs from AGE_SOURCE")

# 3. County, 2030: national 2030 x capped 2023 ratio, renormalised, sums to 1 ####
c30 = run_in(2030, env = "county")
check(c30$msg == "no error", paste("county 2030 errors:", c30$msg))
if(!is.null(c30$out)){
  ratio = ref %>% filter(year == 2023) %>% select(sourceTypeID, ageID, county = ageFraction) %>%
    inner_join(nat(2023) %>% select(sourceTypeID, ageID, n23 = ageFraction), by = c("sourceTypeID", "ageID")) %>%
    mutate(r = pmin(pmax(county / n23, 0.25), 4))
  check(any(ratio$county / ratio$n23 > 4) && any(ratio$county / ratio$n23 < 0.25), "fake data does not exercise the cap")
  want30 = nat(2030) %>% inner_join(ratio, by = c("sourceTypeID", "ageID")) %>%
    mutate(a = ifelse(sourceTypeID %in% c(53, 62), ageFraction, ageFraction * r)) %>%
    group_by(sourceTypeID) %>% mutate(a = a / sum(a)) %>% ungroup() %>% arrange(sourceTypeID, ageID)
  got30 = c30$out %>% arrange(sourceTypeID, ageID)
  check(nrow(got30) == nrow(want30) && all(abs(got30$ageFraction - want30$a) < 1e-9), "county 2030: not national x capped 2023 ratio")
  sums = got30 %>% group_by(sourceTypeID) %>% summarize(s = sum(ageFraction))
  check(all(abs(sums$s - 1) < 1e-9), "county 2030: a vehicle type does not sum to 1")
  check(!anyNA(got30), "county 2030: NA")
}
check(length(c30$note) == 1 && grepl("ratio of 2023, capped 0.25 to 4", c30$note), paste("county 2030 note:", paste(c30$note, collapse = " / ")))
# 2022 lies between the NEI years: both ratios, interpolated
c22 = run_in(2022, env = "county")
check(c22$msg == "no error" && length(c22$note) == 1 && grepl("ratio of 2020 and 2023 \\(interpolated\\)", c22$note),
      paste("county 2022 note:", paste(c22$note, collapse = " / ")))

# 4. County not in the file, or no file: national rows, fallback line ####
n1 = run_in(2022, env = "county", geoid = "01001")
n0 = run_in(2022, geoid = "01001")
check(n1$msg == "no error" && identical(n1$bytes, n0$bytes), "county not in the file: not the national rows")
check(identical(n1$note, "ages: national default (age_source county asked for, but county 01001 is not in the NEI reference file)"),
      paste("county not in the file note:", paste(n1$note, collapse = " / ")))
m1 = run_in(2022, env = "county", reference = file.path(refdir, "absent.rds"))
check(m1$msg == "no error" && identical(m1$bytes, run_in(2022)$bytes), "no reference file: not the national rows")
check(identical(m1$note, "ages: national default (age_source county asked for, but the NEI reference file is missing)"),
      paste("no reference file note:", paste(m1$note, collapse = " / ")))

# 5. A user table wins over county ####
uc = run_in(2022, env = "county", user = user)
check(uc$msg == "no error" && identical(uc$bytes, u$bytes), "user table, county: differs from the user table output")
check(length(uc$note) == 1 && grepl("user table", uc$note), "user table, county: note does not say the user table won")

# 6. A value that is neither stops ####
bad = run_in(2022, env = "state")
check(grepl("age_source must be national or county", bad$msg), paste("bad value did not stop:", bad$msg))

unlink(c(made, db, refdir, released), recursive = TRUE)
if(!exists("adapt_sourcetypeagedistribution", envir = old)){ cat("NOTE: released adapter not readable through git; byte checks against it skipped\n") }
if(length(failures) > 0){
  cat("FAIL\n", paste0("  - ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS: test_adapt_ages_county (absent/national byte-identical, county 2020 / 2022 / 2030, fallback, user wins)\n")
