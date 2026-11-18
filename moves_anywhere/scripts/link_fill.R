# link_fill.R #################################################################
#
# What:      fill the uncounted roads of a place with the county's remainder traffic (project scale)
# Does:      HPMS gives a daily count (aadt) on most roads but on few local streets. For each MOVES road
#            type r (2 to 5) links_fill computes, for the run's hour,
#              V[r] the county's vehicle-miles from the county tables (month, day, hour, road type shares),
#              C[r] the vehicle-miles already on counted HPMS sections (F[r] x sum(aadt x length)),
#              R[r] = V[r] - C[r] the remainder (0 and a flag "remainder_negative" when counted > county).
#            The unrestricted road types (3 and 5) get one "remainder" link each: length
#            min(uncounted miles in the place, 0.5 x default speed), volume = place remainder / length,
#            grade 0. The restricted types (2 and 4) are never filled; a positive gap is printed as
#            "unplaced". Rule and test cases: docs/audit/project_scale_2026-11/sources/local_roads_fill.md
# Uncounted miles of the place (the share of the county remainder the place gets, Rb = R x Ub / U):
#            - a county place: U is the county's own uncounted miles, from the saved statistics response
#              (Ub = U, so the place gets all of R);
#            - a box place: Ub is summed from the "uncounted" attribute of links_build() (the sections
#              the builder fetched for the box); U is still the county's, from the statistics response.
# Switch:    fill = FALSE, or the environment variable MA_FILL_REMAINDER=false: no links are added; V, C
#            and R are still computed and printed.
# Called by: the link builder (task_links.R), after links_build() and links_volume()
# Reads:     through project_read: the county tables (_sourcetypeyearvmt, _monthvmtfraction,
#            _dayvmtfraction, _hourvmtfraction, _roadtypedistribution, _avgspeeddistribution) and the
#            default monthofanyyear and dayofanyweek tables; two HPMS outStatistics requests for the
#            county (counted vehicle-miles and miles; uncounted miles), through links_get()
# Writes:    nothing but the saved responses and requests.csv of links_get; returns the links with the
#            remainder rows appended and attributes fill (table by road type), summary (text lines),
#            sources
# Needs:     adapt_link.R (link_default_mix, link_default_speed), link_volume.R (links_hour_share),
#            link_sources.R (links_get, links_resolve_hpms), link_build.R (links_road_type, links_empty);
#            project_functions.R, adapt_functions.R; dplyr, jsonlite, tibble
###############################################################################

# 1. Settings ####

LINKS_FILL_MAX_HOURS = 0.5   # a remainder link is at most half an hour long at the default speed
LINKS_FILL_FILLED = c(3L, 5L)   # unrestricted road types
LINKS_FILL_TOL = 1e-9        # relative size below which V - C is noise

# 2. The county's vehicle-miles and the per-aadt factor ####

#' V[r] (vehicle-miles in the run's hour) and F[r] (hourly vehicle-miles per unit aadt) by road type
#' V[r] = k x sum_s vmt x roadtypevmtfraction x month x day x hour, k = 7 / noOfDays / noOfRealDays
#' F[r] = 365 x links_hour_share(): the plan's hourly volume formula per unit aadt, default mix
#' @param roadtypes road types 2 to 5 of the run
#' @param spec result of project_spec()
#' @param BUCKET inputs folder
#' @param .runspec path to the run's runspec (XML)
#' @return tibble roadTypeID, V, F
links_fill_basis = function(roadtypes, spec, BUCKET = "inputs", .runspec = "EPA_MOVES_Model/rs_custom.xml"){
  vmt = project_read("sourcetypeyearvmt", .runspec, BUCKET, default = FALSE, spec = spec)
  month = project_read("monthvmtfraction", .runspec, BUCKET, spec = spec)
  day = project_read("dayvmtfraction", .runspec, BUCKET, spec = spec)
  hour = project_read("hourvmtfraction", .runspec, BUCKET, spec = spec)
  road = project_read("roadtypedistribution", .runspec, BUCKET, spec = spec)
  days = project_read("monthofanyyear", .runspec, BUCKET, spec = spec)$noofdays[1]
  real = project_read("dayofanyweek", .runspec, BUCKET, spec = spec)$noofrealdays[1]
  if(is.null(days) || is.na(days) || days <= 0){ stop(paste0("no noOfDays for month ", spec$month[1])) }
  if(is.null(real) || is.na(real) || real <= 0){ stop(paste0("no noOfRealDays for day ", spec$day[1])) }

  w = expand.grid(roadTypeID = sort(unique(roadtypes)), sourceTypeID = spec$sourcetypes) %>%
    dplyr::left_join(by = "sourceTypeID", y = vmt %>%
      dplyr::select(sourceTypeID = sourcetypeid, vmt) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = "sourceTypeID", y = month %>%
      dplyr::select(sourceTypeID = sourcetypeid, monthvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = day %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, dayvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = hour %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, hourvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = road %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, roadtypevmtfraction) %>% dplyr::distinct()) %>%
    dplyr::mutate(weight = vmt * monthvmtfraction * dayvmtfraction * hourvmtfraction * roadtypevmtfraction,
                  weight = ifelse(is.na(weight), 0, weight))
  tp = tapply(w$weight, w$roadTypeID, sum)
  ids = as.integer(dimnames(tp)[[1]])
  V = (7 / days / real) * as.numeric(tp)

  share = links_hour_share(roadtypes, spec, BUCKET, .runspec)
  dplyr::tibble(roadTypeID = ids, V = V, F = 365 * share$hour_share[match(ids, share$roadTypeID)])
}

# 3. The county's HPMS statistics ####

#' Parse one outStatistics response (JSON text) into a tibble f_system, urban_id and the statistics
#' @param txt response text
links_fill_parse_stats = function(txt){
  j = jsonlite::fromJSON(txt, simplifyVector = FALSE)
  if(!is.null(j$error)){ stop(paste0("statistics request failed: ", j$error$message)) }
  ft = j$features
  num = function(v){ if(is.null(v)){ NA_real_ } else { as.numeric(v) } }
  col = function(name){ vapply(ft, function(f){ num(f$attributes[[name]]) }, 0) }
  out = dplyr::tibble(f_system = col("f_system"), urban_id = col("urban_id"),
                      vehmi = col("vehmi"), miles = col("miles"))
  out$roadTypeID = links_road_type(out$f_system, out$urban_id)
  out
}

#' Two requests: counted sections (aadt x length, length) and uncounted sections (length) of a county,
#' facility_type 1 and 2 only (type 6 is the non-inventory direction, already in the other direction's aadt)
#' @param service result of links_resolve_hpms()
#' @param county county code without the state (109 for Tompkins)
#' @param save_dir folder for the saved responses
#' @param fetch fetch function for tests, NULL = curl
#' @return list(counted, uncounted), each a tibble from links_fill_parse_stats()
links_fill_stats = function(service, county, save_dir, fetch = NULL){
  stat = function(where, stats){
    txt = links_get(paste0(service$url, "/query"),
                    query = list(where = where, outStatistics = as.character(jsonlite::toJSON(stats, auto_unbox = TRUE)),
                                 groupByFieldsForStatistics = "f_system,urban_id", f = "json"),
                    save_dir = save_dir, fetch = fetch)
    links_fill_parse_stats(txt)
  }
  cc = paste0("county_id=", as.integer(county))
  list(
    counted = stat(paste0(cc, " AND aadt>0 AND facility_type IN (1,2)"), list(
      list(statisticType = "sum", onStatisticField = "aadt*section_length", outStatisticFieldName = "vehmi"),
      list(statisticType = "sum", onStatisticField = "section_length", outStatisticFieldName = "miles"))),
    uncounted = stat(paste0(cc, " AND (aadt IS NULL OR aadt=0) AND facility_type IN (1,2)"), list(
      list(statisticType = "sum", onStatisticField = "section_length", outStatisticFieldName = "miles"))))
}

# 4. The rule, per road type ####

#' The remainder and the remainder link of each road type
#' @param roadtypes road types to report (2 to 5)
#' @param V,C,U,Ub named numeric vectors (names = road types): county vehicle-miles in the hour, counted
#'   vehicle-miles in the hour, county uncounted miles, uncounted miles in the place
#' @param v function(road type) -> default speed in mph (called only for a road type that gets a link)
#' @param fill FALSE: no link is made, V, C and R are still computed
#' @return tibble roadTypeID, V, C, R, flag, gap, gap_pct, U, Ub, Rb, unplaced, link (logical),
#'   link_length, link_volume, speed
links_fill_core = function(roadtypes, V, C, U, Ub, v, fill = TRUE){
  rows = lapply(roadtypes, function(r){
    k = as.character(r)
    raw = V[[k]] - C[[k]]
    flag = NA_character_; gap = NA_real_; gap_pct = NA_real_
    if(abs(raw) <= LINKS_FILL_TOL * max(V[[k]], 1)){ R = 0 }
    else if(raw < 0){
      R = 0; flag = "remainder_negative"; gap = raw; gap_pct = 100 * raw / V[[k]]
    } else { R = raw }
    unplaced = 0; Rb = 0; link = FALSE; L = NA_real_; vol = NA_real_; speed = NA_real_
    if(!r %in% LINKS_FILL_FILLED){
      unplaced = R                                   # restricted: never filled
    } else if(U[[k]] <= 0){
      unplaced = R                                   # nothing uncounted to put it on
    } else {
      Rb = R * Ub[[k]] / U[[k]]
      if(fill && Rb > 0 && Ub[[k]] > 0){
        speed = v(r)
        L = min(Ub[[k]], LINKS_FILL_MAX_HOURS * speed)
        vol = Rb / L
        link = TRUE
      }
    }
    dplyr::tibble(roadTypeID = as.integer(r), V = V[[k]], C = C[[k]], R = R, flag = flag, gap = gap,
                  gap_pct = gap_pct, U = U[[k]], Ub = Ub[[k]], Rb = Rb, unplaced = unplaced, link = link,
                  link_length = L, link_volume = vol, speed = speed)
  })
  dplyr::bind_rows(rows)
}

# 5. The summary text ####

#' Lines for link_summary.txt
#' @param tab result of links_fill_core()
#' @param fill whether the fill was on
#' @param box_counted optional tibble roadTypeID, miles, vehmi: counted links of the box
links_fill_summary = function(tab, fill, box_counted = NULL){
  f = function(x, d = 1){ ifelse(is.na(x), "-", format(round(x, d), nsmall = d, trim = TRUE, big.mark = "")) }
  out = paste0("Local-road remainder fill: ", ifelse(fill, "on", "off (no remainder links written)"))
  for(i in seq_len(nrow(tab))){
    a = tab[i, ]
    out = c(out, paste0("  road type ", a$roadTypeID, ": county V ", f(a$V), ", C ", f(a$C), ", R ", f(a$R),
                        " veh-mi/h; uncounted miles in county ", f(a$U), ", in place ", f(a$Ub),
                        "; place remainder Rb ", f(a$Rb),
                        ifelse(isTRUE(a$link), paste0("; remainder link ", f(a$link_length, 2), " mi at ",
                                                      f(a$link_volume, 1), " veh/h"), ""),
                        ifelse(!is.na(a$flag), paste0("; FLAG ", a$flag, ": gap ", f(a$gap), " veh-mi/h (", f(a$gap_pct), "% of V)"), ""),
                        ifelse(a$unplaced > 0, paste0("; unplaced ", f(a$unplaced), " veh-mi/h"), "")))
  }
  if(!is.null(box_counted) && nrow(box_counted) > 0){
    for(i in seq_len(nrow(tab))){
      b = box_counted[box_counted$roadTypeID == tab$roadTypeID[i], ]
      if(nrow(b) == 1){
        out = c(out, paste0("  road type ", tab$roadTypeID[i], " in the place: counted ", f(b$miles), " mi, ",
                            f(b$vehmi), " veh-mi/h"))
      }
    }
    rb = sum(tab$Rb[tab$link]); cv = sum(box_counted$vehmi)
    if(rb + cv > 0){
      out = c(out, paste0("  remainder share of the place's traffic: ", f(100 * rb / (rb + cv)), "%"))
    }
  }
  out
}

# 6. Fill the links ####

#' Append the remainder links to a link table
#' @param links links frame from links_build() (and links_volume(), for the box's counted traffic)
#' @param place box c(west, south, east, north) or a 5-digit county FIPS string
#' @param state two-letter state (picks the HPMS layer)
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder holding the county tables
#' @param save_dir folder for the saved statistics responses and requests.csv
#' @param fetch fetch function for tests, NULL = curl
#' @param fill FALSE, or MA_FILL_REMAINDER=false, switches the fill off
#' @param spec result of project_spec(); read from .runspec when NULL
#' @param county 5-digit county FIPS; default the runspec's county
#' @param listing service listing for the resolver (tests); NULL = request it live
#' @param speed function(road type) -> default speed; NULL = link_default_speed() on the default mix
#' @return links with remainder rows appended (direction "remainder", no geometry); attributes fill
#'   (links_fill_core table), summary (text lines) and sources (rows added for the remainder links)
links_fill = function(links, place, state, .runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs",
                      save_dir, fetch = NULL, fill = TRUE, spec = NULL, county = NULL, listing = NULL,
                      speed = NULL){
  if(is.null(spec)){ spec = project_spec(.runspec) }
  if(tolower(Sys.getenv("MA_FILL_REMAINDER")) == "false"){ fill = FALSE }
  rts = sort(intersect(spec$roadtypes, 2:5))
  if(is.null(county)){ county = sprintf("%05d", as.integer(spec$geoid[1])) }
  if(is.character(place)){ county = place }

  basis = links_fill_basis(rts, spec, BUCKET, .runspec)
  rs = links_resolve_hpms(state, listing = listing, year = spec$year[1])
  st = links_fill_stats(rs, as.integer(substr(county, 3, 5)), save_dir, fetch)

  by_rt = function(df, col){ x = tapply(df[[col]], df$roadTypeID, sum); setNames(as.numeric(x[as.character(rts)]), rts) }
  zero = function(x){ x[is.na(x)] = 0; x }
  A = zero(by_rt(st$counted, "vehmi"))
  U = zero(by_rt(st$uncounted, "miles"))
  V = setNames(basis$V[match(rts, basis$roadTypeID)], rts)
  C = setNames(basis$F[match(rts, basis$roadTypeID)] * A, rts)
  if(is.character(place)){
    Ub = U
  } else {
    un = attr(links, "uncounted")
    Ub = setNames(rep(0, length(rts)), rts)
    if(!is.null(un) && nrow(un) > 0){
      m = tapply(un$miles, un$roadTypeID, sum)
      Ub[names(m)[names(m) %in% names(Ub)]] = m[names(m) %in% names(Ub)]
    }
  }

  get_speed = function(r){
    if(!is.null(speed)){ return(speed(r)) }
    mix = link_default_mix(r, spec, BUCKET, .runspec)
    pseudo = dplyr::tibble(linkID = as.numeric(r), roadTypeID = as.integer(r))
    mix = dplyr::transmute(mix, linkID = as.numeric(roadTypeID), sourceTypeID, sourceTypeHourFraction = share)
    link_default_speed(mix, pseudo, spec, BUCKET, .runspec)$speed[1]
  }
  tab = links_fill_core(rts, V, C, U, Ub, get_speed, fill)

  # Counted traffic of the box, for the summary (a county's counted traffic is C itself)
  box_counted = NULL
  if(is.character(place)){
    box_counted = dplyr::tibble(roadTypeID = rts, miles = by_rt(st$counted, "miles"), vehmi = C) %>% dplyr::mutate(miles = zero(miles))
  } else if(nrow(links) > 0){
    vol = if("linkVolume" %in% names(links)) links$linkVolume else rep(NA_real_, nrow(links))
    box_counted = dplyr::tibble(roadTypeID = links$roadTypeID, miles = ifelse(links$direction == "opposite", 0, links$linkLength),
                                vehmi = zero(vol * links$linkLength)) %>%
      dplyr::group_by(roadTypeID) %>% dplyr::summarise(miles = sum(miles), vehmi = sum(vehmi), .groups = "drop")
  }

  # Remainder rows
  add = tab[tab$link, ]
  src = links_sources_empty()
  if(nrow(add) > 0){
    next_id = if(nrow(links) > 0) max(links$linkID, na.rm = TRUE) else 0L
    rows = dplyr::tibble(
      linkID = as.integer(next_id + seq_len(nrow(add))), route_id = paste0("remainder rt", add$roadTypeID),
      begin_point = 0, end_point = add$link_length, roadTypeID = add$roadTypeID, linkLength = add$link_length,
      aadt = NA_real_, dir_share = 1, direction = "remainder", through_lanes = NA_real_, speed_limit = NA_real_,
      aadt_single_unit = NA_real_, aadt_combination = NA_real_, k_factor = NA_real_, count_year = NA_real_,
      f_system = NA_real_, urban_id = NA_real_, n_sections = NA_integer_,
      linkDescription = paste0("uncounted roads, road type ", add$roadTypeID, " (county remainder)"),
      geometry = lapply(seq_len(nrow(add)), function(i){ matrix(numeric(0), ncol = 2, dimnames = list(NULL, c("lon", "lat"))) }),
      linkVolume = round(add$link_volume, 3), linkAvgSpeed = add$speed, linkAvgGrade = 0)
    src = dplyr::bind_rows(lapply(seq_len(nrow(add)), function(i){
      a = add[i, ]; id = rows$linkID[i]
      dplyr::tibble(linkID = id,
        field = c("linkVolume", "linkLength", "linkAvgSpeed", "linkAvgGrade", "vehicle mix"),
        value = as.character(c(rows$linkVolume[i], a$link_length, a$speed, 0, NA)),
        source = c("default", "derived", "default", "default", "default"),
        detail = c(paste0("county remainder rt", a$roadTypeID, ": V=", round(a$V, 1), " C=", round(a$C, 1), " R=", round(a$R, 1),
                          " veh-mi/h, place share ", round(a$Ub, 2), "/", round(a$U, 2), " mi"),
                   "min(uncounted miles in the place, half the default speed)",
                   "county default speed for the road type", "level road", "county default mix"),
        data_year = spec$year[1])
    }))
    old = attr(links, "sources")
    out = dplyr::bind_rows(links, rows)
    attr(out, "uncounted") = attr(links, "uncounted")
    attr(out, "dropped") = attr(links, "dropped")
    attr(out, "sources") = if(is.null(old)) src else dplyr::bind_rows(old, src)
  } else {
    out = links
  }
  attr(out, "fill") = tab
  attr(out, "summary") = links_fill_summary(tab, fill, box_counted)
  out
}
