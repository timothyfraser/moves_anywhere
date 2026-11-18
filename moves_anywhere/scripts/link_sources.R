# link_sources.R ##############################################################
#
# What:      find and fetch federal road data for the link builder (project scale)
# Does:      links_resolve_hpms picks the HPMS layer to use for a state from the federal service
#            listing: the highest year not above max_year, or the layer whose year is nearest to
#            the run year. links_get makes one GET request, saves the response exactly as received
#            and logs the request in requests.csv. links_fetch_hpms returns the sections of a box
#            or county (paged, 2000 per request) as a tibble with lon/lat matrices.
# Called by: the link builder (task_links.R, link_fetch functions); not part of a county run
# Reads:     https://geo.dot.gov/server/rest/services/Hosted?f=json (the listing; keyless, federal),
#            or a listing handed in by the caller (a parsed list, or the JSON text)
# Writes:    save_dir/NNN_<name>.json (or .geojson) and save_dir/requests.csv, one row per request
# Needs:     jsonlite; tibble; curl (the released image has both); no key of any kind
###############################################################################

# 1. Settings ####

LINKS_HOSTED = "https://geo.dot.gov/server/rest/services/Hosted"

# 2. Resolver ####

#' Fetch a URL once with curl; returns what links_get expects from a fetch function
#' @param url full URL, query string included
links_fetch_curl = function(url){
  h = curl::new_handle(useragent = "R-link-sources", timeout = 120, followlocation = TRUE)
  r = curl::curl_fetch_memory(url, handle = h)
  list(status = as.integer(r$status_code), body = r$content)
}

#' Pick the HPMS layer for a state
#' @param state two-letter postal abbreviation, any case
#' @param max_year highest year allowed; NULL for no limit (ignored when year is given)
#' @param listing the service listing: a parsed list, JSON text, or NULL to request it live
#' @param year run year; when given, the layer whose year is nearest wins (ties: the earlier year)
#' @return list(service, year, url); service is the name exactly as listed, without the folder
links_resolve_hpms = function(state, max_year = NULL, listing = NULL, year = NULL){
  st = toupper(trimws(state))
  if(length(st) != 1 || is.na(st) || !grepl("^[A-Z]{2}$", st)){
    stop(paste0("state must be a two-letter abbreviation, not '", paste(state, collapse = ","), "'"))
  }
  if(is.null(listing)){
    got = links_fetch_curl(paste0(LINKS_HOSTED, "?f=json"))
    if(got$status != 200){ stop(paste0("service listing request failed with status ", got$status)) }
    listing = rawToChar(got$body)
  }
  if(is.character(listing)){ listing = jsonlite::fromJSON(listing, simplifyVector = FALSE) }
  svc = listing$services
  names_all = vapply(svc, function(s){ as.character(s$name) }, "")
  types_all = vapply(svc, function(s){ if(is.null(s$type)){ "FeatureServer" } else { as.character(s$type) } }, "")
  names_all = sub("^Hosted/", "", names_all[types_all == "FeatureServer"])
  # HPMS_FULL_<ST>_<YYYY>, any case; a digit suffix on the state (GA3) is allowed
  pat = paste0("^HPMS_FULL_", st, "[0-9]*_([0-9]{4})$")
  hit = names_all[grepl(pat, names_all, ignore.case = TRUE)]
  if(length(hit) == 0){ stop(paste0("no HPMS layer found for state ", st)) }
  yrs = as.integer(sub(pat, "\\1", hit, ignore.case = TRUE))
  exact = grepl(paste0("^HPMS_FULL_", st, "_"), hit, ignore.case = TRUE)
  if(!is.null(year)){
    pick = order(abs(yrs - as.integer(year)), yrs, !exact, hit)[1]
  } else {
    if(!is.null(max_year)){
      ok = yrs <= as.integer(max_year)
      if(!any(ok)){ stop(paste0("no HPMS layer for state ", st, " in ", max_year, " or earlier")) }
      hit = hit[ok]; yrs = yrs[ok]; exact = exact[ok]
    }
    pick = order(-yrs, !exact, hit)[1]
  }
  list(service = hit[pick], year = yrs[pick],
       url = paste0(LINKS_HOSTED, "/", hit[pick], "/FeatureServer/0"))
}

# 3. Request helper ####

#' One GET, saved and logged; one retry after a wait on a 5xx
#' @param url the endpoint (without the query string when query is given)
#' @param query named list of query parameters, or NULL
#' @param save_dir folder for the saved body and requests.csv (created if missing)
#' @param fetch function(url) returning list(status, body); body is raw or text. NULL = curl
#' @param wait seconds to wait before the retry on a 5xx
#' @return the body as text
links_get = function(url, query = NULL, save_dir, fetch = NULL, wait = 5){
  if(is.null(fetch)){ fetch = links_fetch_curl }
  dir.create(save_dir, showWarnings = FALSE, recursive = TRUE)
  full = url
  if(length(query) > 0){
    q = paste0(names(query), "=", vapply(query, function(v){ utils::URLencode(as.character(v), reserved = TRUE) }, ""),
               collapse = "&")
    full = paste0(url, ifelse(grepl("?", url, fixed = TRUE), "&", "?"), q)
  }
  log_file = file.path(save_dir, "requests.csv")
  n_prev = if(file.exists(log_file)){ nrow(utils::read.csv(log_file, stringsAsFactors = FALSE)) } else { 0L }
  n = n_prev
  # short name: last two path parts before the query, plain characters only
  parts = strsplit(sub("\\?.*$", "", url), "/")[[1]]
  short = gsub("[^A-Za-z0-9]+", "_", paste(utils::tail(parts[nzchar(parts)], 2), collapse = "_"))
  short = substr(short, 1, 40)
  one = function(){
    t0 = Sys.time()
    r = tryCatch(fetch(full), error = function(e){ list(status = 0L, body = charToRaw(conditionMessage(e))) })
    secs = as.numeric(difftime(Sys.time(), t0, units = "secs"))
    body = r$body
    txt = if(is.raw(body)){ rawToChar(body) } else { paste(body, collapse = "\n") }
    n <<- n + 1L
    ext = if(grepl("f=geojson", full, fixed = TRUE)){ "geojson" } else { "json" }
    fname = sprintf("%03d_%s.%s", n, short, ext)
    writeBin(charToRaw(txt), file.path(save_dir, fname))
    row = data.frame(n = n, url = full, time_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                     status = as.integer(r$status), bytes = nchar(txt, type = "bytes"),
                     seconds = round(secs, 3), file = fname, stringsAsFactors = FALSE)
    utils::write.table(row, log_file, sep = ",", row.names = FALSE, col.names = !file.exists(log_file),
                       append = file.exists(log_file), qmethod = "double")
    list(status = as.integer(r$status), text = txt)
  }
  r = one()
  if(r$status >= 500){
    Sys.sleep(wait)
    r = one()
  }
  if(r$status < 200 || r$status >= 300){
    stop(paste0("request failed with status ", r$status, ": ", sub("\\?.*$", "", url)))
  }
  r$text
}

# 4. Fetch HPMS sections ####

# fields asked for; numeric unless listed in LINKS_HPMS_TEXT
LINKS_HPMS_FIELDS = c("route_id", "begin_point", "end_point", "f_system", "urban_id", "facility_type",
                      "through_lanes", "aadt", "aadt_single_unit", "aadt_combination", "k_factor",
                      "dir_factor", "speed_limit", "section_length", "data_year")
LINKS_HPMS_TEXT = "route_id"

#' The where clause for a county
#' The layer's county field is county_id: a SmallInteger holding the 3-digit county code as a number
#' (Tompkins NY 36109 = 109); verified on NY, TX and WY 2025 (tests/fixtures/links/hpms_fields_notes.md)
#' @param fips five-digit county FIPS string; the state part is not used (the layer is one state)
links_county_where = function(fips){
  if(length(fips) != 1 || is.na(fips) || !grepl("^[0-9]{5}$", fips)){
    stop("a county place must be a 5-digit FIPS string")
  }
  paste0("county_id=", as.integer(substr(fips, 3, 5)))
}

#' Parse one GeoJSON page of sections into a data frame
#' A MultiLineString keeps its parts joined in order into one lon/lat matrix; parts says how many.
#' @param txt GeoJSON text
#' @return data frame with the fields (lower-case), parts, and list-column geometry
links_parse_sections = function(txt){
  j = jsonlite::fromJSON(txt, simplifyVector = FALSE)
  ft = j$features
  n = length(ft)
  num = function(v){ if(is.null(v)){ NA_real_ } else { as.numeric(v) } }
  out = list()
  for(f in LINKS_HPMS_FIELDS){
    col = lapply(seq_len(n), function(i){ ft[[i]]$properties[[f]] })
    if(f %in% LINKS_HPMS_TEXT){
      out[[f]] = vapply(col, function(v){ if(is.null(v)){ NA_character_ } else { as.character(v) } }, "")
    } else {
      out[[f]] = vapply(col, num, 0)
    }
  }
  mat = function(coords){
    if(length(coords) == 0){ return(matrix(numeric(0), ncol = 2, dimnames = list(NULL, c("lon", "lat")))) }
    m = matrix(unlist(lapply(coords, function(p){ as.numeric(p[1:2]) })), ncol = 2, byrow = TRUE)
    colnames(m) = c("lon", "lat")
    m
  }
  geom = lapply(ft, function(f){
    g = f$geometry
    if(is.null(g) || is.null(g$coordinates)){ return(list(m = mat(list()), parts = 0L)) }
    if(identical(g$type, "MultiLineString")){
      list(m = mat(unlist(g$coordinates, recursive = FALSE)), parts = length(g$coordinates))
    } else {
      list(m = mat(g$coordinates), parts = 1L)
    }
  })
  df = tibble::as_tibble(out)
  df$parts = vapply(geom, function(g){ g$parts }, 0L)
  df$geometry = lapply(geom, function(g){ g$m })
  df
}

#' Fetch the HPMS sections for a place
#' @param place box c(west, south, east, north) in WGS84, or a 5-digit county FIPS string
#' @param state two-letter state (picks the layer)
#' @param year run year; nearest layer year wins (see links_resolve_hpms); NULL = use max_year rule
#' @param max_year highest layer year allowed
#' @param save_dir folder for the saved responses and requests.csv
#' @param fetch function(url) -> list(status, body) for tests; NULL = curl
#' @param page_size features per request (the service limit is 2000)
#' @param listing service listing handed to the resolver (tests); NULL = request it live
#' @return tibble, one row per section, with attributes service and year
links_fetch_hpms = function(place, state, year = NULL, max_year = NULL, save_dir, fetch = NULL,
                            page_size = 2000L, listing = NULL){
  rs = links_resolve_hpms(state, max_year = max_year, listing = listing, year = year)
  base = list(outFields = paste(LINKS_HPMS_FIELDS, collapse = ","), outSR = 4326, f = "geojson",
              orderByFields = "objectid")
  if(is.character(place)){
    base = c(list(where = links_county_where(place)), base)
  } else if(is.numeric(place) && length(place) == 4 && !anyNA(place)){
    base = c(list(where = "1=1", geometry = paste(place, collapse = ","), geometryType = "esriGeometryEnvelope",
                  inSR = 4326, spatialRel = "esriSpatialRelIntersects"), base)
  } else {
    stop("place must be c(west, south, east, north) or a 5-digit county FIPS string")
  }
  pages = list()
  offset = 0L
  repeat{
    q = c(base, list(resultOffset = offset, resultRecordCount = page_size))
    txt = links_get(paste0(rs$url, "/query"), query = q, save_dir = save_dir, fetch = fetch)
    pg = links_parse_sections(txt)
    pages[[length(pages) + 1]] = pg
    if(nrow(pg) < page_size){ break }
    offset = offset + as.integer(page_size)
  }
  out = do.call(rbind, pages)
  attr(out, "service") = rs$service
  attr(out, "year") = rs$year
  out
}
