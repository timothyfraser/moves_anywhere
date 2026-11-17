# project_functions.R #########################################################
#
# What:      Helper functions for project-scale runs (MOVES domain PROJECT: road links, one hour).
# Does:      is_project and project_domain read the runspec's domain. project_spec lists the run's
#            county, year, month, day type, hour, road types, vehicle types and start processes.
#            project_check stops on a runspec that MOVES would refuse or that this image does not
#            support. project_read loads one county table, filtered to the run's time.
#            project_note records which link inputs were filled in by default.
# Called by: task_adapt.R, step 6 of launch.sh (sourced); also sourced by importer.R,
#            task_check_import.R, task_postprocess.R and task_summarize.R (is_project only)
# Reads:     the runspec (XML); <BUCKET>/_<table>.csv, <BUCKET>/<table>.csv; the default input
#            database (project_read only, as the last resort)
# Writes:    <BUCKET>/_project_inputs.csv (project_note)
# Needs:     xml2; project_read also needs dplyr, readr and adapt_functions.R (get_data, get_table)
###############################################################################

# 1. The runspec ####

#' Values of one attribute for every node matching an XPath
#' @param x an xml2 document
#' @param xpath XPath of the nodes
#' @param attr name of the attribute
project_attr = function(x, xpath, attr){
  nodes = xml2::xml_find_all(x, xpath)
  out = xml2::xml_attr(nodes, attr)
  out[!is.na(out)]
}

#' The runspec's domain in upper case ("PROJECT", "DEFAULT", "SINGLE"), or "" if it has none
#' @param .runspec path to the run's runspec (XML)
project_domain = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  x = xml2::read_xml(.runspec)
  value = project_attr(x, "//modeldomain", "value")
  if(length(value) == 0){ return("") }
  toupper(trimws(value[1]))
}

#' Is this a project-scale run?
#' @param .runspec path to the run's runspec (XML)
is_project = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  project_domain(.runspec) == "PROJECT"
}

#' The selections of a project runspec, as a list
#' @param .runspec path to the run's runspec (XML)
#' @return list: geoid, year, month, day, beginhour, endhour (each as found, so possibly several),
#'   hour and hourday (from the first begin hour and day), roadtypes, sourcetypes,
#'   polprocess (pollutant x 100 + process), start_polprocess (those with process 2), processes
project_spec = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  x = xml2::read_xml(.runspec)
  int = function(xpath, attr){ suppressWarnings(as.integer(project_attr(x, xpath, attr))) }

  day = int("//timespan/day", "id")
  beginhour = int("//timespan/beginhour", "id")
  endhour = int("//timespan/endhour", "id")
  pollutant = int("//pollutantprocessassociation", "pollutantkey")
  process = int("//pollutantprocessassociation", "processkey")

  list(
    geoid = int("//geographicselection[@type='COUNTY']", "key"),
    year = int("//timespan/year", "key"),
    month = int("//timespan/month", "id"),
    day = day,
    beginhour = beginhour,
    endhour = endhour,
    hour = beginhour[1],
    hourday = beginhour[1] * 10L + day[1],
    roadtypes = int("//roadtypes/roadtype", "roadtypeid"),
    sourcetypes = sort(unique(int("//onroadvehicleselection", "sourcetypeid"))),
    polprocess = pollutant * 100L + process,
    start_polprocess = sort(unique(pollutant[process == 2] * 100L + 2L)),
    processes = sort(unique(process))
  )
}

#' Stop if a project runspec breaks one of the rules R1 to R10
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder (must hold link.csv)
#' @description Each rule stops with a short message (under 70 characters, no prefix):
#'   run_adapter() in task_adapt.R adds "adapt failed on project runspec: " and writes stop_reason.
#'   MOVES itself refuses several of these but still exits 0, so they are checked here first.
project_check = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  x = xml2::read_xml(.runspec)
  s = project_spec(.runspec)
  one = function(xpath, attr){
    value = project_attr(x, xpath, attr)
    if(length(value) == 0) "none" else value[1]
  }
  same = function(a, b){ tolower(trimws(a)) == tolower(b) }

  # R1 one county, and nothing but a county
  geotypes = project_attr(x, "//geographicselection", "type")
  if(length(geotypes) != 1 || length(s$geoid) != 1 || is.na(s$geoid)){
    stop(paste0("needs exactly one county (found ", length(geotypes), " selections)"))
  }
  # R2 to R4 one year, one month, one day type
  if(length(s$year) != 1){ stop(paste0("needs exactly one year (found ", length(s$year), ")")) }
  if(length(s$month) != 1){ stop(paste0("needs exactly one month (found ", length(s$month), ")")) }
  if(length(s$day) != 1){ stop(paste0("needs exactly one day type (found ", length(s$day), ")")) }
  # R5 one hour
  if(length(s$beginhour) != 1 || length(s$endhour) != 1){ stop("needs one beginhour and one endhour") }
  if(is.na(s$beginhour) || is.na(s$endhour) || s$beginhour != s$endhour){
    stop(paste0("more than one hour (", s$beginhour, " to ", s$endhour, ")"))
  }
  # R6 hourly, not aggregated
  value = one("//timespan/aggregateBy", "key")
  if(!same(value, "hour")){ stop(paste0("aggregateBy must be Hour (found ", value, ")")) }
  value = one("//outputtimestep", "value")
  if(!same(value, "hour")){ stop(paste0("outputtimestep must be Hour (found ", value, ")")) }
  # R7 results by link
  value = one("//geographicoutputdetail", "description")
  if(!same(value, "link")){ stop(paste0("geographicoutputdetail must be LINK (found ", value, ")")) }
  # R8 units that linkdata.csv states
  value = one("//outputfactors/massfactors", "units")
  if(!same(value, "grams")){ stop(paste0("massfactors units must be Grams (found ", value, ")")) }
  value = one("//outputfactors/distancefactors", "units")
  if(!same(value, "miles")){ stop(paste0("distancefactors units must be Miles (found ", value, ")")) }
  value = one("//outputfactors/timefactors", "units")
  if(!same(value, "hours")){ stop(paste0("timefactors units must be Hours (found ", value, ")")) }
  # R9 inventory mode
  value = one("//modelscale", "value")
  if(!same(value, "inv")){ stop(paste0("modelscale must be Inv; rates are not supported (found ", value, ")")) }
  # R10 the custom input database, and the link table
  value = one("//scaleinputdatabase", "databasename")
  if(!same(value, "custom")){ stop(paste0("scaleinputdatabase must be custom (found ", value, ")")) }
  files = tolower(dir(BUCKET))
  if(!"link.csv" %in% files){ stop("link.csv is missing from the inputs folder") }

  invisible(TRUE)
}

#' Stop if MOVES's own input validation is on in a county with no inspection (I/M) programme
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder, after the county adapters have run
#' @description With <skipdomaindatabasevalidation selected="false"/>, MOVES checks every input
#'   table before it runs. A county with no I/M programme has an empty imcoverage table, MOVES
#'   counts that as "not ready", prints no reason, and exits 0 (measured: Washtenaw County, MI,
#'   and Tompkins County, NY, with an empty imcoverage.csv). The MOVES window has a "No I/M
#'   Program" box for this; the command line does not. County run files written by
#'   catr::custom_rs() skip that validation, which is why county runs do not meet this.
project_check_im = function(.runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs"){
  x = xml2::read_xml(.runspec)
  skip = project_attr(x, "//skipdomaindatabasevalidation", "selected")
  validating = length(skip) == 0 || tolower(trimws(skip[1])) != "true"
  if(validating && !"_imcoverage.csv" %in% tolower(dir(BUCKET))){
    stop("no I/M programme here: set skipdomaindatabasevalidation to true")
  }
  invisible(TRUE)
}

# 2. County tables ####

#' Read one county table for a project run, filtered to the run's time
#' @param table table name in lower case, for example "hourvmtfraction"
#' @param .runspec path to the run's runspec (XML)
#' @param BUCKET inputs folder
#' @param default if TRUE, fall back to the default input database when no file is found
#' @param spec result of project_spec(), to avoid reading the runspec again
#' @return a tibble with lower-case column names and an attribute "source":
#'   "adapted" (<BUCKET>/_<table>.csv, written by an adapter), "user" (<BUCKET>/<table>.csv),
#'   or "default" (the default database)
#' @description Order of preference: the adapted file, else the user's own file, else the default
#'   database. Rows are then kept only for the run's year, month, day type, hour and hourDay,
#'   wherever the table has that column. Both halves matter: a user's monthvmtfraction.csv,
#'   dayvmtfraction.csv or hourvmtfraction.csv is written to its _ file unfiltered, and a user's
#'   startsperdaypervehicle.csv or startshourfraction.csv gets no _ file at all.
project_read = function(table, .runspec = "EPA_MOVES_Model/rs_custom.xml", BUCKET = "inputs",
                        default = TRUE, spec = NULL){
  if(is.null(spec)){ spec = project_spec(.runspec) }

  files = dir(BUCKET)
  adapted = files[tolower(files) == paste0("_", table, ".csv")]
  user = files[tolower(files) == paste0(table, ".csv")]

  if(length(adapted) > 0){
    data = readr::read_csv(paste0(BUCKET, "/", adapted[1]), show_col_types = FALSE, progress = FALSE)
    source = "adapted"
  }else if(length(user) > 0){
    .geoidchar = stringr::str_pad(spec$geoid[1], width = 5, side = "left", pad = "0")
    data = get_data(changes = paste0(BUCKET, "/", user[1]), .geoidchar = .geoidchar)
    source = "user"
  }else if(default == TRUE){
    data = get_table(table)
    source = "default"
  }else{
    stop(paste0("no ", table, " table found"))
  }

  data = dplyr::as_tibble(data)
  names(data) = tolower(names(data))

  # Keep only the run's time, wherever the table carries it
  if("yearid" %in% names(data)){ data = data[data$yearid == spec$year[1], ] }
  if("monthid" %in% names(data)){ data = data[data$monthid == spec$month[1], ] }
  if("dayid" %in% names(data)){ data = data[data$dayid == spec$day[1], ] }
  if("hourid" %in% names(data)){ data = data[data$hourid == spec$hour, ] }
  if("hourdayid" %in% names(data)){ data = data[data$hourdayid == spec$hourday, ] }

  attr(data, "source") = source
  return(data)
}

# 3. Which inputs were defaults ####

#' Record where one project input came from, for diagnostics.txt
#' @param item what was filled in, for example "link 5 linkAvgSpeed"
#' @param source "user" or "default"
#' @param detail one short phrase: the value, or the tables the default came from
#' @param BUCKET inputs folder
#' @param reset if TRUE, start the file again (the first call of a run)
project_note = function(item, source, detail = "", BUCKET = "inputs", reset = FALSE){
  path = paste0(BUCKET, "/_project_inputs.csv")
  row = data.frame(item = item, source = source, detail = detail, stringsAsFactors = FALSE)
  if(reset == TRUE || !file.exists(path)){
    readr::write_csv(row, path)
  }else{
    readr::write_csv(row, path, append = TRUE)
  }
  invisible(row)
}

# 4. Make a project runspec ####

#' Turn a county runspec written by catr::custom_rs() into a project runspec, in place
#' @param path path to the runspec (XML) to rewrite
#' @param month month 1 to 12
#' @param day day type: 2 weekend, 5 weekday
#' @param hour hour 1 to 24 (hour 8 is 7:00 to 7:59)
#' @param roadtypes road types to keep (1 off-network, 2 to 5 on-network)
#' @description Sets the domain, one hour, hourly link output, grams / miles / hours, inventory mode and
#'   the output breakdown that rules R1 to R10 need. Keeps only the road types asked for, and only the
#'   processes tested at project scale: running exhaust 1, brakewear 9, tirewear 10, crankcase running 15,
#'   plus (only with road type 1) start 2, crankcase start 16, crankcase extended idle 17, extended idle 90
#'   and auxiliary power 91. Evaporative and refuelling processes are removed.
project_runspec = function(path, month, day, hour, roadtypes){
  x = xml2::read_xml(path)
  roadtypes = as.integer(roadtypes)
  set = function(xpath, ...){
    node = xml2::xml_find_first(x, xpath)
    if(inherits(node, "xml_missing")){ stop(paste0("runspec has no ", xpath)) }
    values = list(...)
    for(name in names(values)){ xml2::xml_set_attr(node, name, values[[name]]) }
  }

  # Domain, scale
  set("//modeldomain", value = "PROJECT")
  set("//modelscale", value = "Inv")

  # Time: the existing year, then exactly one month, day type and hour
  timespan = xml2::xml_find_first(x, "//timespan")
  for(n in xml2::xml_find_all(timespan, "./month | ./day | ./beginhour | ./endhour | ./aggregateBy")){
    xml2::xml_remove(n)
  }
  xml2::xml_add_child(timespan, "month", id = as.character(month))
  xml2::xml_add_child(timespan, "day", id = as.character(day))
  xml2::xml_add_child(timespan, "beginhour", id = as.character(hour))
  xml2::xml_add_child(timespan, "endhour", id = as.character(hour))
  xml2::xml_add_child(timespan, "aggregateBy", key = "Hour")

  # Output: hourly, by link, grams / miles / hours
  set("//outputtimestep", value = "Hour")
  set("//geographicoutputdetail", description = "LINK")
  set("//outputfactors/massfactors", units = "Grams")
  set("//outputfactors/distancefactors", units = "Miles")
  set("//outputfactors/timefactors", units = "Hours")
  for(item in c("emissionprocess", "fueltype", "sourceusetype", "roadtype")){
    set(paste0("//outputemissionsbreakdownselection/", item), selected = "true")
  }

  # Road types
  nodes = xml2::xml_find_all(x, "//roadtypes/roadtype")
  have = suppressWarnings(as.integer(xml2::xml_attr(nodes, "roadtypeid")))
  for(r in roadtypes){
    if(!r %in% have){ stop(paste0("runspec has no road type ", r)) }
  }
  xml2::xml_remove(nodes[!have %in% roadtypes])

  # Processes tested at project scale; starts and idling only where an off-network link exists
  keep = c(1L, 9L, 10L, 15L)
  if(1L %in% roadtypes){ keep = c(keep, 2L, 16L, 17L, 90L, 91L) }
  assoc = xml2::xml_find_all(x, "//pollutantprocessassociations/pollutantprocessassociation")
  process = suppressWarnings(as.integer(xml2::xml_attr(assoc, "processkey")))
  xml2::xml_remove(assoc[!process %in% keep])

  xml2::write_xml(x, path)
  invisible(path)
}
