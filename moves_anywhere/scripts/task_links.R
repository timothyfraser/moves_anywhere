# task_links.R ################################################################
#
# What:      the link builder's command (project scale): writes link.csv and its companions from
#            federal road data (HPMS) for a box or a county
# Does:      checks the run file (a project run file), refuses to replace link.csv without OVERWRITE=1,
#            resolves the state's HPMS layer nearest the run year, fetches the sections, builds the
#            links (links_build), their truck-count mix (links_mix), hourly volume (links_volume), grade
#            (links_grade) and the local-road remainder (links_fill), applies the speed rule (the
#            posted limit as a ceiling on the county default speed), and writes the outputs. The county
#            tables the helpers read are made by running only the county adapters they need
#            (links_prepare_county); every _*.csv this run created is removed at the end and any _*.csv
#            that was there before is restored as it was.
# Called by: scripts/launch_links.sh (in the image, from /cat); tests/test_task_links.R (functions only)
# Reads:     environment PLACE ("w,s,e,n" or a 5-digit FIPS), STATE, MAX_LINKS (default 40),
#            MA_FILL_REMAINDER ("false" = no remainder links), OVERWRITE ("1" = replace link.csv);
#            EPA_MOVES_Model/rs_custom.xml; the HPMS and 3DEP services through links_get()
# Writes:    inputs/link.csv, inputs/linksourcetypehour.csv (when any link has truck counts),
#            inputs/links.geojson, inputs/link_sources.csv, inputs/link_summary.txt, inputs/sources/
# Exits:     0 written; 1 refused (one line "links: <reason>" on stderr and in link_summary.txt);
#            2 an unexpected error (message printed)
# Needs:     adapt_functions.R, project_functions.R, adapt_link.R, link_sources.R, link_build.R,
#            link_volume.R, link_mix.R, link_grade.R, link_fill.R; county adapters adapt_from_nei.R,
#            adapt_vmt2.R, adapt_vmtfraction.R, adapt_avgspeeddistribution.R,
#            adapt_roadtypedistribution.R; dplyr, readr, jsonlite, tibble, xml2
###############################################################################

# 1. Settings ####

LINKS_COLS = c("linkID", "roadTypeID", "linkLength", "linkVolume", "linkAvgSpeed", "linkAvgGrade", "linkDescription")
LINKS_MINUTES_NOTE = "about one minute of MOVES per link on this machine: 7 links took 10 minutes, 32 took 31"

# 2. Small helpers ####

#' Signal a refusal (exit status 1) with a one-line reason
links_refuse = function(reason){
  stop(structure(class = c("links_refusal", "error", "condition"),
                 list(message = paste0("links: ", reason), call = NULL)))
}

#' Plain reason for a place with no road section that has a traffic count (the caller adds "links: " once)
links_no_counts_reason = function(n_sections){
  paste0("no roads with traffic counts found in this place (", n_sections, " road sections returned). ",
         "Try a larger box or give a link.csv.")
}

#' PLACE text to a box c(w, s, e, n) or a 5-digit FIPS string
links_parse_place = function(place){
  p = gsub("[[:space:]]", "", as.character(place))
  if(grepl("^[0-9]{5}$", p)){ return(p) }
  v = suppressWarnings(as.numeric(strsplit(p, ",", fixed = TRUE)[[1]]))
  if(length(v) == 4 && !anyNA(v) && v[1] < v[3] && v[2] < v[4]){ return(v) }
  links_refuse(paste0("PLACE must be \"west,south,east,north\" or a 5-digit county FIPS, not '", place, "'"))
}

#' One sources frame with character values
links_src = function(df){
  if(is.null(df) || nrow(df) == 0){
    return(tibble::tibble(linkID = integer(0), field = character(0), value = character(0), source = character(0),
                          detail = character(0), data_year = numeric(0)))
  }
  tibble::tibble(linkID = as.integer(df$linkID), field = as.character(df$field), value = as.character(df$value),
                 source = as.character(df$source), detail = as.character(df$detail),
                 data_year = suppressWarnings(as.numeric(df$data_year)))
}

#' Uncounted sections of the box by road type, without the non-inventory direction (facility_type 6)
links_uncounted = function(sections){
  ac = if("access_control" %in% names(sections)) sections$access_control else NULL
  rt = links_road_type(sections$f_system, sections$urban_id, ac)
  miles = ifelse(is.na(sections$section_length), sections$end_point - sections$begin_point, sections$section_length)
  keep = (is.na(sections$aadt) | sections$aadt <= 0) & (is.na(sections$facility_type) | sections$facility_type != 6)
  d = tibble::tibble(roadTypeID = rt, f_system = sections$f_system, miles = miles)[keep, ]
  d |> dplyr::group_by(roadTypeID, f_system) |>
    dplyr::summarize(sections = dplyr::n(), miles = sum(miles, na.rm = TRUE), .groups = "drop")
}

# 3. County tables ####

#' Run only the county adapters whose tables the link helpers read, in task_adapt.R's order
#' link_default_mix / links_fill_basis need _sourcetypeyearvmt.csv (no default allowed), and read
#' _monthvmtfraction, _dayvmtfraction, _hourvmtfraction, _roadtypedistribution; link_default_speed reads
#' _avgspeeddistribution. monthofanyyear, dayofanyweek and avgspeedbin come from the default database.
#' The adapters write to "inputs" (their own BUCKET), so this runs from /cat with BUCKET = "inputs".
#' @return the _*.csv names in BUCKET after the adapters ran
links_prepare_county = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  if(BUCKET != "inputs"){ stop("the county adapters write to inputs/; run from /cat with BUCKET = \"inputs\"") }
  source("scripts/adapt_from_nei.R")
  source("scripts/adapt_vmt2.R")
  adapt_vmt2(.runspec = .runspec)
  source("scripts/adapt_vmtfraction.R")
  adapt_dayvmtfraction(.runspec = .runspec)
  adapt_hourvmtfraction(.runspec = .runspec)
  adapt_monthvmtfraction(.runspec = .runspec)
  source("scripts/adapt_avgspeeddistribution.R")
  adapt_avgspeeddistribution(.runspec = .runspec)
  source("scripts/adapt_roadtypedistribution.R")
  adapt_roadtypedistribution(.runspec = .runspec)
  dir(BUCKET, pattern = "^_.*\\.csv$")
}

# 4. Writers ####

#' links.geojson: one LineString Feature per link (null geometry for remainder links)
links_write_geojson = function(links, table, path){
  feats = lapply(seq_len(nrow(table)), function(i){
    g = links$geometry[[i]]
    props = lapply(as.list(table[i, ]), function(v){ if(length(v) == 0 || is.na(v)) NULL else v })
    geom = if(is.null(g) || nrow(g) < 2){ NULL } else {
      list(type = "LineString", coordinates = lapply(seq_len(nrow(g)), function(j){ unname(as.numeric(g[j, 1:2])) }))
    }
    list(type = "Feature", geometry = geom, properties = props)
  })
  txt = jsonlite::toJSON(list(type = "FeatureCollection", features = feats), auto_unbox = TRUE, null = "null",
                         digits = NA, na = "null")
  writeLines(txt, path)
}

# 5. The command ####

#' Build and write the link tables
#' @param place PLACE text ("w,s,e,n" or FIPS)
#' @param state two-letter state
#' @param max_links refuse when more links (remainder links included) would be written
#' @param fill FALSE switches the remainder off
#' @param overwrite TRUE allows replacing link.csv
#' @param fetch NULL = network (curl), or function(url) -> list(status, body) for tests
#' @param prepare function(.runspec, BUCKET) that makes the county tables
#' @param vmt_year NULL (links_vmt_year) or function(year) -> county miles, for tests
#' @param wait seconds before the one retry on a 5xx
#' @return list(status = 0, files, summary)
links_task = function(place, state, max_links = 40, fill = TRUE, overwrite = FALSE, BUCKET = "inputs",
                      .runspec = "EPA_MOVES_Model/rs_custom.xml", fetch = NULL, prepare = links_prepare_county,
                      vmt_year = NULL, wait = 5){
  t0 = Sys.time()
  # 5a. Cheap refusals ####
  if(!file.exists(.runspec)){ links_refuse("no rs_custom.xml in the folder") }
  ok = tryCatch(is_project(.runspec), error = function(e){ FALSE })
  if(!isTRUE(ok)){ links_refuse("rs_custom.xml is not a project run file (modeldomain is not PROJECT)") }
  if(file.exists(file.path(BUCKET, "link.csv")) && !isTRUE(overwrite)){
    links_refuse("link.csv already exists; set OVERWRITE=1 (--overwrite) to replace it")
  }
  pl = links_parse_place(place)
  st = toupper(trimws(state))
  if(!grepl("^[A-Z]{2}$", st)){ links_refuse(paste0("STATE must be two letters, not '", state, "'")) }
  max_links = suppressWarnings(as.integer(max_links))
  if(is.na(max_links) || max_links < 1){ links_refuse("MAX_LINKS must be a whole number of at least 1") }
  spec = project_spec(.runspec)
  save_dir = file.path(BUCKET, "sources")

  # 5b. The layer and the sections ####
  listing = links_get(LINKS_HOSTED, query = list(f = "json"), save_dir = save_dir, fetch = fetch, wait = wait)
  rs = tryCatch(links_resolve_hpms(st, listing = listing, year = spec$year[1]),
                error = function(e){ links_refuse(paste0("no HPMS layer for state ", st, " (", conditionMessage(e), ")")) })
  sections = links_fetch_hpms(pl, st, year = spec$year[1], save_dir = save_dir, fetch = fetch, listing = listing)
  links = links_build(sections)
  if(nrow(links) == 0){
    links_refuse(links_no_counts_reason(nrow(sections)))
  }
  # The box's uncounted tally without facility_type 6 (the builder's tally still has them)
  attr(links, "uncounted") = links_uncounted(sections)
  src = links_src(attr(links, "sources"))

  # 5c. County tables: made here, removed at the end; ones already there are restored ####
  before = dir(BUCKET, pattern = "^_.*\\.csv$")
  keep_dir = tempfile("links_keep_")
  dir.create(keep_dir)
  if(length(before) > 0){ file.copy(file.path(BUCKET, before), keep_dir, overwrite = TRUE) }
  on.exit({
    now = dir(BUCKET, pattern = "^_.*\\.csv$")
    unlink(file.path(BUCKET, setdiff(now, before)))
    if(length(before) > 0){ file.copy(file.path(keep_dir, before), BUCKET, overwrite = TRUE) }
    unlink(keep_dir, recursive = TRUE)
  }, add = TRUE)
  prepare(.runspec, BUCKET)

  # 5d. Mix, volume, grade, remainder ####
  mix = links_mix(links, .runspec, BUCKET, spec = spec)
  src = dplyr::bind_rows(src, links_src(attr(mix, "sources")))
  links = links_volume(links, .runspec, BUCKET, spec = spec, vmt_year = vmt_year, mix = mix)
  src = dplyr::bind_rows(src, links_src(attr(links, "sources")))
  uncounted = attr(links_build_attrs <- links, "uncounted")
  links = links_grade(links, save_dir, fetch = fetch, wait = wait)
  src = dplyr::bind_rows(src, tibble::tibble(linkID = as.integer(links$linkID), field = "linkAvgGrade",
                                             value = as.character(links$linkAvgGrade), source = links$grade_source,
                                             detail = links$grade_detail, data_year = NA_real_))
  links$linkAvgSpeed = NA_real_
  attr(links, "sources") = NULL
  attr(links, "uncounted") = attr(links_build_attrs, "uncounted")
  attr(links, "dropped") = attr(links_build_attrs, "dropped")
  filled = links_fill(links, if(is.character(pl)) pl else pl, st, .runspec, BUCKET, save_dir, fetch = fetch,
                      fill = fill, spec = spec, listing = listing)
  added = filled[filled$direction %in% "remainder", ]
  src = dplyr::bind_rows(src, links_src(dplyr::filter(attr(filled, "sources") %||% links_src(NULL), linkID %in% added$linkID)))
  if(nrow(added) > 0){
    src = dplyr::bind_rows(src, tibble::tibble(linkID = as.integer(added$linkID), field = "roadTypeID",
      value = as.character(added$roadTypeID), source = "default", detail = "remainder of an unrestricted road type",
      data_year = spec$year[1]))
  }
  links = filled

  # 5e. Speed rule: the posted limit as a ceiling on the county default speed ####
  road = which(links$direction != "remainder")
  lm = link_mix(links[road, c("linkID", "roadTypeID")],
                if(nrow(mix) > 0) dplyr::select(mix, linkID, sourceTypeID, sourceTypeHourFraction) else NULL,
                spec, BUCKET, .runspec)
  dv = link_default_speed(lm, links[road, ], spec, BUCKET, .runspec)
  for(i in road){
    v = dv$speed[dv$linkID == links$linkID[i]]
    lim = links$speed_limit[i]
    if(length(v) == 1 && !is.na(lim) && lim > 0 && v > lim){
      links$linkAvgSpeed[i] = lim
      src = dplyr::bind_rows(src, tibble::tibble(linkID = as.integer(links$linkID[i]), field = "linkAvgSpeed",
        value = as.character(lim), source = "measured",
        detail = paste0("posted limit used as a ceiling (county default ", round(v, 1), " mph)"),
        data_year = links$count_year[i]))
    }
  }

  # 5f. The link limit ####
  if(nrow(links) > max_links){
    links_refuse(paste0(nrow(links), " links would be written, more than MAX_LINKS ", max_links, " (",
                        LINKS_MINUTES_NOTE, "); make the place smaller or raise --max-links"))
  }

  # 5g. Write ####
  src = dplyr::bind_rows(src, tibble::tibble(linkID = as.integer(links$linkID), field = "linkDescription",
    value = links$linkDescription, source = ifelse(links$direction == "remainder", "default", "derived"),
    detail = ifelse(links$direction == "remainder", "remainder link", "HPMS route and milepoints"),
    data_year = links$count_year))
  src = src[order(src$linkID, src$field), ]
  table = as.data.frame(links[, LINKS_COLS])
  table$linkDescription = substr(table$linkDescription, 1, 50)
  readr::write_csv(table, file.path(BUCKET, "link.csv"), na = "")
  files = "link.csv"
  lsth = file.path(BUCKET, "linksourcetypehour.csv")
  if(nrow(mix) > 0){
    readr::write_csv(as.data.frame(dplyr::select(mix, linkID, sourceTypeID, sourceTypeHourFraction)), lsth)
    files = c(files, "linksourcetypehour.csv")
  } else if(file.exists(lsth) && isTRUE(overwrite)){
    unlink(lsth)
  }
  links_write_geojson(links, table, file.path(BUCKET, "links.geojson"))
  readr::write_csv(src, file.path(BUCKET, "link_sources.csv"), na = "")
  files = c(files, "links.geojson", "link_sources.csv")

  # 5h. Summary ####
  req = file.path(save_dir, "requests.csv")
  n_req = if(file.exists(req)) nrow(readr::read_csv(req, show_col_types = FALSE, progress = FALSE)) else 0
  by_rt = table(links$roadTypeID, ifelse(links$direction == "remainder", "remainder", "counted"))
  un = attr(links_build_attrs, "uncounted"); dr = attr(links_build_attrs, "dropped")
  yf = links$year_factor[links$direction != "remainder"]
  cy = sort(unique(stats::na.omit(links$count_year)))
  summ = c(
    paste0("Link builder (beta) for place ", paste(place, collapse = ","), ", state ", st, "; run year ", spec$year[1]),
    paste0("Layer: ", rs$service, " (year ", rs$year, ")"),
    paste0("Sections fetched: ", nrow(sections)),
    paste0("Links written: ", nrow(links), " (limit ", max_links, ")"),
    paste0("  road type ", rownames(by_rt), ": ", apply(by_rt, 1, function(r){
      paste(paste0(colnames(by_rt), " ", r), collapse = ", ") })),
    "Sections left out:",
    if(nrow(un) > 0) paste0("  no count (facility_type 6 not included): road type ", un$roadTypeID, ", f_system ",
                            un$f_system, ": ", un$sections, " sections, ", round(un$miles, 2), " mi") else "  no count: none",
    if(!is.null(dr) && nrow(dr) > 0) paste0("  ", dr$reason, ": road type ", dr$roadTypeID, ", f_system ", dr$f_system,
                                            ": ", dr$sections, " sections, ", round(dr$miles, 2), " mi") else "  non-inventory direction: none",
    paste0("Values from defaults: ", round(100 * mean(src$source == "default"), 1), "% of ", nrow(src), " source rows"),
    attr(filled, "summary"),
    paste0("Count years: ", if(length(cy) > 0) paste(cy, collapse = ", ") else "none",
           "; year factor ", if(length(yf) > 0) paste0(signif(min(yf, na.rm = TRUE), 4), " to ", signif(max(yf, na.rm = TRUE), 4)) else "-"),
    paste0("Requests made: ", n_req, "; seconds: ", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)))
  writeLines(summ, file.path(BUCKET, "link_summary.txt"))
  files = c(files, "link_summary.txt", "sources")
  list(status = 0L, files = files, summary = summ)
}

#' Run links_task and turn the result into an exit status; refusals go to stderr and link_summary.txt
links_main = function(env = Sys.getenv(), ...){
  BUCKET = list(...)$BUCKET %||% "inputs"
  get = function(name, default = ""){ v = Sys.getenv(name, unset = default); if(nzchar(v)) v else default }
  res = tryCatch({
    links_task(place = get("PLACE"), state = get("STATE"), max_links = get("MAX_LINKS", "40"),
               fill = tolower(get("MA_FILL_REMAINDER", "true")) != "false", overwrite = get("OVERWRITE") == "1", ...)
    0L
  }, links_refusal = function(e){
    msg = conditionMessage(e)
    message(msg)
    if(dir.exists(BUCKET)){ writeLines(msg, file.path(BUCKET, "link_summary.txt")) }
    1L
  }, error = function(e){
    message(paste0("links: unexpected error: ", conditionMessage(e)))
    2L
  })
  res
}

`%||%` = function(a, b){ if(is.null(a)) b else a }

# 6. Run (only when called as a script) ####

if(sys.nframe() == 0 && !exists("TASK_LINKS_TEST")){
  setwd("/cat")
  suppressPackageStartupMessages({
    library(catr, warn.conflicts = FALSE, quietly = TRUE)
    library(DBI, warn.conflicts = FALSE, quietly = TRUE)
    library(RMariaDB, warn.conflicts = FALSE, quietly = TRUE)
    library(dplyr, warn.conflicts = FALSE, quietly = TRUE)
    library(readr, warn.conflicts = FALSE, quietly = TRUE)
  })
  for(f in c("adapt_functions.R", "project_functions.R", "adapt_link.R", "link_sources.R", "link_build.R",
             "link_volume.R", "link_mix.R", "link_grade.R", "link_fill.R")){ source(file.path("scripts", f)) }
  status = links_main(BUCKET = "inputs", .runspec = "EPA_MOVES_Model/rs_custom.xml")
  quit(save = "no", status = status)
}
