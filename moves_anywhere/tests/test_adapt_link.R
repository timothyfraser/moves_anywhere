# test_adapt_link.R ###########################################################
#
# What:      Offline test of the project-scale link adapters (adapt_link.R).
# Does:      Builds a small project run in a temp folder (runspec from inputs_project, small literal
#            county tables, a literal avgspeedbin) and checks the fills, the defaults and every stop().
# Called by: run by hand from the repository root: Rscript moves_anywhere/tests/test_adapt_link.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml, moves_anywhere/scripts/*.R
# Writes:    a temp folder only (removed at the end)
# Exits:     0 and prints PASS, or prints what failed and exits 1
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(stringr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/project_functions.R")
source("moves_anywhere/scripts/adapt_link.R")

# The default database is not available here: a literal avgspeedbin
get_table = function(tablename){
  if(tablename == "avgspeedbin"){
    return(data.frame(avgSpeedBinID = 1:3, avgBinSpeed = c(5, 20, 60)))
  }
  stop(paste0("test has no default table ", tablename))
}

failures = character(0)
check = function(ok, what){ if(!isTRUE(ok)){ failures <<- c(failures, what) } }
fails_with = function(expr, pattern, what){
  msg = tryCatch({ force(expr); "NO ERROR" }, error = function(e) conditionMessage(e))
  check(grepl(pattern, msg, fixed = TRUE), paste0(what, " (got: ", msg, ")"))
}

# 1. A project run in a temp folder ####
root = tempfile("adapt_link_")
dir.create(root)
rs = paste0(root, "/rs_custom.xml")
file.copy("moves_anywhere/inputs_project/rs_custom.xml", rs)
spec = project_spec(rs)
st = spec$sourcetypes                       # all 13
geoid = spec$geoid

# County tables: only car (21) and combination truck (62) carry mileage
vmt_of = ifelse(st == 21, 3e6, ifelse(st == 62, 1e6, 0))
write_county = function(B){
  write_csv(data.frame(yearID = 2022, sourceTypeID = st, VMT = vmt_of), paste0(B, "/_sourcetypeyearvmt.csv"))
  write_csv(data.frame(sourceTypeID = st, monthID = 7, monthVMTFraction = 0.1), paste0(B, "/_monthvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, monthID = 7, roadTypeID = c(4, 5), dayID = 5) %>%
              mutate(dayVMTFraction = 0.7), paste0(B, "/_dayvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = c(4, 5), dayID = 5, hourID = 8) %>%
              mutate(hourVMTFraction = 0.06), paste0(B, "/_hourvmtfraction.csv"))
  # Cars: 0.5 on type 4, 0.25 on type 5. Trucks: 0.25 on type 4, 0.5 on type 5. Road type 1 shares are 0.
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = c(1, 4, 5)) %>%
              mutate(roadTypeVMTFraction = case_when(
                roadTypeID == 1 ~ 0,
                sourceTypeID == 21 & roadTypeID == 4 ~ 0.5, sourceTypeID == 21 & roadTypeID == 5 ~ 0.25,
                sourceTypeID == 62 & roadTypeID == 4 ~ 0.25, sourceTypeID == 62 & roadTypeID == 5 ~ 0.5,
                TRUE ~ 0)), paste0(B, "/_roadtypedistribution.csv"))
  # Speed distribution for road type 5 at hourDay 85: cars 50/50 in bins 2 and 3, trucks all in bin 1
  write_csv(bind_rows(
    expand.grid(sourceTypeID = st[!st %in% c(21, 62)], roadTypeID = c(4, 5), hourDayID = 85, avgSpeedBinID = 2, avgSpeedFraction = 1),
    data.frame(sourceTypeID = 21, roadTypeID = 5, hourDayID = 85, avgSpeedBinID = 2:3, avgSpeedFraction = c(0.5, 0.5)),
    data.frame(sourceTypeID = 62, roadTypeID = 5, hourDayID = 85, avgSpeedBinID = 1, avgSpeedFraction = 1),
    data.frame(sourceTypeID = c(21, 62), roadTypeID = 4, hourDayID = 85, avgSpeedBinID = 3, avgSpeedFraction = 1),
    # a row for another hour that must be ignored
    data.frame(sourceTypeID = 21, roadTypeID = 5, hourDayID = 95, avgSpeedBinID = 1, avgSpeedFraction = 1)
  ), paste0(B, "/_avgspeeddistribution.csv"))
}

new_bucket = function(link, mix = NULL, sched = NULL){
  B = tempfile("bucket_", tmpdir = root)
  dir.create(B)
  write_county(B)
  write_csv(link, paste0(B, "/link.csv"))
  if(!is.null(mix)){ write_csv(mix, paste0(B, "/linksourcetypehour.csv")) }
  if(!is.null(sched)){ write_csv(sched, paste0(B, "/driveschedulesecondlink.csv")) }
  B
}
run = function(B){
  adapt_link(rs, B); adapt_linksourcetypehour(rs, B); adapt_driveschedulesecondlink(rs, B)
}
base_link = data.frame(
  linkID = c(1, 2, 3, 4, 5, 6),
  roadTypeID = c(5, 5, 4, 5, 5, 1),
  linkLength = c(0.5, 0.5, 1, 0.5, 0.5, NA),
  linkVolume = c(800, 800, 3000, 800, 800, NA),
  linkAvgSpeed = c(NA, 25, NA, NA, NA, NA),
  linkDescription = c("default speed", "user speed", "freeway", "schedule", "user mix", "off-network"))
sched = data.frame(linkID = 4, secondID = 1:3, speed = c(10, 20, 30))
mix = data.frame(linkID = 5, sourceTypeID = c(21, 62), sourceTypeHourFraction = c(0.9, 0.1))

# 2. A full run ####
B = new_bucket(base_link, mix, sched)
run(B)
lk = read_csv(paste0(B, "/_link.csv"), show_col_types = FALSE)
lm = read_csv(paste0(B, "/_linksourcetypehour.csv"), show_col_types = FALSE)
ds = read_csv(paste0(B, "/_driveschedulesecondlink.csv"), show_col_types = FALSE)
notes = read_csv(paste0(B, "/_project_inputs.csv"), show_col_types = FALSE)

check(identical(names(lk), c("linkID", "countyID", "zoneID", "roadTypeID", "linkLength", "linkVolume",
                             "linkAvgSpeed", "linkDescription", "linkAvgGrade")), "_link.csv columns")
check(identical(names(lm), c("linkID", "sourceTypeID", "sourceTypeHourFraction")), "_linksourcetypehour.csv columns")
check(identical(names(ds), c("linkID", "secondID", "speed", "grade")), "_driveschedulesecondlink.csv columns")
check(all(lk$countyID == geoid) && all(lk$zoneID == geoid * 10) && all(lk$linkAvgGrade == 0), "county, zone, grade fills")
check(all(lk$linkLength[lk$linkID == 6] == 0, lk$linkVolume[lk$linkID == 6] == 0, lk$linkAvgSpeed[lk$linkID == 6] == 0),
      "off-network length, volume, speed are 0")
check(!is.unsorted(lk$linkID), "_link.csv sorted")

# Fractions sum to 1 on every road link, and the off-network link has no rows
sums = lm %>% group_by(linkID) %>% summarise(s = sum(sourceTypeHourFraction))
check(all(abs(sums$s - 1) < 1e-9), "fractions sum to 1 per road link")
check(!6 %in% lm$linkID, "no mix rows for the off-network link")
check(setequal(sums$linkID, 1:5), "every road link has a mix")
check(all(table(lm$linkID[lm$linkID != 5]) == length(st)), "default links carry all vehicle types")
# Default mix on road type 5: weights car 3e6*0.25, truck 1e6*0.5 (same month, day, hour factors) -> 0.6 / 0.4
l1 = lm %>% filter(linkID == 1)
check(abs(l1$sourceTypeHourFraction[l1$sourceTypeID == 21] - 0.6) < 1e-9, "default car share, road type 5")
check(abs(l1$sourceTypeHourFraction[l1$sourceTypeID == 62] - 0.4) < 1e-9, "default truck share, road type 5")
l3 = lm %>% filter(linkID == 3)
check(abs(l3$sourceTypeHourFraction[l3$sourceTypeID == 21] - 1.5 / 1.75) < 1e-9, "default car share, road type 4")
# User mix kept for link 5
l5 = lm %>% filter(linkID == 5)
check(nrow(l5) == 2 && abs(l5$sourceTypeHourFraction[l5$sourceTypeID == 21] - 0.9) < 1e-9, "user mix kept for covered link")

# Speeds. Road type 5: car v = 0.5*20 + 0.5*60 = 40, truck v = 5. Mix 0.6 / 0.4.
v_car = 40; v_truck = 5
hand = round(1 / (0.6 / v_car + 0.4 / v_truck), 2)
check(abs(lk$linkAvgSpeed[lk$linkID == 1] - hand) < 1e-9, paste0("default speed is the harmonic value ", hand))
check(lk$linkAvgSpeed[lk$linkID == 2] == 25, "user speed kept")
# Road type 4: car v = 60, truck v = 60 -> 60
check(abs(lk$linkAvgSpeed[lk$linkID == 3] - 60) < 1e-9, "default speed, road type 4")
check(abs(lk$linkAvgSpeed[lk$linkID == 4] - 20) < 1e-9, "drive-schedule link gets the schedule mean")
# Link 5 has a user mix 0.9 / 0.1: its speed comes from that mix
hand5 = round(1 / (0.9 / v_car + 0.1 / v_truck), 2)
check(abs(lk$linkAvgSpeed[lk$linkID == 5] - hand5) < 1e-9, "default speed uses the user's mix")

# Drive schedule passed through
check(nrow(ds) == 3 && all(ds$grade == 0), "drive schedule written")
# Notes
check(any(grepl("^link 1 linkAvgSpeed$", notes$item) & grepl("mph from avgspeeddistribution", notes$detail)), "speed note")
check(any(grepl("^link 4 linkAvgSpeed$", notes$item) & grepl("drive schedule", notes$detail)), "schedule speed note")
check(any(notes$item == "vehicle mix, links 1, 2, 3, 4" & notes$source == "default"), "default mix note")
check(any(notes$item == "vehicle mix, links 5" & notes$source == "user"), "user mix note")

# No drive schedule file, no _ file
B = new_bucket(base_link[c(1, 3, 6), ])
run(B)
check(!file.exists(paste0(B, "/_driveschedulesecondlink.csv")), "no drive schedule file when none given")

# 3. The checks ####
bad = function(...){ l = base_link[c(1, 6), ]; mod = list(...); for(n in names(mod)){ l[[n]][1] = mod[[n]] }; l }
chk_link = function(link, pattern, what, ...){
  B = new_bucket(link, ...)
  fails_with(adapt_link(rs, B), pattern, what)
}
chk_link(base_link[, c("linkID", "roadTypeID", "linkLength")], "link.csv needs column linkVolume", "missing column")
chk_link(base_link[0, ], "link.csv has no rows", "no rows")
chk_link(bad(linkID = 0), "linkID 0 is not a positive whole number", "linkID zero")
chk_link(bad(linkID = 1.5), "is not a positive whole number", "linkID fraction")
chk_link(bind_rows(base_link[1, ], base_link[1, ] %>% mutate(linkLength = 1)), "linkID 1 is repeated", "repeated linkID")
chk_link(bad(roadTypeID = 3), "link 1 roadTypeID 3 is not in the runspec", "road type not in runspec")
chk_link(bind_rows(base_link[6, ], base_link[6, ] %>% mutate(linkID = 7)), "more than one link", "two off-network links")
chk_link(bad(linkLength = -1), "link 1 has a negative linkLength", "negative length")
chk_link(bad(linkVolume = -5), "link 1 has a negative linkVolume", "negative volume")
chk_link(bad(linkAvgSpeed = -5), "link 1 has a negative linkAvgSpeed", "negative speed")
chk_link(bad() %>% mutate(countyID = 99999), paste0("countyID 99999 is not ", geoid), "wrong county")
chk_link(bad() %>% mutate(zoneID = 5), paste0("zoneID 5 is not ", geoid * 10), "wrong zone")
chk_link(bad(linkLength = NA), "link 1 has no linkLength", "blank length")
chk_link(bad(linkVolume = NA), "link 1 has no linkVolume", "blank volume (aadt is ignored)")
chk_link(bad(linkVolume = NA) %>% mutate(aadt = 20000), "link 1 has no linkVolume", "blank volume with aadt")
# The runspec selects road types 1, 4 and 5: a link table with no road type 4 link is refused
chk_link(base_link[c(1, 6), ], "runspec road type 4 has no link in link.csv", "runspec road type without a link")

# The mix and schedule checks need a good _link.csv
B = new_bucket(base_link[c(1, 3, 6), ])
adapt_link(rs, B)
write_csv(data.frame(linkID = 9, sourceTypeID = 21, sourceTypeHourFraction = 1), paste0(B, "/linksourcetypehour.csv"))
fails_with(adapt_linksourcetypehour(rs, B), "not in link.csv", "mix for unknown link")
# Shares must each be between 0 and 1, even when they sum to 1
write_csv(data.frame(linkID = 1, sourceTypeID = c(21, 31), sourceTypeHourFraction = c(1.2, -0.2)), paste0(B, "/linksourcetypehour.csv"))
fails_with(adapt_linksourcetypehour(rs, B), "vehicle mix for link 1 has a share outside 0 to 1", "negative share in a mix that sums to 1")
write_csv(data.frame(linkID = 6, sourceTypeID = 21, sourceTypeHourFraction = 1), paste0(B, "/linksourcetypehour.csv"))
fails_with(adapt_linksourcetypehour(rs, B), "has rows for off-network link 6", "mix for off-network link")
write_csv(data.frame(linkID = 1, sourceTypeID = 99, sourceTypeHourFraction = 1), paste0(B, "/linksourcetypehour.csv"))
fails_with(adapt_linksourcetypehour(rs, B), "sourceTypeID 99 not in the runspec", "mix with unknown vehicle type")
write_csv(data.frame(linkID = 1, sourceTypeID = c(21, 62), sourceTypeHourFraction = c(0.5, 0.4)), paste0(B, "/linksourcetypehour.csv"))
fails_with(adapt_linksourcetypehour(rs, B), "vehicle mix for link 1 sums to 0.9, not 1", "mix does not sum to 1")
file.remove(paste0(B, "/linksourcetypehour.csv"))

write_csv(data.frame(linkID = 9, secondID = 1, speed = 5), paste0(B, "/driveschedulesecondlink.csv"))
fails_with(adapt_driveschedulesecondlink(rs, B), "not in link.csv", "schedule for unknown link")
write_csv(data.frame(linkID = 6, secondID = 1, speed = 5), paste0(B, "/driveschedulesecondlink.csv"))
fails_with(adapt_driveschedulesecondlink(rs, B), "off-network link 6", "schedule for off-network link")
write_csv(data.frame(linkID = 1, secondID = c(1, 1), speed = c(5, 6)), paste0(B, "/driveschedulesecondlink.csv"))
fails_with(adapt_driveschedulesecondlink(rs, B), "repeats secondID 1", "repeated secondID")
write_csv(data.frame(linkID = 1, secondID = 0, speed = 5), paste0(B, "/driveschedulesecondlink.csv"))
fails_with(adapt_driveschedulesecondlink(rs, B), "is not a positive whole number", "secondID zero")
write_csv(data.frame(linkID = 1, secondID = 1, speed = NA_real_), paste0(B, "/driveschedulesecondlink.csv"))
fails_with(adapt_driveschedulesecondlink(rs, B), "has no speed", "blank schedule speed")
write_csv(data.frame(linkID = 1, secondID = 1, speed = -1), paste0(B, "/driveschedulesecondlink.csv"))
fails_with(adapt_driveschedulesecondlink(rs, B), "negative speed", "negative schedule speed")

# Default mix errors
B = new_bucket(base_link[c(1, 3, 6), ])
file.remove(paste0(B, "/_sourcetypeyearvmt.csv"))
fails_with(adapt_link(rs, B), "default vehicle mix needs sourcetypeyearvmt; give linksourcetypehour.csv", "no sourcetypeyearvmt")
B = new_bucket(base_link[c(1, 3, 6), ])
write_csv(data.frame(yearID = 2022, sourceTypeID = st, VMT = 0), paste0(B, "/_sourcetypeyearvmt.csv"))
fails_with(adapt_link(rs, B), "no default vehicle mix for road type 4; give linksourcetypehour.csv", "zero weights")

# 4. Result ####
unlink(root, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n"); cat(paste0(" - ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS\n")
