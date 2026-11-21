# adapt_offnetwork.R ##########################################################
#
# What:      adapt the off-network link tables of a project-scale run
# Does:      An off-network link (roadTypeID 1) is a parking lot or truck stop where engines start
#            and trucks idle. adapt_offnetworklink fills the user's offnetworklink.csv: every vehicle
#            type gets a row, and a blank start share, extended idle share or parked share is filled
#            with a default. adapt_opmodedistribution keeps the user's opmodedistribution.csv rows,
#            checks them, and adds default soak times (how long engines sat before starting) for the
#            off-network link when the run has start emissions and the user gave none.
# Called by: task_adapt.R, step 6 of launch.sh (project runs only, after the link adapters)
# Reads:     <BUCKET>/_link.csv (written by adapt_link); <BUCKET>/offnetworklink.csv and
#            <BUCKET>/opmodedistribution.csv if provided; the run's startsperdaypervehicle,
#            startshourfraction, startsopmodedistribution and sourcetypeagedistribution tables
#            (through project_read); the runspec
# Writes:    <BUCKET>/_offnetworklink.csv, <BUCKET>/_opmodedistribution.csv,
#            rows in <BUCKET>/_project_inputs.csv
# Needs:     project_functions.R and adapt_functions.R (sourced first); dplyr, readr, tidyr
# Exits:     stop() with a short message on bad user input
###############################################################################

# 1. Helpers ####

#' Read the adapted link table and find the off-network link
#' @param BUCKET inputs folder
#' @return list: links (all rows, lower-case names) and off (rows with roadtypeid 1)
offnetwork_links = function(BUCKET){
  links = readr::read_csv(paste0(BUCKET, "/_link.csv"), show_col_types = FALSE, progress = FALSE)
  names(links) = tolower(names(links))
  list(links = links, off = links[links$roadtypeid == 1, ])
}

# 2. The off-network link table ####

#' Adapt the offnetworklink table
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder
adapt_offnetworklink = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){

  table = "offnetworklink"
  spec = project_spec(.runspec)
  found = offnetwork_links(BUCKET)
  files = get_changes(BUCKET)
  f = get_is_custom(files, table = table)

  # No off-network link: nothing to write
  if(nrow(found$off) == 0){
    if(f$is_custom){ stop("offnetworklink.csv given but no link has roadTypeID 1") }
    return(invisible(NULL))
  }

  if(!f$is_custom){ stop("off-network link needs offnetworklink.csv") }
  user = get_data(changes = f$changes)

  # Check the user's columns and rows
  if(!"sourcetypeid" %in% names(user)){ stop("offnetworklink.csv needs column sourceTypeID") }
  if(!"vehiclepopulation" %in% names(user)){ stop("offnetworklink.csv needs column vehiclePopulation") }
  optional = c("startfraction", "extendedidlefraction", "parkedvehiclefraction")
  for(column in optional){
    if(!column %in% names(user)){ user[[column]] = NA_real_ }
    user[[column]] = suppressWarnings(as.numeric(user[[column]]))
  }
  user$sourcetypeid = suppressWarnings(as.integer(user$sourcetypeid))
  user$vehiclepopulation = suppressWarnings(as.numeric(user$vehiclepopulation))

  if(any(is.na(user$sourcetypeid) | !user$sourcetypeid %in% spec$sourcetypes)){
    stop("offnetworklink.csv sourceTypeID not in the run's vehicle types")
  }
  if(any(duplicated(user$sourcetypeid))){ stop("offnetworklink.csv repeats a sourceTypeID") }
  if(any(is.na(user$vehiclepopulation) | user$vehiclepopulation < 0)){
    stop("offnetworklink.csv vehiclePopulation must be 0 or more")
  }
  for(column in optional){
    values = user[[column]]
    if(any(!is.na(values) & (values < 0 | values > 1))){
      stop(paste0("offnetworklink.csv ", column, " must be 0 to 1"))
    }
  }

  # Default start share: starts per day x share of the day's starts in this hour
  starts = project_read("startsperdaypervehicle", .runspec, BUCKET, spec = spec) %>%
    group_by(sourcetypeid) %>% summarize(perday = first(startsperdaypervehicle), .groups = "drop")
  hourly = project_read("startshourfraction", .runspec, BUCKET, spec = spec) %>%
    group_by(sourcetypeid) %>% summarize(share = first(allocationfraction), .groups = "drop")
  data = dplyr::tibble(sourcetypeid = spec$sourcetypes) %>%
    left_join(starts, by = "sourcetypeid") %>%
    left_join(hourly, by = "sourcetypeid") %>%
    mutate(default_start = pmin(1, tidyr::replace_na(perday, 0) * tidyr::replace_na(share, 0))) %>%
    left_join(user %>% select(sourcetypeid, vehiclepopulation, all_of(optional)), by = "sourcetypeid") %>%
    mutate(
      vehiclepopulation = tidyr::replace_na(vehiclepopulation, 0),
      start_user = !is.na(startfraction),
      extended_user = !is.na(extendedidlefraction),
      parked_user = !is.na(parkedvehiclefraction),
      startfraction = ifelse(start_user, startfraction, default_start),
      extendedidlefraction = ifelse(extended_user, extendedidlefraction, 0),
      parkedvehiclefraction = ifelse(parked_user, parkedvehiclefraction, 1)
    )

  # Where did each fraction come from? (a vehicle type the user left out is all default)
  project_note(item = "off-network startFraction",
               source = ifelse(all(data$start_user), "user", "default"),
               detail = "startsperdaypervehicle x startshourfraction", BUCKET = BUCKET)
  if(!all(data$extended_user)){
    project_note(item = "off-network extendedIdleFraction", source = "default", detail = "0", BUCKET = BUCKET)
  }
  if(!all(data$parked_user)){
    project_note(item = "off-network parkedVehicleFraction", source = "default", detail = "1", BUCKET = BUCKET)
  }
  anydefault = !all(data$start_user & data$extended_user & data$parked_user)

  data = data %>%
    transmute(zoneID = found$off$zoneid[1], sourceTypeID = sourcetypeid,
              vehiclePopulation = vehiclepopulation, startFraction = round(startfraction, 6),
              extendedIdleFraction = extendedidlefraction,
              parkedVehicleFraction = parkedvehiclefraction) %>%
    arrange(sourceTypeID)

  import_table(data, tablename = "offnetworklink", adapt = anydefault, save = TRUE, volume = BUCKET)
  invisible(data)
}

# 3. Operating mode distribution ####

#' Adapt the opmodedistribution table
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder
adapt_opmodedistribution = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){

  table = "opmodedistribution"
  spec = project_spec(.runspec)
  found = offnetwork_links(BUCKET)
  files = get_changes(BUCKET)
  f = get_is_custom(files, table = table)
  columns = c("sourcetypeid", "hourdayid", "linkid", "polprocessid", "opmodeid", "opmodefraction")
  spelled = c("sourceTypeID", "hourDayID", "linkID", "polProcessID", "opModeID", "opModeFraction")

  # The user's rows, checked
  supplied = NULL
  if(f$is_custom){
    supplied = get_data(changes = f$changes)
    for(i in seq_along(columns)){
      if(!columns[i] %in% names(supplied)){ stop(paste0("opmodedistribution.csv needs column ", spelled[i])) }
    }
    supplied = supplied %>% select(all_of(columns))
    # No blanks and no text: a blank fraction would pass the sum check and load as nothing
    for(i in seq_along(columns)){
      supplied[[columns[i]]] = suppressWarnings(as.numeric(supplied[[columns[i]]]))
      if(any(is.na(supplied[[columns[i]]]))){
        stop(paste0("opmodedistribution.csv has a blank or non-numeric ", spelled[i]))
      }
    }
    if(any(supplied$opmodefraction < 0 | supplied$opmodefraction > 1)){
      stop("opmodedistribution.csv opModeFraction must be 0 to 1")
    }
    if(any(supplied$hourdayid != spec$hourday)){
      stop(paste0("opmodedistribution.csv hourDayID must be ", spec$hourday))
    }
    unknown = setdiff(supplied$linkid, found$links$linkid)
    if(length(unknown) > 0){
      stop(paste0("opmodedistribution.csv linkID ", unknown[1], " is not in link.csv"))
    }
    sums = supplied %>%
      group_by(sourcetypeid, hourdayid, linkid, polprocessid) %>%
      summarize(total = sum(opmodefraction), .groups = "drop") %>%
      filter(abs(total - 1) > 0.0001)
    if(nrow(sums) > 0){
      stop(paste0("opmodedistribution for link ", sums$linkid[1], " does not sum to 1"))
    }
  }

  # Default soak times for the off-network link
  data = supplied
  appended = FALSE
  if(nrow(found$off) > 0 && length(spec$start_polprocess) > 0){
    {
      soak = project_read("startsopmodedistribution", .runspec, BUCKET, spec = spec) %>%
        select(sourcetypeid, ageid, opmodeid, opmodefraction)
      ages = project_read("sourcetypeagedistribution", .runspec, BUCKET, spec = spec) %>%
        select(sourcetypeid, ageid, agefraction)
      # Each operating mode's share, weighted by how many vehicles of each age there are
      weighted = soak %>%
        inner_join(ages, by = c("sourcetypeid", "ageid")) %>%
        group_by(sourcetypeid, opmodeid) %>%
        summarize(opmodefraction = sum(agefraction * opmodefraction), .groups = "drop") %>%
        group_by(sourcetypeid) %>%
        mutate(opmodefraction = opmodefraction / sum(opmodefraction)) %>%
        ungroup() %>%
        filter(sourcetypeid %in% spec$sourcetypes)
      defaults = tidyr::crossing(weighted, polprocessid = spec$start_polprocess) %>%
        mutate(hourdayid = spec$hourday, linkid = found$off$linkid[1]) %>%
        select(all_of(columns))
      pairs_all = nrow(distinct(defaults, sourcetypeid, polprocessid))
      # Keep the user's soak times where given, and fill only the vehicle type x pollutant pairs
      # the user left out. (Dropping every default because one pair was supplied would leave the
      # other vehicle types with no start operating modes, and the run would still end ok.)
      if(!is.null(supplied)){
        given = supplied %>% filter(linkid %in% found$off$linkid) %>% distinct(sourcetypeid, polprocessid)
        defaults = defaults %>% anti_join(given, by = c("sourcetypeid", "polprocessid"))
      }
      pairs_default = nrow(distinct(defaults, sourcetypeid, polprocessid))
      if(pairs_default > 0){
        data = bind_rows(supplied, defaults)
        appended = TRUE
        detail = "startsopmodedistribution weighted by vehicle age"
        if(pairs_default < pairs_all){
          detail = paste0(detail, ", for ", pairs_default, " of ", pairs_all, " vehicle type x pollutant pairs")
        }
        project_note(item = "start soak times (opmodedistribution)", source = "default",
                     detail = detail, BUCKET = BUCKET)
      }else if(pairs_all > 0){
        project_note(item = "start soak times (opmodedistribution)", source = "user",
                     detail = "supplied opmodedistribution.csv", BUCKET = BUCKET)
      }
    }
  }

  # Nothing to write
  if(is.null(data) || nrow(data) == 0){ return(invisible(NULL)) }

  data = data %>%
    select(sourceTypeID = sourcetypeid, hourDayID = hourdayid, linkID = linkid,
           polProcessID = polprocessid, opModeID = opmodeid, opModeFraction = opmodefraction) %>%
    arrange(sourceTypeID, hourDayID, linkID, polProcessID, opModeID)

  import_table(data, tablename = "opmodedistribution", adapt = appended, save = TRUE, volume = BUCKET)
  invisible(data)
}
