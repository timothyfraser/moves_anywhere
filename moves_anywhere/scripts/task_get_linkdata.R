# task_get_linkdata.R ##########################################################
#
# What:      Build the link-level results table of a project-scale run
# Does:      get_linkdata sums MOVES's two output tables to one row per link x pollutant x process x
#            vehicle type x fuel, with that link's activity (miles, hours, starts, vehicles) beside it.
#            linkdata_summary makes the per-link table that task_summarize.R prints.
# Called by: task_postprocess.R (sourced, project runs only); task_summarize.R; tests/test_linkdata.R
# Reads:     <FOLDER>/movesoutput.csv, <FOLDER>/movesactivityoutput.csv, <FOLDER>/_link.csv
# Writes:    <FOLDER>/linkdata.csv
# Needs:     dplyr, readr
###############################################################################

# 1. Link-level results ####

#' Write <FOLDER>/linkdata.csv; returns its path invisibly
#' @param FOLDER folder holding the two MOVES output tables and _link.csv
get_linkdata = function(FOLDER = "inputs"){
  
  # Read the tables. Only the newest MOVES run counts, if the output holds several.
  e = readr::read_csv(file.path(FOLDER, "movesoutput.csv"), show_col_types = FALSE)
  a = readr::read_csv(file.path(FOLDER, "movesactivityoutput.csv"), show_col_types = FALSE)
  l = readr::read_csv(file.path(FOLDER, "_link.csv"), show_col_types = FALSE)
  newest = max(e$MOVESRunID, na.rm = TRUE)
  e = e %>% dplyr::filter(MOVESRunID == newest)
  a = a %>% dplyr::filter(MOVESRunID == newest)
  
  # Emissions: grams in the hour, summed over regulatory class, model year and the rest
  keys = c("yearID", "monthID", "dayID", "hourID", "countyID", "linkID", "sourceTypeID", "fuelTypeID")
  emis = e %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(c(keys, "pollutantID", "processID")))) %>%
    dplyr::summarize(emissions = sum(emissionQuant, na.rm = TRUE), .groups = "drop")
  
  # Activity: summed by link x vehicle type x fuel, one column per activity type (0 when absent).
  # Not joined on month, day or hour: a project run has one hour, and MOVES writes the vehicle
  # population (activity type 6) under month 0, day 0, hour 0.
  akeys = c("linkID", "sourceTypeID", "fuelTypeID")
  types = c(vmt = 1, sourcehours = 4, vehicles = 6, starts = 7)
  act = a %>%
    dplyr::filter(activityTypeID %in% types) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(c(akeys, "activityTypeID")))) %>%
    dplyr::summarize(activity = sum(activity, na.rm = TRUE), .groups = "drop")
  wide = emis %>% dplyr::distinct(dplyr::across(dplyr::all_of(akeys)))
  for(i in seq_along(types)){
    one = act %>%
      dplyr::filter(activityTypeID == types[i]) %>%
      dplyr::select(dplyr::all_of(akeys), activity)
    names(one)[names(one) == "activity"] = names(types)[i]
    wide = wide %>% dplyr::left_join(one, by = akeys)
    wide[[names(types)[i]]] = dplyr::coalesce(wide[[names(types)[i]]], 0)
  }
  
  # Join the activity onto every pollutant row, add the road type, name and order the columns
  road = l %>% dplyr::select(linkID, linkroad = roadTypeID) %>% dplyr::distinct(linkID, .keep_all = TRUE)
  out = emis %>%
    dplyr::left_join(wide, by = akeys) %>%
    dplyr::left_join(road, by = "linkID") %>%
    dplyr::transmute(
      year = yearID, month = monthID, day = dayID, hour = hourID,
      geoid = countyID, link = linkID, roadtype = linkroad,
      pollutant = pollutantID, process = processID,
      sourcetype = sourceTypeID, fueltype = fuelTypeID,
      emissions, vmt, sourcehours, starts, vehicles
    ) %>%
    dplyr::arrange(link, pollutant, process, sourcetype, fueltype)
  
  path = file.path(FOLDER, "linkdata.csv")
  readr::write_csv(out, path)
  invisible(path)
}

# 2. Per-link summary ####

#' One row per link: miles, CO2 and NOx grams, grams per mile, starts
#' @param linkdata the table get_linkdata wrote
#' @param link the user's link table (_link.csv): linkID, roadTypeID, linkDescription
linkdata_summary = function(linkdata, link){
  lk = link
  # Activity repeats on every pollutant row, so count it once per link x vehicle type x fuel
  act = linkdata %>%
    dplyr::distinct(link, sourcetype, fueltype, vmt, starts) %>%
    dplyr::group_by(link) %>%
    dplyr::summarize(miles = sum(vmt), starts = sum(starts), .groups = "drop")
  em = linkdata %>%
    dplyr::group_by(link) %>%
    dplyr::summarize(
      co2 = sum(emissions[pollutant == 90]),
      nox = sum(emissions[pollutant == 3]),
      .groups = "drop")
  desc = if("linkDescription" %in% names(lk)) lk$linkDescription else rep(NA_character_, nrow(lk))
  info = data.frame(link = lk$linkID, roadtype = lk$roadTypeID, description = desc)
  info %>%
    dplyr::inner_join(act, by = "link") %>%
    dplyr::inner_join(em, by = "link") %>%
    dplyr::mutate(
      co2_per_mile = ifelse(miles > 0, co2 / miles, NA_real_),
      nox_per_mile = ifelse(miles > 0, nox / miles, NA_real_)
    ) %>%
    dplyr::arrange(link)
}
