# link_build.R ################################################################
#
# What:      turn HPMS road sections into project-scale links (project scale)
# Does:      links_build gives each section a MOVES road type (restricted: functional class 1, and
#            class 2 unless HPMS access_control is 2 or 3; class 2 without access_control is marked
#            default; classes 3-7 are unrestricted whatever access_control says), keeps the sections with a positive
#            count (aadt), joins consecutive equal sections of one route into links of at most 2 miles,
#            and splits a two-way link into a primary and an opposite link with their share of the
#            count. Sections without a count are tallied in attribute "uncounted"; sections in the
#            non-inventory direction (facility_type 6) are tallied in attribute "dropped". Attribute
#            "sources" says where each value came from.
# Called by: the link builder (task_links.R); not part of a county run
# Reads:     nothing; takes the sections data frame from links_fetch_hpms() (link_sources.R)
# Writes:    nothing
# Needs:     dplyr, tibble
###############################################################################

# 1. Settings ####

# columns of the links frame, in order (the link table contract)
LINKS_BUILD_COLS = c("linkID", "route_id", "begin_point", "end_point", "roadTypeID", "linkLength", "aadt",
                     "dir_share", "direction", "through_lanes", "speed_limit", "aadt_single_unit",
                     "aadt_combination", "k_factor", "count_year", "f_system", "urban_id", "n_sections",
                     "linkDescription", "geometry")
LINKS_JOIN_TOL = 0.001   # miles between one section's end and the next one's begin
LINKS_MAX_MILES = 2      # a merged link stops growing at this length
LINKS_RURAL_ID = 99999   # urban_id of rural sections
LINKS_MATCH = c("roadTypeID", "rt_fallback", "aadt", "through_lanes", "speed_limit", "facility_type",
                "aadt_single_unit", "aadt_combination")

# 2. Small helpers ####

#' MOVES road type from HPMS functional class, access control and urban code
#' f_system 1 (Interstate) is always restricted access (road type 2 rural, 4 urban). f_system 2 (other
#' freeways and expressways) is restricted when access_control is 1 or missing (links_build marks the
#' missing case "default") and unrestricted when it is 2 or 3 (FHWA HPMS field manual: 1 full, 2 partial,
#' 3 none). f_system 3-7 or missing is always unrestricted, whatever access_control says (states code
#' full control on thousands of class 3-7 sections; tests/fixtures/links/hpms_fields_notes.md).
#' urban_id 99999 or NA is rural.
#' @param f_system HPMS functional system (1-7)
#' @param urban_id HPMS urban code
#' @param access_control HPMS access control (1, 2, 3 or NA); NULL = missing on every section
links_road_type = function(f_system, urban_id, access_control = NULL){
  if(is.null(access_control)){ access_control = rep(NA_real_, length(f_system)) }
  restricted = !is.na(f_system) &
    (f_system == 1 | (f_system == 2 & (is.na(access_control) | access_control == 1)))
  rural = is.na(urban_id) | urban_id == LINKS_RURAL_ID
  as.integer(dplyr::case_when(rural & restricted ~ 2, rural ~ 3, restricted ~ 4, TRUE ~ 5))
}

#' Equal values, NA equal to NA
same = function(a, b){ (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b) }

#' Milepost text for a description
mp = function(x){ as.character(round(x, 4)) }

#' Bind lon/lat matrices in order, keeping a shared joint point once
bind_geom = function(gs){
  out = gs[[1]]
  for(g in gs[-1]){
    if(nrow(out) > 0 && nrow(g) > 0 && isTRUE(all(out[nrow(out), ] == g[1, ]))){ g = g[-1, , drop = FALSE] }
    out = rbind(out, g)
  }
  out
}

#' An empty links frame with the contract's columns
links_empty = function(){
  e = tibble::tibble(linkID = integer(0), route_id = character(0), begin_point = numeric(0),
                     end_point = numeric(0), roadTypeID = integer(0), linkLength = numeric(0),
                     aadt = numeric(0), dir_share = numeric(0), direction = character(0),
                     through_lanes = numeric(0), speed_limit = numeric(0), aadt_single_unit = numeric(0),
                     aadt_combination = numeric(0), k_factor = numeric(0), count_year = numeric(0),
                     f_system = numeric(0), urban_id = numeric(0), n_sections = integer(0),
                     linkDescription = character(0), geometry = list())
  e[, LINKS_BUILD_COLS]
}

#' An empty sources frame
links_sources_empty = function(){
  tibble::tibble(linkID = integer(0), field = character(0), value = character(0), source = character(0),
                 detail = character(0), data_year = numeric(0))
}

#' Tally sections by road type and functional class
tally_sections = function(df){
  df |>
    dplyr::group_by(roadTypeID, f_system) |>
    dplyr::summarize(sections = dplyr::n(), miles = sum(miles, na.rm = TRUE), .groups = "drop")
}

# 3. Build links ####

#' Sections to links
#' @param sections data frame from links_fetch_hpms() / links_parse_sections(); attribute "year" is the
#'   layer's year, used when a section has no data_year
#' @return links frame (LINKS_BUILD_COLS); attributes uncounted, dropped, sources
links_build = function(sections){
  layer_year = attr(sections, "year")
  if(is.null(layer_year)){ layer_year = NA_real_ }
  if(!"data_year" %in% names(sections)){ sections$data_year = NA_real_ }
  if(!"access_control" %in% names(sections)){ sections$access_control = NA_real_ }

  s = sections |>
    dplyr::mutate(roadTypeID = links_road_type(f_system, urban_id, access_control),
                  rt_fallback = !is.na(f_system) & f_system == 2 & is.na(access_control),
                  miles = dplyr::if_else(is.na(section_length), end_point - begin_point, section_length),
                  counted = !is.na(aadt) & aadt > 0)

  uncounted = tally_sections(dplyr::filter(s, !counted))
  inv = dplyr::filter(s, counted)
  dropped = inv |>
    dplyr::filter(!is.na(facility_type) & facility_type == 6) |>
    tally_sections() |>
    dplyr::mutate(reason = "second carriageway already counted in the inventory direction")
  inv = inv |>
    dplyr::filter(is.na(facility_type) | facility_type != 6) |>
    dplyr::arrange(route_id, begin_point)

  finish = function(links, src){
    attr(links, "uncounted") = uncounted
    attr(links, "dropped") = dropped
    attr(links, "sources") = src
    links
  }
  if(nrow(inv) == 0){ return(finish(links_empty(), links_sources_empty())) }

  # 3a. Group consecutive equal sections ####
  grp = integer(nrow(inv))
  g = 1L
  len = inv$miles[1]
  grp[1] = g
  for(i in seq_len(nrow(inv))[-1]){
    joins = identical(inv$route_id[i], inv$route_id[i - 1]) &&
      isTRUE(abs(inv$begin_point[i] - inv$end_point[i - 1]) <= LINKS_JOIN_TOL) &&
      all(vapply(LINKS_MATCH, function(f){ same(inv[[f]][i], inv[[f]][i - 1]) }, TRUE)) &&
      len + inv$miles[i] <= LINKS_MAX_MILES + 1e-9
    if(joins){ len = len + inv$miles[i] } else { g = g + 1L; len = inv$miles[i] }
    grp[i] = g
  }
  inv$grp = grp

  # 3b. One row per merged link ####
  diff_note = function(x){
    u = unique(x)
    if(length(u) > 1){ paste0("; sections differ (", paste(u, collapse = ", "), "), first kept") } else { "" }
  }
  merged = lapply(split(inv, inv$grp), function(d){
    yr = dplyr::if_else(is.na(d$data_year), as.numeric(layer_year), d$data_year)
    tibble::tibble(route_id = d$route_id[1], begin_point = d$begin_point[1], end_point = d$end_point[nrow(d)],
                   roadTypeID = d$roadTypeID[1], rt_fallback = d$rt_fallback[1],
                   access_control = d$access_control[1], linkLength = sum(d$miles), aadt = d$aadt[1],
                   facility_type = d$facility_type[1], dir_factor = d$dir_factor[1],
                   through_lanes = d$through_lanes[1], speed_limit = d$speed_limit[1],
                   aadt_single_unit = d$aadt_single_unit[1], aadt_combination = d$aadt_combination[1],
                   k_factor = d$k_factor[1], count_year = yr[1], f_system = d$f_system[1],
                   urban_id = d$urban_id[1], n_sections = nrow(d), geometry = list(bind_geom(d$geometry)),
                   note_k = diff_note(d$k_factor), note_dir = diff_note(d$dir_factor), note_year = diff_note(yr))
  }) |> dplyr::bind_rows()

  # 3c. Direction ####
  merged = merged |>
    dplyr::mutate(fac_default = is.na(facility_type) | !facility_type %in% c(1, 2, 4, 5),
                  one_way = !fac_default & facility_type %in% c(1, 4, 5),
                  dir_measured = !is.na(dir_factor) & dir_factor >= 50 & dir_factor <= 100,
                  share = dplyr::if_else(dir_measured, dir_factor / 100, 0.5))
  rows = lapply(seq_len(nrow(merged)), function(i){
    m = merged[i, ]
    if(m$one_way){
      dplyr::mutate(m, direction = "one-way", dir_share = 1)
    } else {
      opp = dplyr::mutate(m, direction = "opposite", dir_share = 1 - m$share)
      opp$geometry = list(m$geometry[[1]][rev(seq_len(nrow(m$geometry[[1]]))), , drop = FALSE])
      dplyr::bind_rows(dplyr::mutate(m, direction = "primary", dir_share = m$share), opp)
    }
  })
  links = dplyr::bind_rows(rows) |>
    dplyr::mutate(linkID = seq_len(dplyr::n()),
                  linkDescription = paste0(route_id, " ", mp(begin_point), "-", mp(end_point),
                                           dplyr::if_else(direction == "opposite", " opp", "")),
                  linkDescription = substr(gsub("[,\"']", "", linkDescription), 1, 50))

  # 3d. Sources ####
  src = lapply(seq_len(nrow(links)), function(i){
    l = links[i, ]
    area = if(is.na(l$urban_id) || l$urban_id == LINKS_RURAL_ID){ "rural" } else { paste0("urban ", l$urban_id) }
    r = tibble::tibble(
      linkID = l$linkID,
      field = c("linkLength", "roadTypeID", "aadt", "dir_share"),
      value = as.character(c(l$linkLength, l$roadTypeID, l$aadt, l$dir_share)),
      source = c("measured", if(l$rt_fallback){ "default" } else { "derived" }, "measured",
                 dplyr::if_else(l$one_way | l$dir_measured, "measured", "default")),
      detail = c(paste0("sum of ", l$n_sections, " HPMS sections"),
                 if(l$rt_fallback){ paste0("access control not coded; class 2 treated as restricted, ", area) }
                 else if(isTRUE(l$f_system == 2)){ paste0("f_system 2, access_control ", l$access_control, ", ", area) }
                 else if(isTRUE(l$access_control == 1) && !isTRUE(l$f_system == 1)){
                   paste0("access control coded full on functional class ", l$f_system, "; treated as unrestricted, ", area) }
                 else { paste0("f_system ", l$f_system, ", ", area) },
                 "HPMS aadt, both directions",
                 if(l$one_way){ paste0("one-way road (facility_type ", l$facility_type, ")") }
                 else if(l$dir_measured){ paste0("dir_factor ", l$dir_factor, ", ", l$direction) }
                 else { "half each way" }),
      data_year = l$count_year)
    if(l$fac_default){
      r = dplyr::bind_rows(r, tibble::tibble(linkID = l$linkID, field = "direction", value = l$direction,
        source = "default", detail = paste0("facility_type ", l$facility_type, " not 1, 2, 4 or 5; treated as two-way"),
        data_year = l$count_year))
    }
    notes = c(k_factor = l$note_k, dir_factor = l$note_dir, count_year = l$note_year)
    notes = notes[notes != ""]
    if(length(notes) > 0){
      r = dplyr::bind_rows(r, tibble::tibble(linkID = l$linkID, field = names(notes),
        value = as.character(c(k_factor = l$k_factor, dir_factor = l$dir_factor, count_year = l$count_year)[names(notes)]),
        source = "measured", detail = paste0("first of ", l$n_sections, " sections", notes), data_year = l$count_year))
    }
    r
  }) |> dplyr::bind_rows()

  finish(links[, LINKS_BUILD_COLS], src)
}
