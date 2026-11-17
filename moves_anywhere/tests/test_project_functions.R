# test_project_functions.R ####################################################
#
# What:      Offline test of scripts/project_functions.R (project-scale helpers).
# Does:      Checks is_project, project_domain, project_spec on the project fixture; one broken copy
#            of the runspec per rule R1 to R10 (exact message, under 70 characters); project_read
#            (adapted, user, default, no default); project_note.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_project_functions.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml, moves_anywhere/inputs_ny/rs_custom.xml
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

suppressPackageStartupMessages({ library(xml2); library(dplyr); library(readr); library(tidyr); library(stringr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/project_functions.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
msg = function(expr){
  tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) })
}

# 1. The good project file ####

good_xml = "moves_anywhere/inputs_project/rs_custom.xml"
made = character(0)
mkdir = function(){ d = tempfile("pf_"); dir.create(d); made <<- c(made, d); d }
good_dir = mkdir()
invisible(file.copy(good_xml, file.path(good_dir, "rs_custom.xml")))
write_csv(data.frame(linkID = 1, countyID = 36109), file.path(good_dir, "link.csv"))
good = file.path(good_dir, "rs_custom.xml")

check(is_project(good), "is_project good")
check(project_domain(good) == "PROJECT", "project_domain good")
check(identical(msg(project_check(good, good_dir)), "no error"), "project_check good")
s = project_spec(good)
check(identical(s$geoid, 36109L), "spec geoid")
check(identical(s$year, 2022L), "spec year")
check(identical(s$month, 7L), "spec month")
check(identical(s$day, 5L), "spec day")
check(identical(s$hour, 8L), "spec hour")
check(identical(s$hourday, 85L), "spec hourday")
check(identical(s$roadtypes, c(1L, 4L, 5L)), "spec roadtypes")
check(length(s$sourcetypes) == 13, "spec 13 vehicle types")
check(length(s$start_polprocess) == 17, "spec 17 start polprocesses")
check(s$start_polprocess[1] == 102L, "spec first start polprocess 102")
check(!is_project("moves_anywhere/inputs_ny/rs_custom.xml"), "county file is not project")

# 2. One broken copy per rule ####

# Read the good file, apply fn to the document, write it to a fresh folder (with link.csv unless asked)
broken = function(fn, link = TRUE){
  d = mkdir()
  x = read_xml(good_xml)
  fn(x)
  write_xml(x, file.path(d, "rs_custom.xml"))
  if(link){ invisible(file.copy(file.path(good_dir, "link.csv"), file.path(d, "link.csv"))) }
  d
}
one = function(x, xpath){ xml_find_first(x, xpath) }
expect = function(fn, expected, label, link = TRUE){
  d = broken(fn, link)
  got = msg(project_check(file.path(d, "rs_custom.xml"), d))
  check(identical(got, expected), paste0(label, ": got '", got, "'"))
  check(nchar(expected) < 70, paste0(label, ": message too long"))
}
dup = function(xpath){ function(x){ n = one(x, xpath); xml_add_sibling(n, n, .copy = TRUE) } }
setattr = function(xpath, attr, value){ function(x){ xml_set_attr(one(x, xpath), attr, value) } }

expect(dup("//geographicselection"), "needs exactly one county (found 2 selections)", "R1")
expect(dup("//timespan/year"), "needs exactly one year (found 2)", "R2")
expect(dup("//timespan/month"), "needs exactly one month (found 2)", "R3")
expect(dup("//timespan/day"), "needs exactly one day type (found 2)", "R4")
expect(function(x){ xml_set_attr(one(x, "//timespan/beginhour"), "id", "7")
                    xml_set_attr(one(x, "//timespan/endhour"), "id", "9") },
       "more than one hour (7 to 9)", "R5")
expect(setattr("//timespan/aggregateBy", "key", "Year"), "aggregateBy must be Hour (found Year)", "R6 aggregateBy")
expect(setattr("//outputtimestep", "value", "Day"), "outputtimestep must be Hour (found Day)", "R6 timestep")
expect(setattr("//geographicoutputdetail", "description", "COUNTY"),
       "geographicoutputdetail must be LINK (found COUNTY)", "R7")
expect(setattr("//outputfactors/massfactors", "units", "Kilograms"),
       "massfactors units must be Grams (found Kilograms)", "R8 mass")
expect(setattr("//outputfactors/distancefactors", "units", "Kilometers"),
       "distancefactors units must be Miles (found Kilometers)", "R8 distance")
expect(setattr("//outputfactors/timefactors", "units", "Seconds"),
       "timefactors units must be Hours (found Seconds)", "R8 time")
expect(setattr("//modelscale", "value", "Rates"),
       "modelscale must be Inv; rates are not supported (found Rates)", "R9")
expect(setattr("//scaleinputdatabase", "databasename", "other"),
       "scaleinputdatabase must be custom (found other)", "R10 database")
expect(function(x){ invisible(NULL) }, "link.csv is missing from the inputs folder", "R10 link.csv", link = FALSE)

# 3. project_read ####

sp = project_spec(good)
raw = data.frame(hourVMTFraction = 0.1, hourID = rep(c(7, 8, 9), 2), dayID = rep(c(2, 5), each = 3),
                 sourceTypeID = 21, roadTypeID = 5)

# (a) adapted file, written unfiltered
da = mkdir()
write_csv(raw, file.path(da, "_hourvmtfraction.csv"))
ra = project_read("hourvmtfraction", good, da, spec = sp)
check(nrow(ra) == 1 && all(ra$hourid == 8) && all(ra$dayid == 5), "read adapted: filtered to hour 8 day 5")
check(all(names(ra) == tolower(names(ra))), "read adapted: lower-case names")
check(identical(attr(ra, "source"), "adapted"), "read adapted: source")

# (b) raw user file with mixed-case names
db = mkdir()
write_csv(data.frame(dayID = c(2, 5), HourID = c(8, 8), StartsHourFraction = c(0.5, 0.25)),
          file.path(db, "startshourfraction.csv"))
rb = project_read("startshourfraction", good, db, spec = sp)
check(nrow(rb) == 1 && rb$startshourfraction == 0.25, "read user: filtered")
check(all(names(rb) == tolower(names(rb))), "read user: lower-case names")
check(identical(attr(rb, "source"), "user"), "read user: source")

# (c) default database, get_table redefined
get_table = function(tablename){
  data.frame(yearID = c(2021, 2022, 2022), monthID = c(7, 7, 1), value = c(1, 2, 3))
}
dc = mkdir()
rc = project_read("somedefault", good, dc, spec = sp)
check(identical(attr(rc, "source"), "default"), "read default: source")
check(nrow(rc) == 1 && rc$value == 2, "read default: year and month filter")
rc2 = project_read("somedefault", good, dc)
check(nrow(rc2) == 1, "read default: spec read from runspec")

# (d) no file, no default
check(identical(msg(project_read("hourvmtfraction", good, dc, default = FALSE, spec = sp)),
                "no hourvmtfraction table found"), "read no default: message")

# 4. project_note ####

dn = mkdir()
project_note("link 5 linkAvgSpeed", "default", "average speed bin", dn)
project_note("link 6 linkAvgSpeed", "user", "35", dn)
notes = read_csv(file.path(dn, "_project_inputs.csv"), show_col_types = FALSE)
check(nrow(notes) == 2 && identical(names(notes), c("item", "source", "detail")), "note: two rows, three columns")

# 5. Result ####

unlink(made, recursive = TRUE)

if(length(failures) > 0){
  cat("FAIL\n", paste0("  ", failures, collapse = "\n"), "\n", sep = "")
  quit(status = 1)
}
cat("PASS\n")
