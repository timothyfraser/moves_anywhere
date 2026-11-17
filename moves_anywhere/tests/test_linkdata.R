# test_linkdata.R ##############################################################
#
# What:      Offline test of get_linkdata() and linkdata_summary()
# Does:      Builds a small MOVES output (2 links, 2 regClasses) in a temp folder, runs get_linkdata,
#            checks columns, sums, activity repeated not multiplied, zero starts, newest run wins.
# Called by: run by hand from the repository root: Rscript moves_anywhere/tests/test_linkdata.R
# Reads:     nothing outside a temp folder
# Writes:    a temp folder, removed at the end
# Exits:     0 and prints PASS; non-zero and prints what failed
###############################################################################

suppressMessages({library(dplyr); library(readr)})
source("moves_anywhere/scripts/task_get_linkdata.R")

fails = character(0)
check = function(ok, msg){ if(!isTRUE(ok)){ fails <<- c(fails, msg) } }

# 1. Literal inputs ####
em = function(run, link, pol, proc, st, reg, q){
  data.frame(MOVESRunID = run, iterationID = 1, yearID = 2022, monthID = 7, dayID = 5, hourID = 8,
             stateID = 36, countyID = 36109, zoneID = 361090, linkID = link, pollutantID = pol,
             processID = proc, sourceTypeID = st, regClassID = reg, fuelTypeID = 1, modelYearID = 2020,
             roadTypeID = 5, emissionQuant = q)
}
act = function(run, link, st, reg, type, v){
  # MOVES writes the vehicle population (type 6) under month 0, day 0, hour 0
  when = if(type == 6) 0 else 1
  data.frame(MOVESRunID = run, iterationID = 1, yearID = 2022, monthID = 7 * when, dayID = 5 * when,
             hourID = 8 * when,
             stateID = 36, countyID = 36109, zoneID = 361090, linkID = link, sourceTypeID = st,
             regClassID = reg, fuelTypeID = 1, modelYearID = 2020, roadTypeID = 5,
             activityTypeID = type, activity = v)
}
moves = bind_rows(
  em(2, 1, 90, 1, 21, 20, 100), em(2, 1, 90, 1, 21, 30, 50),   # regClass summed: 150
  em(2, 1, 3, 1, 21, 20, 2),    em(2, 1, 3, 1, 21, 30, 1),     # 3
  em(2, 1, 90, 2, 21, 20, 10),                                 # second process on link 1
  em(2, 1, 90, 1, 31, 20, 70),  em(2, 1, 3, 1, 31, 20, 4),     # second vehicle type
  em(2, 2, 90, 1, 21, 20, 200), em(2, 2, 3, 1, 21, 20, 5),
  em(2, 2, 90, 1, 21, 30, 40),  em(2, 2, 3, 1, 21, 30, 1),
  em(1, 1, 90, 1, 21, 20, 9999))                               # older run: must be ignored
activity = bind_rows(
  act(2, 1, 21, 20, 1, 3), act(2, 1, 21, 30, 1, 1),            # vmt link1 type21 = 4
  act(2, 1, 21, 20, 4, 0.5), act(2, 1, 21, 30, 4, 0.25),       # hours 0.75
  act(2, 1, 21, 20, 6, 10), act(2, 1, 21, 20, 7, 6),           # vehicles 10, starts 6
  act(2, 1, 31, 20, 1, 2),                                     # type 31: miles only, no starts
  act(2, 2, 21, 20, 1, 8), act(2, 2, 21, 30, 1, 2),            # vmt link2 = 10
  act(1, 1, 21, 20, 1, 777))
link = data.frame(linkID = 1:2, linkLength = 0.5, roadTypeID = c(5, 4), linkDescription = c("a", "b"))
dir = tempfile("linkdata"); dir.create(dir)
write_csv(moves, file.path(dir, "movesoutput.csv"))
write_csv(activity, file.path(dir, "movesactivityoutput.csv"))
write_csv(link, file.path(dir, "_link.csv"))

# 2. Run and check ####
path = get_linkdata(dir)
d = read_csv(path, show_col_types = FALSE)
want = c("year","month","day","hour","geoid","link","roadtype","pollutant","process","sourcetype",
         "fueltype","emissions","vmt","sourcehours","starts","vehicles")
check(identical(names(d), want), "column names or order")
check(abs(sum(d$emissions) - sum(moves$emissionQuant[moves$MOVESRunID == 2])) < 1e-9, "emissions total")
check(!any(duplicated(d[c("link","pollutant","process","sourcetype","fueltype")])), "one row per key")
check(nrow(d) == 7, paste("row count", nrow(d)))
check(identical(order(d$link, d$pollutant, d$process, d$sourcetype, d$fueltype), seq_len(nrow(d))), "sort order")
a = d %>% filter(link == 1, sourcetype == 21, pollutant == 90, process == 1)
check(a$emissions == 150, "regClass summed")
x = d %>% filter(link == 1, sourcetype == 21)
check(all(x$vmt == 4), "vmt repeated, not multiplied")
check(all(x$sourcehours == 0.75) & all(x$vehicles == 10) & all(x$starts == 6), "other activity")
check(all(d$starts[d$sourcetype == 31] == 0), "no starts gives 0")
check(all(d$roadtype[d$link == 2] == 4), "roadtype from _link.csv")
check(!any(d$emissions == 9999), "highest MOVESRunID wins")
check(!any(d$vmt == 777), "highest MOVESRunID wins (activity)")

# 3. Summary arithmetic ####
s = linkdata_summary(d, link)
l1 = s %>% filter(link == 1)
check(abs(l1$miles - 6) < 1e-9, paste("miles counted once per type, got", l1$miles))  # 4 + 2
check(abs(l1$co2 - 230) < 1e-9 & abs(l1$nox - 7) < 1e-9, "co2/nox sums")
check(abs(l1$co2_per_mile - 230 / 6) < 1e-9, "co2 per mile")
check(l1$starts == 6, "starts counted once")
d0 = d %>% mutate(vmt = 0)
check(is.na(linkdata_summary(d0, link)$co2_per_mile[1]), "blank per-mile at 0 miles")

# 4. Result ####
unlink(dir, recursive = TRUE)
if(length(fails) > 0){
  cat("FAIL:\n", paste0(" - ", fails, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS\n")
