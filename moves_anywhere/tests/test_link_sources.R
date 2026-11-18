# test_link_sources.R #########################################################
#
# What:      Test of scripts/link_sources.R (resolver, request helper, HPMS section fetch).
# Does:      Checks links_resolve_hpms on the saved federal listing (NY, AL, GA, max_year, nearest
#            year, unknown state) and on a small literal listing with the odd names; checks links_get
#            with fake fetch functions (success, one 5xx then success, two failures, saved files and
#            requests.csv).
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_link_sources.R
# Reads:     moves_anywhere/tests/fixtures/links/hosted_listing.json, hpms_ny2025_ithaca_box_40.geojson,
#            hpms_ny2025_ithaca_box_40_access.geojson (one live request only when LINKS_LIVE=1)
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

source("moves_anywhere/scripts/link_sources.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }
msg = function(expr){ tryCatch({ expr; "no error" }, error = function(e){ conditionMessage(e) }) }

# 1. Resolver on the saved listing ####

lst = readLines("moves_anywhere/tests/fixtures/links/hosted_listing.json", warn = FALSE)
lst = paste(lst, collapse = "\n")
ny = links_resolve_hpms("NY", listing = lst)
check(identical(ny$service, "HPMS_FULL_NY_2025"), "NY service")
check(identical(ny$year, 2025L), "NY year")
check(identical(ny$url, "https://geo.dot.gov/server/rest/services/Hosted/HPMS_FULL_NY_2025/FeatureServer/0"), "NY url")
check(identical(links_resolve_hpms("ny", listing = lst)$service, "HPMS_FULL_NY_2025"), "lower-case state")
check(identical(links_resolve_hpms("NY", max_year = 2023, listing = lst)$service, "HPMS_FULL_NY_2023"), "NY max 2023")
check(grepl("GeoIntersections", links_resolve_hpms("AL", listing = lst)$service) == FALSE, "intersection layers skipped")
check(identical(links_resolve_hpms("AL", max_year = 2019, listing = lst)$service, "HPMS_Full_AL_2019"), "AL mixed case")
check(identical(links_resolve_hpms("GA", max_year = 2023, listing = lst)$service, "HPMS_FULL_GA3_2023"), "GA3 suffix")
check(identical(links_resolve_hpms("NY", year = 2021, listing = lst)$year, 2020L), "nearest 2021: tie goes to 2020")
check(identical(links_resolve_hpms("NY", year = 2022, listing = lst)$service, "HPMS_FULL_NY_2022"), "nearest exact year")
check(identical(links_resolve_hpms("NY", year = 2030, listing = lst)$year, 2025L), "nearest above the range")
check(identical(links_resolve_hpms("NY", year = 2010, listing = lst)$year, 2020L), "nearest below the range")
check(grepl("ZZ", msg(links_resolve_hpms("ZZ", listing = lst))), "unknown state names the state")
check(grepl("NY", msg(links_resolve_hpms("NY", max_year = 2001, listing = lst))), "no year low enough names the state")
check(grepl("two-letter", msg(links_resolve_hpms("New York", listing = lst))), "bad state text")

# 2. Resolver on a literal listing with the odd names ####

mk = function(nm){ list(services = lapply(nm, function(x){ list(name = paste0("Hosted/", x), type = "FeatureServer") })) }
odd = mk(c("HPMS_Full_AL_2019", "HPMS_FULL_GA3_2023", "HPMS_FULL_GA_2022", "HPMS_AL_GeoIntersections_2019",
           "hpms_full_tx_2021"))
check(identical(links_resolve_hpms("AL", listing = odd)$service, "HPMS_Full_AL_2019"), "literal AL")
check(identical(links_resolve_hpms("GA", listing = odd)$service, "HPMS_FULL_GA3_2023"), "literal GA3")
check(identical(links_resolve_hpms("GA", max_year = 2022, listing = odd)$service, "HPMS_FULL_GA_2022"), "literal GA max 2022")
check(identical(links_resolve_hpms("TX", listing = odd)$service, "hpms_full_tx_2021"), "literal lower-case service")
tie = mk(c("HPMS_FULL_GA3_2023", "HPMS_FULL_GA_2023"))
check(identical(links_resolve_hpms("GA", listing = tie)$service, "HPMS_FULL_GA_2023"), "same year: exact state name first")

# 3. links_get ####

made = character(0)
mkdir = function(){ d = tempfile("ls_"); made <<- c(made, d); d }
body_ok = '{"ok": true}'

d1 = mkdir()
got = links_get("https://example.test/a/b/query", list(where = "county_id=109", f = "geojson"), d1,
                fetch = function(url){ list(status = 200L, body = charToRaw(body_ok)) })
check(identical(got, body_ok), "success body")
check(file.exists(file.path(d1, "001_b_query.geojson")), "saved file name")
check(identical(readLines(file.path(d1, "001_b_query.geojson"), warn = FALSE), body_ok), "saved body as received")
lg = read.csv(file.path(d1, "requests.csv"), stringsAsFactors = FALSE)
check(identical(names(lg), c("n", "url", "time_utc", "status", "bytes", "seconds", "file")), "requests.csv columns")
check(nrow(lg) == 1 && lg$status == 200 && grepl("where=county_id%3D109&f=geojson", lg$url, fixed = TRUE), "requests.csv row")

# one 5xx, then success: body returned, two requests logged
d2 = mkdir(); calls = 0L
got = links_get("https://example.test/svc/query", NULL, d2, wait = 0,
                fetch = function(url){ calls <<- calls + 1L
                  if(calls == 1L){ list(status = 503L, body = charToRaw("busy")) } else { list(status = 200L, body = charToRaw(body_ok)) } })
lg = read.csv(file.path(d2, "requests.csv"), stringsAsFactors = FALSE)
check(identical(got, body_ok) && calls == 2L, "5xx then success")
check(identical(lg$status, c(503L, 200L)) && identical(lg$n, 1:2), "two requests logged")
check(length(list.files(d2, pattern = "^00[12]_")) == 2, "two files saved")

# two 5xx: stops with the status
d3 = mkdir(); calls = 0L
m = msg(links_get("https://example.test/svc/query", NULL, d3, wait = 0,
                  fetch = function(url){ calls <<- calls + 1L; list(status = 502L, body = charToRaw("bad")) }))
check(grepl("502", m) && calls == 2L, "two 5xx stops with status")

# 4xx: no retry, stops with the status
d4 = mkdir(); calls = 0L
m = msg(links_get("https://example.test/svc/query", NULL, d4, wait = 0,
                  fetch = function(url){ calls <<- calls + 1L; list(status = 404L, body = charToRaw("no")) }))
check(grepl("404", m) && calls == 1L, "4xx stops, no retry")

# counter continues in a folder that already has a log
got = links_get("https://example.test/svc/query", NULL, d2, wait = 0,
                fetch = function(url){ list(status = 200L, body = charToRaw(body_ok)) })
check(nrow(read.csv(file.path(d2, "requests.csv"))) == 3 && file.exists(file.path(d2, "003_svc_query.json")), "counter continues")

# 4. links_fetch_hpms, offline ####

fx = paste(readLines("moves_anywhere/tests/fixtures/links/hpms_ny2025_ithaca_box_40.geojson", warn = FALSE), collapse = "
")
box = c(-76.55, 42.40, -76.44, 42.48)
d5 = mkdir()
sec = links_fetch_hpms(box, "NY", save_dir = d5, listing = lst,
                       fetch = function(url){ list(status = 200L, body = charToRaw(fx)) })
check(nrow(sec) == 40, "fixture parses to 40 rows")
check(all(c(LINKS_HPMS_FIELDS, "parts", "geometry") %in% names(sec)), "fixture has the listed fields")
check(is.character(sec$route_id) && all(vapply(sec[LINKS_HPMS_FIELDS[-1]], is.numeric, TRUE)), "field types")
check(is.numeric(sec$aadt) && any(!is.na(sec$aadt)) && any(is.na(sec$aadt)), "aadt numeric with NA kept")
check(is.list(sec$geometry) && is.matrix(sec$geometry[[1]]) && ncol(sec$geometry[[1]]) == 2 &&
        identical(colnames(sec$geometry[[1]]), c("lon", "lat")), "geometry matrices")
check(nrow(sec$geometry[[1]]) == 2 && abs(sec$geometry[[1]][1, "lon"] + 76.5006) < 0.001, "geometry values")
check(identical(attr(sec, "service"), "HPMS_FULL_NY_2025") && identical(attr(sec, "year"), 2025L), "service and year attributes")
lg5 = read.csv(file.path(d5, "requests.csv"), stringsAsFactors = FALSE)
check(nrow(lg5) == 1 && grepl("geometryType=esriGeometryEnvelope", lg5$url, fixed = TRUE) &&
        grepl("geometry=-76.55%2C42.4%2C-76.44%2C42.48", lg5$url, fixed = TRUE) &&
        grepl("resultOffset=0", lg5$url, fixed = TRUE) && grepl("orderByFields=objectid", lg5$url, fixed = TRUE), "box request")
check(grepl("%2Caccess_control", lg5$url, fixed = TRUE), "outFields asks for access_control")
check(is.numeric(sec$access_control) && all(is.na(sec$access_control)), "old fixture without access_control parses to NA")
fa = links_parse_sections(paste(readLines("moves_anywhere/tests/fixtures/links/hpms_ny2025_ithaca_box_40_access.geojson", warn = FALSE), collapse = "\n"))
check(nrow(fa) == 40 && all(fa$access_control %in% 1:3), "access fixture: access_control 1-3 on all 40 sections")

# county where clause: county_id is a number holding the 3-digit code
check(identical(links_county_where("36109"), "county_id=109"), "county where Tompkins")
check(identical(links_county_where("48001"), "county_id=1"), "county where leading zeros")
check(grepl("5-digit", msg(links_county_where("109"))), "bad county text")
d6 = mkdir()
urls = character(0)
sec6 = links_fetch_hpms("36109", "NY", save_dir = d6, listing = lst,
                        fetch = function(url){ urls <<- c(urls, url); list(status = 200L, body = charToRaw(fx)) })
check(grepl("where=county_id%3D109", urls[1], fixed = TRUE) && !grepl("geometry=", urls[1], fixed = TRUE), "county request")
check(grepl("5-digit|box", msg(links_fetch_hpms(c(1, 2), "NY", save_dir = d6, listing = lst))), "bad place")

# fake two-page source: page size 3; page 1 has 3 features, page 2 has 2; two requests, five rows
mkfeat = function(i){
  list(type = "Feature", geometry = list(type = "LineString", coordinates = list(c(-76 + i/100, 42), c(-76 + i/100, 42.01))),
       properties = list(route_id = paste0("r", i), aadt = 100 * i, f_system = 3))
}
page = function(ids){ as.character(jsonlite::toJSON(list(type = "FeatureCollection", features = lapply(ids, mkfeat)), auto_unbox = TRUE, null = "null")) }
d7 = mkdir(); offs = integer(0)
sec7 = links_fetch_hpms(box, "NY", save_dir = d7, listing = lst, page_size = 3L,
  fetch = function(url){
    o = as.integer(sub(".*resultOffset=([0-9]+).*", "\\1", url)); offs <<- c(offs, o)
    list(status = 200L, body = charToRaw(if(o == 0L){ page(1:3) } else { page(4:5) }))
  })
check(nrow(sec7) == 5 && identical(sec7$route_id, paste0("r", 1:5)), "two pages joined in order")
check(identical(offs, c(0L, 3L)), "offsets 0 then 3")
check(nrow(read.csv(file.path(d7, "requests.csv"))) == 2, "two requests logged")
check(all(is.na(sec7$k_factor)) && is.numeric(sec7$k_factor), "absent field is numeric NA")
# a full last page asks once more and then stops on the empty page
d8 = mkdir(); offs = integer(0)
sec8 = links_fetch_hpms(box, "NY", save_dir = d8, listing = lst, page_size = 3L,
  fetch = function(url){ o = as.integer(sub(".*resultOffset=([0-9]+).*", "\\1", url)); offs <<- c(offs, o)
    list(status = 200L, body = charToRaw(if(o == 0L){ page(1:3) } else { page(integer(0)) })) })
check(nrow(sec8) == 3 && identical(offs, c(0L, 3L)), "full page then empty page")

# MultiLineString: parts joined in order, parts counted
ml = '{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"MultiLineString","coordinates":[[[-76,42],[-76,42.1]],[[-76,42.1],[-76.1,42.1]]]},"properties":{"route_id":"m","aadt":5}},{"type":"Feature","geometry":null,"properties":{"route_id":"n"}}]}'
pm = links_parse_sections(ml)
check(nrow(pm) == 2 && pm$parts[1] == 2L && nrow(pm$geometry[[1]]) == 4 && pm$geometry[[1]][3, "lon"] == -76, "multilinestring joined")
check(pm$parts[2] == 0L && nrow(pm$geometry[[2]]) == 0, "null geometry is an empty matrix")

# 5. Live smoke test (skipped unless LINKS_LIVE=1) ####

if(identical(Sys.getenv("LINKS_LIVE"), "1")){
  d9 = mkdir(); t0 = Sys.time()
  live = links_fetch_hpms(box, "NY", save_dir = d9)
  secs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat("live Ithaca box:", nrow(live), "sections in", secs, "s,", attr(live, "service"), "
")
  check(nrow(live) >= 1500 && nrow(live) <= 2500, "live Ithaca box returns 1500 to 2500 sections (measured 1961; the brief said 900 to 1200)")
  cat("live access_control:", paste(names(table(live$access_control, useNA = "ifany")), table(live$access_control, useNA = "ifany"), sep = "=", collapse = " "), "\n")
  check(any(live$access_control %in% 1) && any(live$access_control %in% 3), "live box has access_control 1 and 3")
  source("moves_anywhere/scripts/link_build.R")
  rt_new = links_road_type(live$f_system, live$urban_id, live$access_control)
  rt_old = links_road_type(live$f_system, live$urban_id)
  cat("live sections by road type, new rule:", paste(names(table(rt_new)), table(rt_new), sep = "=", collapse = " "),
      "| class-only rule:", paste(names(table(rt_old)), table(rt_old), sep = "=", collapse = " "), "\n")
  Ll = links_build(live)
  cat("live links by road type:", paste(names(table(Ll$roadTypeID)), table(Ll$roadTypeID), sep = "=", collapse = " "), "\n")
} else {
  cat("SKIP live smoke test (set LINKS_LIVE=1 to run it)
")
}

unlink(made, recursive = TRUE)

if(length(failures) > 0){
  cat("FAIL\n", paste0("  ", failures, collapse = "\n"), "\n", sep = "")
  quit(status = 1)
}
cat("PASS\n")
