# test_adapt_offnetwork.R #####################################################
#
# What:      Offline test of scripts/adapt_offnetwork.R (off-network link adapters, project scale).
# Does:      Runs adapt_offnetworklink and adapt_opmodedistribution on small literal tables:
#            13 rows out, population 0 for missing types, default and user start shares (capped at 1),
#            extended idle and parked defaults, soak times weighted by vehicle age (hand-computed),
#            row counts, supplied rows suppressing the defaults, no off-network link, and every
#            check's exact message.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_adapt_offnetwork.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

suppressPackageStartupMessages({ library(xml2); library(dplyr); library(readr); library(tidyr); library(stringr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/project_functions.R")
source("moves_anywhere/scripts/adapt_offnetwork.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
near = function(a, b){ length(a) == length(b) && all(abs(a - b) < 1e-9) }
msg = function(expr){ tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) }) }

# 1. Literal inputs ####

types = c(11, 21, 31, 32, 41, 42, 43, 51, 52, 53, 54, 61, 62)
# Weekday (5), hour 8: only 21, 31 and 32 have start rates; 31 and 32 are capped or user-set
starts = data.frame(dayID = 5, sourceTypeID = c(21, 31, 32), startsPerDayPerVehicle = c(4, 3, 30))
hourly = data.frame(dayID = 5, hourID = 8, sourceTypeID = c(21, 31, 32), allocationFraction = 0.05)
# Two ages, weights 0.25 and 0.75 (the same for every vehicle type)
ages = expand.grid(sourceTypeID = types, ageID = 0:1) %>%
  mutate(yearID = 2022, ageFraction = ifelse(ageID == 0, 0.25, 0.75)) %>%
  select(sourceTypeID, yearID, ageID, ageFraction)
# Default soak table: two ages with DIFFERENT fractions; an off-day row that must be filtered out
soak = bind_rows(
  expand.grid(dayID = 5, hourID = 8, sourceTypeID = types, ageID = 0:1, opModeID = 101:102) %>%
    mutate(opModeFraction = case_when(ageID == 0 & opModeID == 101 ~ 0.9, ageID == 0 ~ 0.1,
                                      opModeID == 101 ~ 0.3, TRUE ~ 0.7)),
  data.frame(dayID = 2, hourID = 8, sourceTypeID = 21, ageID = 0, opModeID = 101, opModeFraction = 1)
)
get_table = function(tablename){
  if(tablename == "startsopmodedistribution"){ return(soak) }
  stop(paste0("test has no default table ", tablename))
}
# Hand-computed age-weighted soak: 101 = 0.25 * 0.9 + 0.75 * 0.3 = 0.45; 102 = 0.25 * 0.1 + 0.75 * 0.7 = 0.55
# (a plain average over ages would give 0.6 and 0.4)

links = data.frame(
  linkID = c(1, 2, 7), countyID = 36109, zoneID = 361090, roadTypeID = c(5, 5, 1),
  linkLength = c(0.5, 0.5, 0), linkVolume = c(800, 800, 0), linkAvgSpeed = c(25, 25, 0),
  linkDescription = "", linkAvgGrade = 0)
links_no_off = links[links$roadTypeID != 1, ]

made = character(0)
bucket = function(link = links, user_off = NULL, user_op = NULL){
  d = tempfile("off_"); dir.create(d); made <<- c(made, d)
  invisible(file.copy("moves_anywhere/inputs_project/rs_custom.xml", file.path(d, "rs_custom.xml")))
  write_csv(link, file.path(d, "_link.csv"))
  write_csv(starts, file.path(d, "_startsperdaypervehicle.csv"))
  write_csv(hourly, file.path(d, "_startshourfraction.csv"))
  write_csv(ages, file.path(d, "_sourcetypeagedistribution.csv"))
  if(!is.null(user_off)){ write_csv(user_off, file.path(d, "offnetworklink.csv")) }
  if(!is.null(user_op)){ write_csv(user_op, file.path(d, "opmodedistribution.csv")) }
  d
}
rs = function(d){ file.path(d, "rs_custom.xml") }

user_off = data.frame(
  sourceTypeID = c(21, 31, 32), vehiclePopulation = c(200, 150, 10),
  startFraction = c(NA, 0.5, NA), parkedVehicleFraction = c(0.8, NA, NA))

# 2. offnetworklink: fill-in ####

d = bucket(user_off = user_off)
adapt_offnetworklink(rs(d), d)
out = read_csv(file.path(d, "_offnetworklink.csv"), show_col_types = FALSE)
check(identical(names(out), c("zoneID", "sourceTypeID", "vehiclePopulation", "startFraction",
                              "extendedIdleFraction", "parkedVehicleFraction")), "offnetworklink columns")
check(nrow(out) == 13, "13 rows out")
check(identical(as.numeric(out$sourceTypeID), sort(types)), "sorted by sourceTypeID")
check(all(out$zoneID == 361090), "zoneID from the link")
check(near(out$vehiclePopulation[out$sourceTypeID %in% c(21, 31, 32)], c(200, 150, 10)), "user populations")
check(all(out$vehiclePopulation[!out$sourceTypeID %in% c(21, 31, 32)] == 0), "population 0 for missing types")
check(near(out$startFraction[out$sourceTypeID == 21], 4 * 0.05), "default start share is the product")
check(near(out$startFraction[out$sourceTypeID == 32], 1), "default start share capped at 1")
check(near(out$startFraction[out$sourceTypeID == 31], 0.5), "user start share kept")
check(near(out$startFraction[out$sourceTypeID == 11], 0), "no start rate gives 0")
check(all(out$extendedIdleFraction == 0), "extended idle default 0")
check(near(out$parkedVehicleFraction[out$sourceTypeID == 21], 0.8), "user parked share kept")
check(near(out$parkedVehicleFraction[out$sourceTypeID == 31], 1), "parked default 1")
notes = read_csv(file.path(d, "_project_inputs.csv"), show_col_types = FALSE)
check("off-network startFraction" %in% notes$item &&
        notes$source[notes$item == "off-network startFraction"] == "default", "start note")
check(all(c("off-network extendedIdleFraction", "off-network parkedVehicleFraction") %in% notes$item), "default notes")

# Everything given by the user: the start note says "user"
full = data.frame(sourceTypeID = types, vehiclePopulation = 1, startFraction = 0.1,
                  extendedIdleFraction = 0, parkedVehicleFraction = 1)
d = bucket(user_off = full)
adapt_offnetworklink(rs(d), d)
notes = read_csv(file.path(d, "_project_inputs.csv"), show_col_types = FALSE)
check(notes$source[notes$item == "off-network startFraction"] == "user", "user start note")
check(nrow(notes) == 1, "no default notes when all given")

# 3. offnetworklink: no off-network link, and every check ####

d = bucket(link = links_no_off)
adapt_offnetworklink(rs(d), d)
check(!file.exists(file.path(d, "_offnetworklink.csv")), "no off-network link writes nothing")

err = function(user, link = links){
  d = bucket(link = link, user_off = user)
  msg(adapt_offnetworklink(rs(d), d))
}
check(err(user_off, links_no_off) == "offnetworklink.csv given but no link has roadTypeID 1", "msg given but no link")
check(err(NULL) == "off-network link needs offnetworklink.csv", "msg needs file")
check(err(user_off[, c("sourceTypeID", "startFraction")]) == "offnetworklink.csv needs column vehiclePopulation", "msg no population")
check(err(user_off[, c("vehiclePopulation", "startFraction")]) == "offnetworklink.csv needs column sourceTypeID", "msg no type")
bad = user_off; bad$sourceTypeID[1] = 99
check(err(bad) == "offnetworklink.csv sourceTypeID not in the run's vehicle types", "msg unknown type")
bad = user_off; bad$sourceTypeID[2] = 21
check(err(bad) == "offnetworklink.csv repeats a sourceTypeID", "msg repeated type")
bad = user_off; bad$vehiclePopulation[1] = -1
check(err(bad) == "offnetworklink.csv vehiclePopulation must be 0 or more", "msg negative population")
bad = user_off; bad$vehiclePopulation[1] = NA
check(err(bad) == "offnetworklink.csv vehiclePopulation must be 0 or more", "msg blank population")
bad = user_off; bad$startFraction[2] = 1.5
check(err(bad) == "offnetworklink.csv startfraction must be 0 to 1", "msg fraction out of range")

# 4. opmodedistribution: soak defaults ####

d = bucket(user_off = user_off)
adapt_opmodedistribution(rs(d), d)
op = read_csv(file.path(d, "_opmodedistribution.csv"), show_col_types = FALSE)
check(identical(names(op), c("sourceTypeID", "hourDayID", "linkID", "polProcessID", "opModeID", "opModeFraction")),
      "opmodedistribution columns")
n_start = length(project_spec(rs(d))$start_polprocess)
check(n_start == 17, "17 start pollutant-processes in the fixture")
check(nrow(op) == 13 * 2 * n_start, "rows = types x modes x start polprocesses")
check(all(op$hourDayID == 85) && all(op$linkID == 7), "hourDayID and off-network linkID")
check(all(op$polProcessID %in% project_spec(rs(d))$start_polprocess), "only start polprocesses")
check(near(op$opModeFraction[op$opModeID == 101], rep(0.45, 13 * n_start)), "age-weighted soak 101")
check(near(op$opModeFraction[op$opModeID == 102], rep(0.55, 13 * n_start)), "age-weighted soak 102")
sums = op %>% group_by(sourceTypeID, polProcessID) %>% summarize(total = sum(opModeFraction), .groups = "drop")
check(near(sums$total, rep(1, nrow(sums))), "soak sums to 1")
check(identical(op, op %>% arrange(sourceTypeID, hourDayID, linkID, polProcessID, opModeID)), "sorted")
notes = read_csv(file.path(d, "_project_inputs.csv"), show_col_types = FALSE)
check(notes$source[notes$item == "start soak times (opmodedistribution)"] == "default", "soak note default")

# Ages that do not sum to 1 are renormalised: weights 0.5 and 1.5 give the same 0.45 and 0.55
ages_big = ages; ages_big$ageFraction = ages_big$ageFraction * 2
d = bucket(user_off = user_off)
write_csv(ages_big, file.path(d, "_sourcetypeagedistribution.csv"))
adapt_opmodedistribution(rs(d), d)
op2 = read_csv(file.path(d, "_opmodedistribution.csv"), show_col_types = FALSE)
check(near(op2$opModeFraction[op2$opModeID == 101], rep(0.45, 13 * n_start)), "renormalised")

# Supplied rows for the off-network link suppress the defaults
supplied = data.frame(sourceTypeID = 21, hourDayID = 85, linkID = 7, polProcessID = c(202, 202),
                      opModeID = c(101, 102), opModeFraction = c(0.3, 0.7))
d = bucket(user_off = user_off, user_op = supplied)
adapt_opmodedistribution(rs(d), d)
op3 = read_csv(file.path(d, "_opmodedistribution.csv"), show_col_types = FALSE)
mine = op3[op3$sourceTypeID == 21 & op3$polProcessID == 202, ]
check(nrow(mine) == 2 && all(near(sort(mine$opModeFraction), c(0.3, 0.7))), "supplied soak rows are kept for their pair")
check(nrow(op3) == 2 + (13 * n_start - 1) * 2, "defaults fill only the pairs the user left out")
notes = read_csv(file.path(d, "_project_inputs.csv"), show_col_types = FALSE)
check(notes$source[notes$item == "start soak times (opmodedistribution)"] == "default", "soak note default when only some pairs were supplied")
check(grepl(" of ", notes$detail[notes$item == "start soak times (opmodedistribution)"]), "soak note counts the pairs")

# Supplied rows for a road link only: kept, and defaults appended for the off-network link
road = data.frame(sourceTypeID = 21, hourDayID = 85, linkID = 1, polProcessID = 101,
                  opModeID = c(0, 1), opModeFraction = c(0.4, 0.6))
d = bucket(user_off = user_off, user_op = road)
adapt_opmodedistribution(rs(d), d)
op4 = read_csv(file.path(d, "_opmodedistribution.csv"), show_col_types = FALSE)
check(nrow(op4) == 2 + 13 * 2 * n_start, "road-link rows kept plus defaults")
check(sum(op4$linkID == 1) == 2, "road-link rows kept")

# No off-network link: supplied rows pass through, no defaults; nothing supplied writes nothing
d = bucket(link = links_no_off, user_op = road)
adapt_opmodedistribution(rs(d), d)
op5 = read_csv(file.path(d, "_opmodedistribution.csv"), show_col_types = FALSE)
check(nrow(op5) == 2, "no off-network link: supplied rows pass through")
d = bucket(link = links_no_off)
adapt_opmodedistribution(rs(d), d)
check(!file.exists(file.path(d, "_opmodedistribution.csv")), "no off-network link, no rows: nothing written")

# No start process in the run: no defaults
x = read_xml(rs(bucket(user_off = user_off)))
for(node in xml_find_all(x, "//pollutantprocessassociation[@processkey='2']")){ xml_remove(node) }
d = bucket(user_off = user_off)
write_xml(x, rs(d))
adapt_opmodedistribution(rs(d), d)
check(!file.exists(file.path(d, "_opmodedistribution.csv")), "no start process: nothing written")

# 5. opmodedistribution: checks ####

operr = function(user){
  d = bucket(user_off = user_off, user_op = user)
  msg(adapt_opmodedistribution(rs(d), d))
}
check(operr(road[, -6]) == "opmodedistribution.csv needs column opModeFraction", "msg missing column")
bad = road; bad$hourDayID = 75
check(operr(bad) == "opmodedistribution.csv hourDayID must be 85", "msg hourDayID")
bad = road; bad$linkID = 99
check(operr(bad) == "opmodedistribution.csv linkID 99 is not in link.csv", "msg unknown link")
bad = road; bad$opModeFraction = c(0.4, 0.5)
check(operr(bad) == "opmodedistribution for link 1 does not sum to 1", "msg sum")

# 6. Result ####

unlink(made, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n"); cat(paste0(" - ", failures), sep = "\n")
  quit(status = 1)
}
cat("PASS\n")
