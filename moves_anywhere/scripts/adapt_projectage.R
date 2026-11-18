# adapt_projectage.R ##########################################################
#
# What:      vehicle ages for a project-scale run, weighted by travel
# Does:      The age table says what share of REGISTERED vehicles is each age. At county scale MOVES
#            multiplies each share by the relative mileage of that age (relativeMAR) before it shares
#            out the miles; at project scale it does not, and reads the table as the ages of the
#            traffic on the link. adapt_projectage makes that correction before MOVES runs:
#            ageFraction x relativeMAR, normalised to 1 within each vehicle type and year.
#            A user's own sourcetypeagedistribution.csv is used as given. The switch
#            PROJECT_AGES=registration (environment) or "project_ages": "registration"
#            (inputs/parameters.json) keeps the registration ages. Every choice is recorded with
#            project_note().
# Called by: task_adapt.R, step 6 of launch.sh (project runs only, after the county adapters and
#            before adapt_link, so that the off-network soak default reads the same ages)
# Reads:     EPA_MOVES_Model/rs_custom.xml (runspec); inputs/_sourcetypeagedistribution.csv (written
#            by adapt_sourcetypeagedistribution.R); inputs/sourcetypeagedistribution.csv (only to see
#            whether the user gave one); inputs/parameters.json if present; the default sourcetypeage
#            table (relativeMAR, through project_read)
# Writes:    inputs/_sourcetypeagedistribution.csv (overwritten, travel-weighted case only), and rows
#            in inputs/_project_inputs.csv (project_note)
# Needs:     adapt_functions.R (get_table) and project_functions.R (is_project, project_spec,
#            project_read, project_note); dplyr, readr, jsonlite
###############################################################################

# 1. The switch ####

#' Which ages the run asked for: "travel" (the default) or "registration"
#' @param BUCKET inputs folder (may hold parameters.json)
#' @return "travel" or "registration"; stops on any other value
#' @description The environment variable PROJECT_AGES wins; else "project_ages" in parameters.json.
projectage_mode = function(BUCKET = "inputs"){
  value = Sys.getenv("PROJECT_AGES", unset = "")
  if(trimws(value) == ""){
    path = paste0(BUCKET, "/parameters.json")
    if(file.exists(path)){
      p = jsonlite::fromJSON(path)
      if(!is.null(p$project_ages)){ value = as.character(p$project_ages)[1] }
    }
  }
  value = tolower(trimws(value))
  if(is.na(value) || value == ""){ return("travel") }
  if(!value %in% c("travel", "registration")){
    stop(paste0("project_ages must be travel or registration (found ", value, ")"))
  }
  value
}

# 2. The arithmetic ####

#' Weight registration ages by relative mileage, per vehicle type and year
#' @param ages data frame with sourcetypeid, yearid, ageid, agefraction (lower-case names)
#' @param mar data frame with sourcetypeid, ageid, relativemar (lower-case names)
#' @return ages with agefraction replaced, and a column kept (TRUE where a vehicle type had no
#'   relativeMAR rows or a weighted sum of 0, so its registration shares were kept)
projectage_weight = function(ages, mar){
  mar = mar %>%
    select(sourcetypeid, ageid, relativemar) %>%
    distinct(sourcetypeid, ageid, .keep_all = TRUE)
  ages %>%
    mutate(.row = row_number()) %>%
    left_join(by = c("sourcetypeid", "ageid"), y = mar) %>%
    group_by(sourcetypeid, yearid) %>%
    mutate(
      # An age with no relativeMAR row among others that have one carries no travel
      weighted = agefraction * ifelse(is.na(relativemar), 0, relativemar),
      kept = all(is.na(relativemar)) || sum(weighted, na.rm = TRUE) <= 0,
      agefraction = if(kept[1]){ agefraction }else{ weighted / sum(weighted, na.rm = TRUE) }
    ) %>%
    ungroup() %>%
    arrange(.row) %>%
    select(-.row, -relativemar, -weighted)
}

# 3. The adapter ####

#' Write travel-weighted vehicle ages for a project run
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder, after adapt_sourcetypeagedistribution has written its _ file
adapt_projectage = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  # Only at project scale
  if(!is_project(.runspec)){ return(invisible(NULL)) }
  item = "vehicle ages"
  files = tolower(dir(BUCKET))

  # A user's table: MOVES reads it as the ages of the traffic on the link
  if("sourcetypeagedistribution.csv" %in% files){
    project_note(item, "user",
                 "used as given: at project scale MOVES reads this as the ages of the traffic on the link",
                 BUCKET)
    return(invisible("user"))
  }

  # The switch back to registration ages (stops on a value that is neither)
  mode = projectage_mode(BUCKET)
  if(mode == "registration"){
    project_note(item, "default",
                 paste0("registration ages (national default), not weighted by travel; ",
                        "expect higher NOx and particulates per mile than a county run"), BUCKET)
    return(invisible("registration"))
  }

  # Read the table the county adapter wrote, keeping its column names and order
  if(!"_sourcetypeagedistribution.csv" %in% files){ stop("_sourcetypeagedistribution.csv is missing") }
  path = paste0(BUCKET, "/", dir(BUCKET)[files == "_sourcetypeagedistribution.csv"][1])
  raw = readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
  spelling = names(raw)
  ages = raw
  names(ages) = tolower(names(ages))
  needed = c("sourcetypeid", "yearid", "ageid", "agefraction")
  missing = needed[!needed %in% names(ages)]
  if(length(missing) > 0){ stop(paste0("_sourcetypeagedistribution.csv needs column ", missing[1])) }

  # Relative mileage by age, from the default sourcetypeage table
  mar = project_read("sourcetypeage", .runspec = .runspec, BUCKET = BUCKET, default = TRUE)
  if(!all(c("sourcetypeid", "ageid", "relativemar") %in% names(mar))){
    stop("sourcetypeage table has no relativeMAR column")
  }

  # Weight, normalise, write back under the original names
  out = projectage_weight(ages, mar)
  kept = sort(unique(out$sourcetypeid[out$kept]))
  raw[[spelling[tolower(spelling) == "agefraction"][1]]] = out$agefraction
  readr::write_csv(raw, path)

  project_note(item, "derived",
               paste0("travel-weighted: national default registration ages x MOVES relative mileage ",
                      "by age, so link traffic matches county-scale runs"), BUCKET)
  for(id in kept){
    project_note(paste0("vehicle ages ", id), "default",
                 "no relative mileage for this vehicle type: registration ages kept", BUCKET)
  }
  invisible("travel")
}
