# link_volume.R ###############################################################
#
# What:      hourly volume and the year factor for project-scale links
# Does:      links_volume scales each link's daily count to the run year by the county's miles
#            (year_factor = county miles in the run year / county miles in the count year, all vehicle
#            types summed), then spreads it to the run's hour:
#            linkVolume = sum over vehicle types s of aadt_scaled x 365 x a[s] x monthVMTFraction[s]
#              x (7 / noOfDays) x dayVMTFraction[s, r] / noOfRealDays x hourVMTFraction[s, r],
#            with aadt_scaled = aadt x dir_share x year_factor, r the link's road type and a[s] the
#            default vehicle mix of link_default_mix(). Where k_factor is present it records the
#            design-hour volume as a cross-check (not used). Links with direction "remainder" are
#            left untouched.
# Limits:    noOfDays is MOVES' monthofanyyear value, which has 28 days for February in every year
#            (MOVES makes no leap-year change); this script follows it.
# Called by: the link builder (task_links.R); not part of a county run
# Reads:     through project_read: _sourcetypeyearvmt.csv, _monthvmtfraction.csv, _dayvmtfraction.csv,
#            _hourvmtfraction.csv, _roadtypedistribution.csv and the default monthofanyyear and
#            dayofanyweek tables; the county's miles in other years through adapt_vmt_from_nei()
#            (scripts/reference/nei_sourcetypeyearvmt.rds and its companions), unless vmt_year is given
# Writes:    nothing; returns the links with linkVolume, year_factor, aadt_scaled and attribute sources
# Needs:     adapt_functions.R, project_functions.R (project_spec, project_read), adapt_link.R
#            (link_default_mix), adapt_from_nei.R (adapt_vmt_from_nei, for the default lookup);
#            dplyr, readr
###############################################################################

# 1. The county's miles in any year ####

#' A function (year) -> the county's miles, all vehicle types summed, from the NEI reference tables
#' @param geoid county geoid (number or text)
#' @param path_hpmsvtypeyear,path_nei_sourcetypeyearvmt,path_projections reference files (as adapt_vmt_from_nei)
links_vmt_year = function(geoid,
                          path_hpmsvtypeyear = "scripts/reference/hpmsvtypeyear.csv",
                          path_nei_sourcetypeyearvmt = "scripts/reference/nei_sourcetypeyearvmt.rds",
                          path_projections = "scripts/projections.rds"){
  .geoidchar = stringr::str_pad(as.character(geoid), width = 5, side = "left", pad = "0")
  function(year){
    v = suppressMessages(adapt_vmt_from_nei(.geoidchar = .geoidchar, .year = year,
                                            path_hpmsvtypeyear = path_hpmsvtypeyear,
                                            path_nei_sourcetypeyearvmt = path_nei_sourcetypeyearvmt,
                                            path_projections = path_projections))
    sum(v$VMT, na.rm = TRUE)
  }
}

# 2. The share of a year's traffic in the run's hour ####

#' Share of a year's vehicles on a road type that pass in the run's hour
#' @param roadtypes road types of the links
#' @param spec result of project_spec()
#' @param BUCKET inputs folder
#' @param .runspec path to the run's runspec (XML)
#' @return tibble roadTypeID, hour_share (linkVolume = aadt_scaled x 365 x hour_share)
links_hour_share = function(roadtypes, spec, BUCKET = "inputs", .runspec = "EPA_MOVES_Model/rs_custom.xml"){
  mix = link_default_mix(roadtypes, spec, BUCKET, .runspec)
  month = project_read("monthvmtfraction", .runspec, BUCKET, spec = spec)
  day = project_read("dayvmtfraction", .runspec, BUCKET, spec = spec)
  hour = project_read("hourvmtfraction", .runspec, BUCKET, spec = spec)
  days = project_read("monthofanyyear", .runspec, BUCKET, spec = spec)$noofdays[1]
  real = project_read("dayofanyweek", .runspec, BUCKET, spec = spec)$noofrealdays[1]
  if(is.null(days) || is.na(days) || days <= 0){ stop(paste0("no noOfDays for month ", spec$month[1])) }
  if(is.null(real) || is.na(real) || real <= 0){ stop(paste0("no noOfRealDays for day ", spec$day[1])) }

  mix %>%
    dplyr::left_join(by = "sourceTypeID", y = month %>%
      dplyr::select(sourceTypeID = sourcetypeid, monthvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = day %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, dayvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::left_join(by = c("sourceTypeID", "roadTypeID"), y = hour %>%
      dplyr::select(sourceTypeID = sourcetypeid, roadTypeID = roadtypeid, hourvmtfraction) %>% dplyr::distinct()) %>%
    dplyr::mutate(
      term = share * monthvmtfraction * (7 / days) * dayvmtfraction / real * hourvmtfraction,
      term = ifelse(is.na(term), 0, term)) %>%
    dplyr::group_by(roadTypeID) %>%
    dplyr::summarise(hour_share = sum(term), .groups = "drop")
}

# 3. The links ####

#' Hourly volume and year factor of each link
#' @param links the links data frame of the link table contract (linkID, roadTypeID, aadt, dir_share,
#'   direction, count_year, k_factor, ...)
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder holding the county tables
#' @param spec result of project_spec(); read from .runspec when NULL
#' @param vmt_year function (year) -> the county's miles, all vehicle types; links_vmt_year() when NULL
#' @return links with linkVolume, year_factor, aadt_scaled; attribute sources
#'   (linkID, field, value, source, detail, data_year)
links_volume = function(links, .runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs",
                        spec = NULL, vmt_year = NULL){
  if(is.null(spec)){ spec = project_spec(.runspec) }
  if(is.null(vmt_year)){ vmt_year = links_vmt_year(spec$geoid[1]) }
  run_year = spec$year[1]

  for(col in c("linkVolume", "year_factor", "aadt_scaled")){
    if(!col %in% names(links)){ links[[col]] = rep(NA_real_, nrow(links)) }
  }
  sources = dplyr::tibble(linkID = numeric(0), field = character(0), value = numeric(0),
                          source = character(0), detail = character(0), data_year = numeric(0))
  todo = which(is.na(links$direction) | links$direction != "remainder")
  if(length(todo) == 0){
    attr(links, "sources") = sources
    return(links)
  }

  # County miles by year, looked up once per year; a failure is kept as its message
  miles = list()
  get_miles = function(y){
    key = as.character(y)
    if(is.null(miles[[key]])){
      miles[[key]] <<- tryCatch({
        m = vmt_year(y)
        if(length(m) != 1 || is.na(m) || m <= 0){ stop(paste0("county miles for ", y, " are ", paste(m, collapse = " "))) }
        m
      }, error = function(e){ paste0("county miles lookup failed for ", y, ": ", conditionMessage(e)) })
    }
    miles[[key]]
  }

  # Year factor
  for(i in todo){
    cy = links$count_year[i]
    if(is.na(cy) || cy == run_year){
      f = 1
      row = dplyr::tibble(source = ifelse(is.na(cy), "default", "derived"),
                          detail = ifelse(is.na(cy), "no count year; factor 1",
                                          paste0("count year ", cy, " is the run year; factor 1")))
    }else{
      a = get_miles(cy)
      b = get_miles(run_year)
      if(is.character(a) || is.character(b)){
        f = 1
        row = dplyr::tibble(source = "default",
                            detail = paste0(if(is.character(a)) a else b, "; factor 1 (", cy, " to ", run_year, ")"))
      }else{
        f = b / a
        row = dplyr::tibble(source = "derived",
                            detail = paste0("county miles ", round(b), " in ", run_year, " / ", round(a),
                                            " in ", cy, " (all vehicle types)"))
      }
    }
    links$year_factor[i] = f
    sources = dplyr::bind_rows(sources, dplyr::tibble(linkID = links$linkID[i], field = "year_factor",
                                                      value = f, source = row$source, detail = row$detail,
                                                      data_year = cy))
  }

  # Hourly volume
  aadt_dir = links$aadt[todo] * links$dir_share[todo]
  links$aadt_scaled[todo] = aadt_dir * links$year_factor[todo]
  share = links_hour_share(links$roadTypeID[todo], spec, BUCKET, .runspec)
  h = share$hour_share[match(links$roadTypeID[todo], share$roadTypeID)]
  links$linkVolume[todo] = round(links$aadt_scaled[todo] * 365 * h, 3)
  sources = dplyr::bind_rows(sources, dplyr::tibble(
    linkID = links$linkID[todo], field = "linkVolume", value = links$linkVolume[todo], source = "derived",
    detail = paste0("AADT ", links$aadt[todo], " x direction share ", links$dir_share[todo],
                    " x year factor ", signif(links$year_factor[todo], 6), " (", links$count_year[todo],
                    " to ", run_year, "), spread by the county's month, day and hour shares"),
    data_year = links$count_year[todo]))

  # Design-hour cross-check from the federal K factor (not used)
  if("k_factor" %in% names(links)){
    k = todo[!is.na(links$k_factor[todo])]
    if(length(k) > 0){
      sources = dplyr::bind_rows(sources, dplyr::tibble(
        linkID = links$linkID[k], field = "peak_hour_check",
        value = links$aadt[k] * links$dir_share[k] * links$k_factor[k] / 100, source = "measured",
        detail = "design-hour volume from the federal K factor; not used",
        data_year = links$count_year[k]))
    }
  }

  attr(links, "sources") = sources[order(sources$linkID), ]
  links
}
