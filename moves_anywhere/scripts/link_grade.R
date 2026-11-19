# link_grade.R ################################################################
#
# What:      road grade for project-scale links, derived from federal elevation data
# Does:      links_grade sends one request per link to the USGS 3DEP ImageServer getSamples (the link's
#            line as an Esri polyline, one sample per 25 m), and sets linkAvgGrade (percent, signed along
#            the geometry) = (median of the last three elevations - median of the first three) / the
#            length they span, (n-3)/(n-1) of the link, x 100. Sets 0 with source "default" and a reason when the link is under 200 m, a
#            end-to-end grade disagrees with the least-squares slope through all samples by over 3 points (an end on a bridge, cut or off the road),
#            the request fails twice, or the response has no usable elevations. Caps at +/- 12.
# Limits:    An odd elevation at one END of a short link may not be caught (the fitted line follows it).
#            The grade is the link's average, so a hill inside a long link is flattened.
# Called by: the link builder (task_links.R); not part of a county run
# Reads:     https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/getSamples
#            (keyless, federal), or whatever the fetch argument returns in tests
# Writes:    save_dir/NNN_*.json and save_dir/requests.csv, through links_get (link_sources.R)
# Needs:     jsonlite; curl (via links_get); scripts/link_sources.R sourced first
# Never:     sampleDistance (it is in degrees for a WGS84 geometry)
###############################################################################

# 1. Settings ####

LINKS_ELEV_URL = "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/getSamples"
LINKS_GRADE_MIN_M = 200       # shorter links are not graded (vertical error over the run)
LINKS_GRADE_CAP = 12          # percent, plus or minus
LINKS_GRADE_DISAGREE = 3      # percentage points: end-to-end grade against the fitted line
LINKS_GRADE_NOTE_STEP_M = 10  # a step this big mid-link is noted, not rejected
LINKS_GRADE_SPACING_M = 25
LINKS_GRADE_URL_MAX = 1800    # characters of the whole GET URL
MILE_M = 1609.344

# 2. Geometry helpers ####

#' Great-circle length of a lon/lat line, in metres
#' @param xy numeric matrix, columns lon and lat (WGS84)
links_haversine_m = function(xy){
  if(nrow(xy) < 2){ return(0) }
  r = 6371008.8
  rad = pi / 180
  la1 = xy[-nrow(xy), 2] * rad; la2 = xy[-1, 2] * rad
  dla = la2 - la1
  dlo = (xy[-1, 1] - xy[-nrow(xy), 1]) * rad
  a = sin(dla / 2)^2 + cos(la1) * cos(la2) * sin(dlo / 2)^2
  sum(2 * r * asin(pmin(1, sqrt(a))))
}

#' The Esri polyline JSON for a line
links_polyline_json = function(xy){
  pts = paste0("[", sprintf("%.6f", xy[, 1]), ",", sprintf("%.6f", xy[, 2]), "]", collapse = ",")
  paste0("{\"paths\":[[", pts, "]],\"spatialReference\":{\"wkid\":4326}}")
}

#' Thin the interior vertices evenly (first and last kept) until the encoded geometry fits
#' @param xy lon/lat matrix
#' @param max_chars most characters the URL-encoded polyline JSON may take
#' @return list(xy, thinned) with thinned TRUE when vertices were dropped
links_thin_geometry = function(xy, max_chars){
  enc = function(m){ nchar(utils::URLencode(links_polyline_json(m), reserved = TRUE)) }
  if(enc(xy) <= max_chars || nrow(xy) <= 2){ return(list(xy = xy, thinned = FALSE)) }
  n = nrow(xy)
  while(n > 2){
    n = n - 1
    keep = unique(round(seq(1, nrow(xy), length.out = n)))
    if(enc(xy[keep, , drop = FALSE]) <= max_chars){ break }
  }
  keep = unique(round(seq(1, nrow(xy), length.out = max(n, 2))))
  list(xy = xy[keep, , drop = FALSE], thinned = TRUE)
}

# 3. Elevation response ####

#' Elevations in order along the line from a getSamples response
#' @param txt response body (JSON text)
#' @return numeric vector, NA where the service had no value
links_parse_samples = function(txt){
  js = jsonlite::fromJSON(txt, simplifyVector = FALSE)
  s = js$samples
  if(is.null(s) || length(s) == 0){ return(numeric(0)) }
  id = vapply(s, function(z){ if(is.null(z$locationId)){ NA_real_ } else { as.numeric(z$locationId) } }, 0)
  v = vapply(s, function(z){
    x = suppressWarnings(as.numeric(z$value))
    if(length(x) != 1 || is.na(x) || x < -500){ NA_real_ } else { x }   # NoData comes back as a huge negative or text
  }, 0)
  if(!anyNA(id)){ v = v[order(id)] }   # locationId is the order along the line
  v
}

# 4. One link ####

#' Grade of one link; returns list(grade, source, detail, rise)
links_grade_one = function(xy, length_m, save_dir, fetch = NULL, wait = 5, max_disagree = LINKS_GRADE_DISAGREE){
  out = function(g, src, det, rise = NA_real_, fit = NA_real_){ list(grade = g, source = src, detail = det, rise = rise, fit = fit) }
  if(is.na(length_m) || length_m < LINKS_GRADE_MIN_M){ return(out(0, "default", "link under 200 m")) }
  if(is.null(xy) || nrow(xy) < 2){ return(out(0, "default", "no geometry")) }
  notes = character(0)
  glen = links_haversine_m(xy)
  if(glen > 0 && abs(glen - length_m) / length_m > 0.2){
    notes = c(notes, sprintf("table length %.0f m, geometry %.0f m; grade over table length", length_m, glen))
  }
  n = min(200, max(5, round(length_m / LINKS_GRADE_SPACING_M)))
  base = paste0(LINKS_ELEV_URL, "?geometryType=esriGeometryPolyline&sampleCount=", n,
                "&returnFirstValueOnly=true&f=json&geometry=")
  th = links_thin_geometry(xy, LINKS_GRADE_URL_MAX - nchar(base))
  if(th$thinned){ notes = c(notes, sprintf("geometry thinned to %d of %d vertices", nrow(th$xy), nrow(xy))) }
  q = list(geometry = links_polyline_json(th$xy), geometryType = "esriGeometryPolyline",
           sampleCount = n, returnFirstValueOnly = "true", f = "json")
  txt = tryCatch(links_get(LINKS_ELEV_URL, query = q, save_dir = save_dir, fetch = fetch, wait = wait),
                 error = function(e){ NULL })
  if(is.null(txt)){ return(out(0, "default", paste(c("request failed twice", notes), collapse = "; "))) }
  v = tryCatch(links_parse_samples(txt), error = function(e){ numeric(0) })
  if(length(v) < 6 || anyNA(v)){
    return(out(0, "default", paste(c("elevation response unusable (missing samples or no data)", notes), collapse = "; ")))
  }
  # the two end medians sit at samples 2 and n-1, so they span (n-3)/(n-1) of the link
  n_s = length(v)
  g = (stats::median(utils::tail(v, 3)) - stats::median(utils::head(v, 3))) / (length_m * (n_s - 3) / (n_s - 1)) * 100
  rise = g * length_m / 100
  x = seq(0, length_m, length.out = length(v))
  fit = unname(stats::cov(x, v) / stats::var(x) * 100)
  if(abs(g - fit) > max_disagree){
    return(out(0, "default", paste(c(sprintf("profile irregular: end-to-end %.1f%% against fitted %.1f%% (bridge, cut, or samples off the road)", g, fit), notes),
                                   collapse = "; "), rise, fit))
  }
  step = max(abs(diff(v)))
  if(step > LINKS_GRADE_NOTE_STEP_M){ notes = c(notes, sprintf("note: step of %.0f m mid-link", step)) }
  if(abs(g) > LINKS_GRADE_CAP){
    notes = c(sprintf("capped at %d", LINKS_GRADE_CAP), notes)
    g = sign(g) * LINKS_GRADE_CAP
  }
  out(g, "derived", paste(notes, collapse = "; "), rise, fit)
}

# 5. All links ####

#' Add grade columns to a link table
#' @param links data frame: linkID, linkLength (miles), geometry (list-column of lon/lat matrices)
#' @param save_dir folder for the saved responses and requests.csv
#' @param fetch NULL for the network, or function(url) -> list(status, body) for tests
#' @param wait seconds before the one retry on a 5xx
#' @param max_disagree percentage points the end-to-end grade may differ from the fitted slope
#' @return links with linkAvgGrade, grade_source, grade_detail, grade_rise_m, grade_fit
links_grade = function(links, save_dir, fetch = NULL, wait = 5, max_disagree = LINKS_GRADE_DISAGREE){
  res = lapply(seq_len(nrow(links)), function(i){
    links_grade_one(links$geometry[[i]], links$linkLength[i] * MILE_M, save_dir, fetch, wait, max_disagree)
  })
  links$linkAvgGrade = vapply(res, function(r){ r$grade }, 0)
  links$grade_source = vapply(res, function(r){ r$source }, "")
  links$grade_detail = vapply(res, function(r){ r$detail }, "")
  links$grade_rise_m = vapply(res, function(r){ r$rise }, 0)
  links$grade_fit = vapply(res, function(r){ r$fit }, 0)
  links
}
