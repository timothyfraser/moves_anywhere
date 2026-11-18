# test_link_fill.R ############################################################
#
# What:      Offline test of the local-road remainder fill (link_fill.R).
# Does:      Checks the nine literal cases of docs/audit/project_scale_2026-11/sources/local_roads_fill.md
#            section 6 on the pure core (links_fill_core, links_fill_summary), the same-basis case through
#            links_fill() with literal county tables and a fake HPMS statistics response, and the Tompkins
#            county with the saved statistics response (fixtures/links/hpms_ny2025_tompkins_stats.json):
#            remainder plus counted vehicle-miles equals the county's figure on road types 3 and 5.
# Called by: run by hand from the repository root: Rscript moves_anywhere/tests/test_link_fill.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml, moves_anywhere/scripts/*.R,
#            moves_anywhere/tests/fixtures/links/hpms_ny2025_tompkins_stats.json, hosted_listing.json
# Writes:    a temp folder only (removed at the end)
# Exits:     0 and prints PASS, or prints what failed and exits 1
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(stringr) })
source("moves_anywhere/scripts/adapt_functions.R")
source("moves_anywhere/scripts/project_functions.R")
source("moves_anywhere/scripts/adapt_link.R")
source("moves_anywhere/scripts/link_volume.R")
source("moves_anywhere/scripts/link_sources.R")
source("moves_anywhere/scripts/link_build.R")
source("moves_anywhere/scripts/link_fill.R")

# July has 31 days here (the specification's case 1); weekday = 5 real days
get_table = function(tablename){
  if(tablename == "monthofanyyear"){ return(data.frame(monthID = 1:12, monthName = month.name, noOfDays = 31)) }
  if(tablename == "dayofanyweek"){ return(data.frame(dayID = c(2, 5), dayName = c("Weekend", "Weekdays"), noOfRealDays = c(2, 5))) }
  stop(paste0("test has no default table ", tablename))
}

failures = character(0)
check = function(ok, what){ if(!isTRUE(ok)){ failures <<- c(failures, what) } }
near = function(a, b, rel = 0.001){ isTRUE(all(abs(a - b) <= rel * abs(b))) }
row_of = function(tab, r){ tab[tab$roadTypeID == r, ] }
cap_ok = list()

# 1. The pure core: cases 2 to 6, 8 and 9 ####
core = function(V, C, U, Ub, v, fill = TRUE){
  r = as.character(c(3, 4, 5))
  pick = function(x, r_){ out = setNames(rep(0, 3), r); out[as.character(r_)] = x; out }
  links_fill_core(roadtypes = c(3, 4, 5), V = pick(V$x, V$r), C = pick(C$x, C$r), U = pick(U$x, U$r),
                  Ub = pick(Ub$x, Ub$r), v = function(rt){ v }, fill = fill)
}

# Case 2: V 10000, C 6000, U 400, Ub 40, v 25
t2 = core(list(x = 10000, r = 5), list(x = 6000, r = 5), list(x = 400, r = 5), list(x = 40, r = 5), 25)
a = row_of(t2, 5)
check(near(a$R, 4000) && near(a$Rb, 400), "case 2: R 4000, Rb 400")
check(near(a$link_length, 12.5) && near(a$link_volume, 32), "case 2: length 12.5, volume 32")
check(near(a$link_volume * a$link_length / 25, 16), "case 2: source hours 16 = 400 / 25")
cap_ok[[2]] = a$link_length / 25

# Case 3: Ub 8, v 30
t3 = core(list(x = 10000, r = 5), list(x = 6000, r = 5), list(x = 400, r = 5), list(x = 8, r = 5), 30)
a = row_of(t3, 5)
check(near(a$Rb, 80) && near(a$link_length, 8) && near(a$link_volume, 10), "case 3: Rb 80, length 8, volume 10")
cap_ok[[3]] = a$link_length / 30

# Case 4: counted above the county
t4 = core(list(x = 5000, r = 3), list(x = 5600, r = 3), list(x = 100, r = 3), list(x = 10, r = 3), 40)
a = row_of(t4, 3)
check(a$R == 0 && a$flag == "remainder_negative", "case 4: R 0 and flag remainder_negative")
check(near(a$gap, -600) && near(a$gap_pct, -12), "case 4: gap -600 veh-mi, -12%")
check(!isTRUE(a$link) && is.na(a$link_length), "case 4: no link")

# Case 5: restricted road type is never filled
t5 = core(list(x = 3000, r = 4), list(x = 2500, r = 4), list(x = 50, r = 4), list(x = 5, r = 4), 60)
a = row_of(t5, 4)
check(!isTRUE(a$link) && near(a$unplaced, 500), "case 5: no link on road type 4, unplaced 500")
check(any(grepl("unplaced", links_fill_summary(t5, fill = TRUE))), "case 5: the summary shows unplaced")

# Case 6: nothing uncounted
t6 = core(list(x = 1900, r = 5), list(x = 1000, r = 5), list(x = 0, r = 5), list(x = 0, r = 5), 25)
a = row_of(t6, 5)
check(near(a$R, 900) && !isTRUE(a$link) && near(a$unplaced, 900), "case 6: R 900, no link, unplaced 900")

# Case 8: switch off still prints R
t8 = core(list(x = 10000, r = 5), list(x = 6000, r = 5), list(x = 400, r = 5), list(x = 40, r = 5), 25, fill = FALSE)
check(!any(t8$link), "case 8: no remainder link with fill off")
s8 = links_fill_summary(t8, fill = FALSE)
check(any(grepl("4000", s8)) && any(grepl("off", s8, ignore.case = TRUE)), "case 8: the summary prints R = 4000 and says the fill is off")
check(any(grepl("on", links_fill_summary(t2, fill = TRUE)[1])), "the summary starts with a line on whether the fill was on")

# 2. Case 1 and case 7 through links_fill(): literal county tables, fake statistics ####
root = tempfile("link_fill_")
dir.create(root)
rs = paste0(root, "/rs_custom.xml")
invisible(file.copy("moves_anywhere/inputs_project/rs_custom.xml", rs))
spec = project_spec(rs)

#' Write the county tables for the given source types and road types; vmt = annual miles by source type
new_bucket = function(vmt, rtf, rts){
  B = tempfile("bucket_", tmpdir = root)
  dir.create(B)
  st = as.integer(names(vmt))
  write_csv(data.frame(yearID = 2022, sourceTypeID = st, VMT = as.numeric(vmt)), paste0(B, "/_sourcetypeyearvmt.csv"))
  write_csv(data.frame(sourceTypeID = st, monthID = 7, monthVMTFraction = 1 / 12), paste0(B, "/_monthvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, monthID = 7, roadTypeID = rts, dayID = c(2, 5)) %>%
              mutate(dayVMTFraction = ifelse(dayID == 5, 0.75, 0.25)), paste0(B, "/_dayvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = rts, dayID = 5, hourID = 1:24) %>%
              mutate(hourVMTFraction = 1 / 24), paste0(B, "/_hourvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = rts) %>%
              mutate(roadTypeVMTFraction = unname(rtf[as.character(roadTypeID)])), paste0(B, "/_roadtypedistribution.csv"))
  B
}

#' A fake fetch: serves the counted or the uncounted statistics response by what the request asks for
make_fetch = function(counted, uncounted, seen = NULL){
  function(url){
    if(!is.null(seen)){ seen$urls = c(seen$urls, utils::URLdecode(url)) }
    body = if(grepl("IS NULL", utils::URLdecode(url), fixed = TRUE)) uncounted else counted
    list(status = 200L, body = charToRaw(body))
  }
}
stats_json = function(rows){ jsonlite::toJSON(list(features = lapply(rows, function(r){ list(attributes = r) })), auto_unbox = TRUE) }
listing = paste(readLines("moves_anywhere/tests/fixtures/links/hosted_listing.json", warn = FALSE), collapse = "\n")
none = links_empty()

# Case 1: V[5] = 42.93 veh-mi/h; one counted mile with aadt 1000 gives C[5] = 42.93 and no link
spec1 = spec; spec1$roadtypes = 5L; spec1$sourcetypes = 21L
B1 = new_bucket(c(`21` = 365000), c(`5` = 1), 5)
seen = new.env(); seen$urls = character(0)
fetch1 = make_fetch(stats_json(list(list(f_system = 5, urban_id = 41914, vehmi = 1000, miles = 1))), stats_json(list()), seen)
out1 = links_fill(none, "36109", "NY", rs, B1, file.path(root, "s1"), fetch = fetch1, fill = TRUE,
                  spec = spec1, listing = listing, speed = function(r){ 25 })
f1 = row_of(attr(out1, "fill"), 5)
check(near(f1$V, 42.93, 0.0005), paste0("case 1: V[5] = 42.93 (got ", f1$V, ")"))
check(near(f1$C, f1$V, 1e-9) && f1$R == 0, paste0("case 1: C equals V and R is 0 (got C ", f1$C, " R ", f1$R, ")"))
check(nrow(out1) == 0 && is.null(f1$flag) || (nrow(out1) == 0 && is.na(f1$flag)), "case 1: no remainder link, no flag")

# Case 7: the county request asks for facility_type 1 and 2 only, so the non-inventory direction is not in U
check(any(grepl("facility_type IN (1,2)", seen$urls, fixed = TRUE)), "case 7: requests are limited to facility_type IN (1,2)")
check(all(grepl("facility_type IN (1,2)", seen$urls[grepl("outStatistics", seen$urls, fixed = TRUE)], fixed = TRUE)),
      "case 7: every statistics request carries facility_type IN (1,2)")
check(any(grepl("county_id=109", seen$urls, fixed = TRUE)), "the county field is county_id with the 3-digit code")

# 3. Tompkins with the saved statistics response ####
saved = jsonlite::fromJSON("moves_anywhere/tests/fixtures/links/hpms_ny2025_tompkins_stats.json", simplifyVector = FALSE)
as_text = function(x){ as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA)) }
fetch_t = make_fetch(as_text(saved$counted), as_text(saved$uncounted))

# FAKE DATA: county tables, a flat year (every hour 1/24, weekday 3/4 of the week) that gives Tompkins
# about 1.8 M veh-mi a day, split by road type so that road types 3 and 5 are not fully counted
spect = spec; spect$roadtypes = 2:5; spect$sourcetypes = c(21L, 62L)
Bt = new_bucket(c(`21` = 4.0e8, `62` = 2.57e8), c(`2` = 0.02, `3` = 0.40, `4` = 0.08, `5` = 0.50), 2:5)
speeds = c(`3` = 45, `5` = 25)
outt = links_fill(none, "36109", "NY", rs, Bt, file.path(root, "st"), fetch = fetch_t, fill = TRUE,
                  spec = spect, listing = listing, speed = function(r){ speeds[[as.character(r)]] })
ft = attr(outt, "fill")
# Independent counted vehicle-miles per unit aadt: flat hour share = 1 / 24 / (31 days/7 x 5/0.75...) is the
# plan's formula; here the shares are flat so each aadt-mile gives (1/24) of a day
hourly = function(day_total){ day_total / 24 }
A_of = function(rt){
  s = 0
  for(f in saved$counted$features){
    a = f$attributes
    if(links_road_type(a$f_system, a$urban_id) == rt){ s = s + a$vehmi }
  }
  s
}
# the flat tables give 365 x (1/12) x (7/31) x 0.75 / 5 x (1/24) per aadt = 0.0429 x 1/... computed below
Fflat = 365 * (1 / 12) * (7 / 31) * 0.75 / 5 / 24
Vday = 6.57e8 / 12 * 0.75 / 24 * 7 / 31 / 5     # hourly veh-mi for the whole county, all road types
for(r in c(3, 5)){
  a = row_of(ft, r)
  rtshare = c(`3` = 0.40, `5` = 0.50)[[as.character(r)]]
  check(near(a$V, Vday * rtshare, 1e-9), paste0("Tompkins road type ", r, ": V from the county tables (got ", a$V, ")"))
  check(near(a$C, Fflat * A_of(r), 1e-9), paste0("Tompkins road type ", r, ": C = F x sum(aadt x length) (got ", a$C, ")"))
  check(a$R > 0 && near(a$R + a$C, a$V, 0.01), paste0("Tompkins road type ", r, ": remainder + counted = county within 1%"))
  check(a$U > 0 && near(a$Ub, a$U, 1e-12) && near(a$Rb, a$R, 1e-9), paste0("Tompkins road type ", r, ": a county run gets all of R"))
}
rem = outt[outt$direction == "remainder", ]
check(nrow(rem) == 2 && setequal(rem$roadTypeID, c(3, 5)), "Tompkins: one remainder link each for road types 3 and 5")
check(all(rem$linkDescription == paste0("uncounted roads, road type ", rem$roadTypeID, " (county remainder)")), "remainder link description")
check(all(rem$linkLength / speeds[as.character(rem$roadTypeID)] <= 0.5 + 1e-9), "case 9: length / speed <= 0.5 on every remainder link")
for(i in seq_len(nrow(rem))){
  Rb = row_of(ft, rem$roadTypeID[i])$Rb
  check(near(rem$linkVolume[i] * rem$linkLength[i], Rb, 1e-3), paste0("remainder link ", rem$linkID[i], ": volume x length = Rb"))
}
check(!any(duplicated(outt$linkID)), "link numbers are unique")
check(is.na(row_of(ft, 4)$flag) || row_of(ft, 4)$flag != "x", "road type 4 is reported, not filled")
check(all(c("linkVolume", "linkAvgSpeed", "linkAvgGrade") %in% names(outt)) && all(rem$linkAvgGrade == 0), "remainder rows carry volume, speed and grade 0")
src = attr(outt, "sources")
check(all(src$source[src$linkID %in% rem$linkID & src$field %in% c("linkVolume", "linkAvgSpeed", "linkAvgGrade")] == "default"),
      "remainder values have source default")
check(src$source[src$linkID == rem$linkID[1] & src$field == "linkLength"] == "derived", "remainder linkLength is derived")

# Switch by environment variable
Sys.setenv(MA_FILL_REMAINDER = "false")
off = links_fill(none, "36109", "NY", rs, Bt, file.path(root, "soff"), fetch = fetch_t, fill = TRUE,
                 spec = spect, listing = listing, speed = function(r){ 25 })
Sys.unsetenv("MA_FILL_REMAINDER")
check(nrow(off) == 0 && near(row_of(attr(off, "fill"), 5)$R, row_of(ft, 5)$R, 1e-12), "MA_FILL_REMAINDER=false: no links, R still computed")

# Print the Tompkins remainder
cat("Tompkins remainder (flat FAKE county tables, real HPMS 2025 statistics), vehicle-miles in the hour:\n")
for(r in c(3, 5)){
  a = row_of(ft, r)
  cat(sprintf("  road type %d: V %.1f  C %.1f  R %.1f  share of V %.2f%%  U %.1f mi  link %.2f mi at %.1f veh/h\n",
              r, a$V, a$C, a$R, 100 * a$R / a$V, a$U, a$link_length, a$link_volume))
}
cat(paste0("  ", attr(outt, "summary")), sep = "\n")

# 4. Result ####
unlink(root, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n", paste0("- ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS: test_link_fill.R\n")
