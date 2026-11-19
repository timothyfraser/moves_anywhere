# test_link_grade.R ###########################################################
#
# What:      Test of scripts/link_grade.R (grade from 3DEP elevation samples).
# Does:      Offline with a fake fetch: the saved profile gives its rise; an end sitting 15 m off the trend is flagged and set
#            to 0, a mid-link dip only adds a note; a 150 m link is set to 0 and makes no request; the cap at 12 applies; the reversed
#            geometry gives the opposite sign; a fetch that fails twice gives 0 with the reason; a long
#            geometry is thinned to fit the URL; a table length that disagrees with the geometry is noted.
#            One live smoke test (East State Street, Ithaca), only when LINKS_LIVE=1.
# Called by: Developer tool and tests/run_gate.sh. Not part of a run.
#            Run from the repository root: Rscript moves_anywhere/tests/test_link_grade.R
# Reads:     moves_anywhere/tests/fixtures/links/elev_3dep_getsamples_polyline.json
# Writes:    temporary folders only
# Exits:     0 and prints PASS; 1 and prints what failed
###############################################################################

source("moves_anywhere/scripts/link_sources.R")
source("moves_anywhere/scripts/link_grade.R")

failures = character(0)
check = function(ok, label){ if(!isTRUE(ok)){ failures <<- c(failures, label) } }

# 1. Helpers ####

tmp = function(){ d = tempfile("grade_"); dir.create(d); d }
n_requests = function(d){
  f = file.path(d, "requests.csv")
  if(file.exists(f)){ nrow(read.csv(f)) } else { 0L }
}
# a getSamples response for a vector of elevations
resp = function(v){
  s = lapply(seq_along(v), function(i){ list(location = list(x = 0, y = 0), locationId = i - 1L, value = sprintf("%.9f", v[i]), rasterId = 1L, resolution = 1L) })
  jsonlite::toJSON(list(samples = s), auto_unbox = TRUE)
}
ok_fetch = function(v, seen = NULL){ function(url){ list(status = 200L, body = charToRaw(as.character(resp(v)))) } }
# an east-west line of about len_m metres at the latitude of Ithaca
line_m = function(len_m, nv = 2){
  dlon = len_m / (111194.9 * cos(42.44 * pi / 180))
  cbind(seq(-76.5, -76.5 + dlon, length.out = nv), 42.44)
}
mk = function(xy, miles = NULL){
  if(is.null(miles)){ miles = links_haversine_m(xy) / MILE_M }
  d = data.frame(linkID = 1L, linkLength = miles)
  d$geometry = list(xy)
  d
}

# 2. The saved profile ####

fx = readLines("moves_anywhere/tests/fixtures/links/elev_3dep_getsamples_polyline.json", warn = FALSE)
fx = paste(fx, collapse = "\n")
fx_fetch = function(url){ list(status = 200L, body = charToRaw(fx)) }
hill = cbind(c(-76.4950, -76.4900, -76.4850, -76.4800), c(42.4394, 42.4386, 42.4378, 42.4372))
v = links_parse_samples(fx)
check(length(v) == 51, "fixture has 51 samples")
# The saved profile stops 24 m short of the end vertex. Its end medians differ by 98.93 m over the
# (n-3)/(n-1) = 48/50 of the link they span, so the rise over the whole link is 98.93 x 50/48 = 103.05 m;
# the documented end-to-end rise of the whole line is 100.16 m (EPQS).
d = tmp()
r = links_grade(mk(hill), d, fetch = fx_fetch)
cat(sprintf("saved East State Street: grade_end %.2f, grade_fit %.2f
", r$linkAvgGrade, r$grade_fit))
check(abs(r$grade_rise_m - 103.05) < 0.5, "saved profile rise within 0.5 m of 103.05")
check(abs(r$grade_rise_m - 100.16) < 3.5, "saved profile rise within 3.5 m of the documented 100.16")
check(r$grade_source == "derived", "saved profile passes with default arguments")
check(r$linkAvgGrade > 7 && r$linkAvgGrade < 8.5, "saved profile grade 7 to 8.5 percent")
check(n_requests(d) == 1, "one request for one link")
u = read.csv(file.path(d, "requests.csv"))$url[1]
check(grepl("sampleCount=50", u, fixed = TRUE), "sampleCount is one per 25 m")
check(!grepl("sampleDistance", u, fixed = TRUE), "never sampleDistance")
check(grepl("returnFirstValueOnly=true", u, fixed = TRUE) && grepl("esriGeometryPolyline", u, fixed = TRUE), "request parameters")

# 3. Plain rules ####

ln = line_m(300, 3)
ramp = 100 + 0.5 * (0:12)                       # 12 steps of 0.5 m over about 300 m
d = tmp()
r = links_grade(mk(ln), d, fetch = ok_fetch(ramp))
check(abs(r$linkAvgGrade - (median(tail(ramp, 3)) - median(head(ramp, 3))) / (links_haversine_m(ln) * 10 / 12) * 100) < 0.01, "ramp grade arithmetic")
check(abs(r$linkAvgGrade - 2) < 0.01 && abs(r$grade_fit - 2) < 0.01, "ramp is exactly 2 percent by both measures")
check(r$linkAvgGrade > 1.5 && r$linkAvgGrade < 2.5 && r$grade_source == "derived" && r$grade_detail == "", "ramp is about 2 percent, derived")
# reversed geometry, same elevations reversed: opposite sign
rev = links_grade(mk(ln[nrow(ln):1, ]), tmp(), fetch = ok_fetch(rev(ramp)))
check(abs(rev$linkAvgGrade + r$linkAvgGrade) < 1e-9 && rev$linkAvgGrade < 0, "reversed geometry gives the opposite sign")
# last three samples 60 m above the trend (a 15 m offset is not caught on a short link): flagged and set to 0
# (on a short link: on a long one the fitted line follows the odd end too, so this rule cannot see it)
ln_short = line_m(220, 3)
odd = 100 + 0.5 * (0:8); odd[7:9] = odd[7:9] + 60
d = tmp()
j = links_grade(mk(ln_short), d, fetch = ok_fetch(odd))
check(j$linkAvgGrade == 0 && j$grade_source == "default" && grepl("profile irregular", j$grade_detail), "end 60 m above trend flagged and set to 0")
# 12 m dip in the middle only: grade kept, note carried
dip = ramp; dip[7] = dip[7] - 12
dp = links_grade(mk(ln), tmp(), fetch = ok_fetch(dip))
check(dp$grade_source == "derived" && abs(dp$linkAvgGrade - r$linkAvgGrade) < 1e-9 && grepl("note: step of 12 m mid-link", dp$grade_detail), "mid-link dip keeps the grade and carries the note")
# 150 m link: default, no request
d = tmp()
s = links_grade(mk(line_m(150)), d, fetch = function(url){ stop("must not be called") })
check(s$linkAvgGrade == 0 && s$grade_source == "default" && s$grade_detail == "link under 200 m", "150 m link set to 0 with reason")
check(n_requests(d) == 0, "150 m link makes no request")
# cap
ln_long = ln
steep = 100 + 4 * (0:12)                         # 4 m per step: 16 percent, on a short link
c1 = links_grade(mk(ln_long), tmp(), fetch = ok_fetch(steep))
check(c1$linkAvgGrade == 12 && c1$grade_source == "derived" && grepl("capped at 12", c1$grade_detail), "cap at +12")
c2 = links_grade(mk(ln_long), tmp(), fetch = ok_fetch(rev(steep)))
check(c2$linkAvgGrade == -12, "cap at -12")
# fetch fails twice
d = tmp()
f = links_grade(mk(ln), d, fetch = function(url){ list(status = 503L, body = charToRaw("busy")) }, wait = 0)
check(f$linkAvgGrade == 0 && f$grade_source == "default" && grepl("request failed twice", f$grade_detail), "two failures: 0 with reason")
check(n_requests(d) == 2, "two failures logged as two requests")
# one failure then success
cnt = 0
flaky = function(url){ cnt <<- cnt + 1; if(cnt == 1){ list(status = 502L, body = charToRaw("x")) } else { list(status = 200L, body = charToRaw(as.character(resp(ramp)))) } }
g = links_grade(mk(ln), tmp(), fetch = flaky, wait = 0)
check(g$grade_source == "derived", "retry after one 502 succeeds")
# no data values
nd = links_grade(mk(ln), tmp(), fetch = ok_fetch(rep(-9999, 13)))
check(nd$linkAvgGrade == 0 && nd$grade_source == "default", "no-data response gives default")
# samples out of order are put in order by locationId
shuf = resp(ramp)
js = jsonlite::fromJSON(as.character(shuf), simplifyVector = FALSE)
js$samples = rev(js$samples)
check(isTRUE(all.equal(links_parse_samples(jsonlite::toJSON(js, auto_unbox = TRUE)), ramp)), "samples sorted by locationId")

# 4. Long geometry and length mismatch ####

lg = line_m(5000, 400)
lg[, 2] = 42.44 + 0.0005 * sin(seq(0, 40, length.out = 400))
seen_url = NULL
sf = function(url){ seen_url <<- url; list(status = 200L, body = charToRaw(as.character(resp(100 + 0.5 * (0:199))))) }
t = links_grade(mk(lg), tmp(), fetch = sf)
check(nchar(seen_url) <= 1900, "long geometry fits the URL")
check(grepl("thinned", t$grade_detail), "thinning is noted")
check(grepl("sampleCount=200", seen_url, fixed = TRUE), "sampleCount capped at 200")
m = links_grade(mk(ln, miles = 2 * links_haversine_m(ln) / MILE_M), tmp(), fetch = ok_fetch(ramp))
check(grepl("table length", m$grade_detail) && m$grade_source == "derived", "length mismatch noted, grade still computed")
check(m$linkAvgGrade < r$linkAvgGrade && m$linkAvgGrade > 0, "mismatch grade uses the table length")

# 5. Live smoke test ####

if(identical(Sys.getenv("LINKS_LIVE"), "1")){
  d = tmp()
  t0 = Sys.time()
  lv = links_grade(mk(hill), d)
  secs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat(sprintf("LIVE East State Street: grade %.2f percent, source %s, detail '%s', rise %.1f m, %.1f s\n",
              lv$linkAvgGrade, lv$grade_source, lv$grade_detail, lv$grade_rise_m, secs))
  check(lv$linkAvgGrade >= 6 && lv$linkAvgGrade <= 10, "live: East State Street grade 6 to 10 percent")
} else {
  cat("SKIP live smoke test: set LINKS_LIVE=1 to call the USGS elevation service\n")
}

if(length(failures) > 0){
  cat("FAIL:\n", paste0(" - ", failures, collapse = "\n"), "\n", sep = "")
  quit(status = 1)
}
cat("PASS test_link_grade\n")
