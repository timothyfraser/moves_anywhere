# test_task_links.R ###########################################################
#
# What:      Offline test of the link builder's command (task_links.R).
# Does:      Runs links_task() on a temp folder with a project run file, a fake fetch (saved listing,
#            the 40-section Ithaca box, the saved elevation profile, the saved Tompkins statistics) and
#            fake county tables; checks every output, the sources, project_check, adapt_link and
#            adapt_linksourcetypehour, the clean-up of _*.csv, and each refusal.
# Called by: run by hand from the repository root: Rscript moves_anywhere/tests/test_task_links.R
# Reads:     moves_anywhere/inputs_project/rs_custom.xml, moves_anywhere/scripts/*.R,
#            moves_anywhere/tests/fixtures/links/*
# Writes:    a temp folder only (removed at the end)
# Exits:     0 and prints PASS, or prints what failed and exits 1
###############################################################################

suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(stringr) })
TASK_LINKS_TEST = TRUE
for(f in c("adapt_functions.R", "project_functions.R", "adapt_link.R", "link_sources.R", "link_build.R",
           "link_volume.R", "link_mix.R", "link_grade.R", "link_fill.R", "task_links.R")){
  source(file.path("moves_anywhere/scripts", f))
}

# FAKE DATA: default tables (31-day month, 5 real weekdays, three speed bins)
get_table = function(tablename){
  if(tablename == "monthofanyyear"){ return(data.frame(monthID = 1:12, monthName = month.name, noOfDays = 31)) }
  if(tablename == "dayofanyweek"){ return(data.frame(dayID = c(2, 5), dayName = c("Weekend", "Weekdays"), noOfRealDays = c(2, 5))) }
  if(tablename == "avgspeedbin"){ return(data.frame(avgSpeedBinID = 1:3, avgBinSpeed = c(20, 40, 70))) }
  stop(paste0("test has no default table ", tablename))
}

failures = character(0)
check = function(ok, what){ if(!isTRUE(ok)){ failures <<- c(failures, what) } }
fx = "moves_anywhere/tests/fixtures/links/"
slurp = function(f){ paste(readLines(paste0(fx, f), warn = FALSE), collapse = "\n") }
listing = slurp("hosted_listing.json")
box = slurp("hpms_ny2025_ithaca_box_40_access.geojson")
elev = slurp("elev_3dep_getsamples_polyline.json")
stats = jsonlite::fromJSON(paste0(fx, "hpms_ny2025_tompkins_stats.json"), simplifyVector = FALSE)
as_text = function(x){ as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA)) }

fetch = function(url){
  u = utils::URLdecode(url)
  body = if(grepl("outStatistics", u, fixed = TRUE)){
    if(grepl("IS NULL", u, fixed = TRUE)) as_text(stats$uncounted) else as_text(stats$counted)
  } else if(grepl("FeatureServer/0/query", u, fixed = TRUE)){ box
  } else if(grepl("Hosted?f=json", u, fixed = TRUE) || grepl("Hosted\\?", u) ){ listing
  } else { elev }
  list(status = 200L, body = charToRaw(body))
}

# FAKE DATA: county tables written by the fake prepare (flat shares; only cars and combination trucks drive)
fake_prepare = function(.runspec, BUCKET){
  spec = project_spec(.runspec)
  st = spec$sourcetypes; rts = 2:5
  write_csv(data.frame(yearID = spec$year[1], sourceTypeID = st, VMT = ifelse(st == 21, 4e8, ifelse(st == 62, 2.5e8, 0))),
            paste0(BUCKET, "/_sourcetypeyearvmt.csv"))
  write_csv(data.frame(sourceTypeID = st, monthID = spec$month[1], monthVMTFraction = 1 / 12), paste0(BUCKET, "/_monthvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, monthID = spec$month[1], roadTypeID = rts, dayID = c(2, 5)) %>%
              mutate(dayVMTFraction = ifelse(dayID == 5, 0.75, 0.25)), paste0(BUCKET, "/_dayvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = rts, dayID = 5, hourID = 1:24) %>%
              mutate(hourVMTFraction = 1 / 24), paste0(BUCKET, "/_hourvmtfraction.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = rts) %>%
              mutate(roadTypeVMTFraction = c(`2` = 0.02, `3` = 0.4, `4` = 0.08, `5` = 0.5)[as.character(roadTypeID)]),
            paste0(BUCKET, "/_roadtypedistribution.csv"))
  write_csv(expand.grid(sourceTypeID = st, roadTypeID = rts, hourDayID = spec$hourday, avgSpeedBinID = 2:3) %>%
              mutate(avgSpeedFraction = 0.5), paste0(BUCKET, "/_avgspeeddistribution.csv"))
  dir(BUCKET, pattern = "^_.*\\.csv$")
}
fake_vmt = function(y){ 1e9 + (y - 2020) * 1e7 }   # FAKE DATA: county miles by year

root = tempfile("task_links_")
dir.create(root)
new_folder = function(name, project = TRUE){
  B = file.path(root, name); dir.create(B)
  file.copy("moves_anywhere/inputs_project/rs_custom.xml", file.path(B, "rs_custom.xml"))
  if(!project){
    x = readLines(file.path(B, "rs_custom.xml")); x = sub("value=\"PROJECT\"", "value=\"DEFAULT\"", x, fixed = TRUE)
    writeLines(x, file.path(B, "rs_custom.xml"))
  }
  B
}
run = function(B, ...){
  args = list(place = "-76.51,42.435,-76.49,42.445", state = "NY", max_links = 40, fill = TRUE, overwrite = FALSE,
              BUCKET = B, .runspec = file.path(B, "rs_custom.xml"), fetch = fetch, prepare = fake_prepare,
              vmt_year = fake_vmt, wait = 0)
  a = modifyList(args, list(...))
  out = tryCatch(do.call(links_task, a), links_refusal = function(e){ list(status = 1L, reason = conditionMessage(e)) })
  out
}

# 1. A full build ####
B = new_folder("ok")
writeLines("x", file.path(B, "_keepme.csv"))   # an earlier _ file must survive
before = dir(B)
res = run(B)
if(!identical(res$status, 0L)){ cat("build did not return 0:", res$reason, "\n") }
check(identical(res$status, 0L), paste0("the build returns 0 (got ", res$reason, ")"))
for(f in c("link.csv", "links.geojson", "link_sources.csv", "link_summary.txt", "sources", "sources/requests.csv")){
  check(file.exists(file.path(B, f)), paste0(f, " exists"))
}
lk = read_csv(file.path(B, "link.csv"), show_col_types = FALSE)
check(identical(names(lk), LINKS_COLS), "link.csv columns")
src = read_csv(file.path(B, "link_sources.csv"), show_col_types = FALSE)
for(col in setdiff(LINKS_COLS, "linkID")){
  ids = lk$linkID[!is.na(lk[[col]])]
  miss = setdiff(ids, src$linkID[src$field == col])
  check(length(miss) == 0, paste0("every ", col, " value has a source row (missing links ", paste(miss, collapse = ","), ")"))
}
gj = jsonlite::fromJSON(file.path(B, "links.geojson"), simplifyVector = FALSE)
check(length(gj$features) == nrow(lk), "one geojson feature per link")
rem = lk$linkID[grepl("remainder", lk$linkDescription)]
isnull = vapply(gj$features, function(f){ is.null(f$geometry) }, TRUE)
check(all(isnull == (lk$linkID %in% rem)), "remainder links (and only they) have null geometry")
left = setdiff(dir(B, pattern = "^_.*\\.csv$"), "_keepme.csv")
check(length(left) == 0, paste0("no _*.csv left behind (found ", paste(left, collapse = ", "), ")"))
check(file.exists(file.path(B, "_keepme.csv")) && readLines(file.path(B, "_keepme.csv")) == "x", "an earlier _ file is kept")
cat(readLines(file.path(B, "link_summary.txt")), sep = "\n")

# project_check and the adapters accept the folder (road types set to those of the links, as B7 step 3)
rs = file.path(B, "rs_custom.xml")
sp = project_spec(rs)
rtx = sort(unique(lk$roadTypeID))
ok_rs = tryCatch({ project_runspec(rs, sp$month[1], sp$day[1], sp$hour[1], rtx); TRUE }, error = function(e){ cat("project_runspec:", conditionMessage(e), "\n"); FALSE })
pc = tryCatch({ project_check(rs, B); "ok" }, error = function(e){ conditionMessage(e) })
check(pc == "ok", paste0("project_check passes (got ", pc, ")"))
fake_prepare(rs, B)
ad = tryCatch({ adapt_link(rs, B); adapt_linksourcetypehour(rs, B); "ok" }, error = function(e){ conditionMessage(e) })
check(ad == "ok", paste0("adapt_link and adapt_linksourcetypehour accept the folder (got ", ad, ")"))

# 2. Refusals ####
refuse = function(res, pattern, what){
  check(identical(res$status, 1L) && grepl(pattern, res$reason, fixed = TRUE), paste0(what, " (got ", res$reason, ")"))
  cat(what, ": ", res$reason, "\n", sep = "")
}
B2 = new_folder("notproject", project = FALSE)
refuse(run(B2), "not a project run file", "refusal: not a project run file")
refuse(run(B), "link.csv already exists", "refusal: link.csv exists without OVERWRITE")
B3 = new_folder("state")
refuse(run(B3, state = "ZZ"), "no HPMS layer for state ZZ", "refusal: unknown state")
B4 = new_folder("empty")
empty_fetch = function(url){
  if(grepl("FeatureServer/0/query", utils::URLdecode(url), fixed = TRUE) && !grepl("outStatistics", utils::URLdecode(url), fixed = TRUE)){
    return(list(status = 200L, body = charToRaw('{"type":"FeatureCollection","features":[]}')))
  }
  fetch(url)
}
refuse(run(B4, fetch = empty_fetch), "no roads with traffic counts found in this place (0 road sections returned)", "refusal: no counted section")
msg_nc = tryCatch(links_refuse(links_no_counts_reason(0L)), links_refusal = function(e){ conditionMessage(e) })
check(identical(msg_nc, "links: no roads with traffic counts found in this place (0 road sections returned). Try a larger box or give a link.csv."), paste0("no-counts message text (got ", msg_nc, ")"))
check(lengths(regmatches(msg_nc, gregexpr("links: ", msg_nc, fixed = TRUE))) == 1L && !grepl("counted section", msg_nc, fixed = TRUE), "no-counts message has one links: prefix and no jargon")
B5 = new_folder("many")
refuse(run(B5, max_links = 3), "more than MAX_LINKS 3", "refusal: too many links")
check(length(dir(B5, pattern = "^_.*\\.csv$")) == 0, "a refusal after the county tables leaves no _*.csv")
# links_main: exit status and the summary line
Sys.setenv(PLACE = "-76.51,42.435,-76.49,42.445", STATE = "NY", MAX_LINKS = "40")
st1 = suppressMessages(links_main(BUCKET = B2, .runspec = file.path(B2, "rs_custom.xml"), fetch = fetch, prepare = fake_prepare))
check(st1 == 1L && grepl("^links: ", readLines(file.path(B2, "link_summary.txt"))[1]), "links_main returns 1 and writes the reason")
Sys.unsetenv(c("PLACE", "STATE", "MAX_LINKS"))

# 3. Result ####
unlink(root, recursive = TRUE)
if(length(failures) > 0){
  cat("FAIL\n", paste0("- ", failures, collapse = "\n"), "\n")
  quit(status = 1)
}
cat("PASS: test_task_links.R\n")
