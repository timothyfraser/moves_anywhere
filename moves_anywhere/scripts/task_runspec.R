# task_runspec.R ##############################################################
#
# What:      Task script to create a runspec .xml file
# Does:      Makes a county-level, annual runspec for GEOID and YEAR with catr::custom_rs(). With
#            LEVEL=project it makes a project-scale runspec instead: one county, year, month, day type
#            and hour (MONTH, DAY, HOUR), road types from ROADTYPES or inputs/link.csv, and checks it
#            against rules R1 to R10 when inputs/link.csv exists.
# Called by: Developer tool: make a runspec at launch. Run by launch_runspec.sh; launch.sh does not run it.
# Reads:     environment variables GEOID and YEAR (both required); LEVEL (optional, "project");
#            for a project runspec also MONTH, DAY, HOUR (required), ROADTYPES (optional) and inputs/link.csv
# Writes:    inputs/rs_custom.xml
# Needs:     catr; working directory /cat; for a project runspec also xml2, readr and scripts/project_functions.R
###############################################################################

# Loda packages
setwd("/cat")
library(catr, warn.conflicts = FALSE, quietly = TRUE)

GEOID = Sys.getenv("GEOID")
YEAR = as.integer(Sys.getenv("YEAR"))

if(nchar(GEOID) == 0){ stop("GEOID is required environmental variable. Stopping...") }
if(nchar(YEAR) == 0){ stop("YEAR is required environmental variable. Stopping...") }

LEVEL = tolower(Sys.getenv("LEVEL"))

if(LEVEL == "project"){
  # Project scale: read and check MONTH, DAY, HOUR, ROADTYPES
  int_env = function(name){ suppressWarnings(as.integer(Sys.getenv(name))) }
  MONTH = int_env("MONTH")
  DAY = int_env("DAY")
  HOUR = int_env("HOUR")
  if(is.na(MONTH) || !MONTH %in% 1:12){ stop("MONTH is required: 1 to 12") }
  if(is.na(DAY) || !DAY %in% c(2, 5)){ stop("DAY is required: 2 (weekend) or 5 (weekday)") }
  if(is.na(HOUR) || !HOUR %in% 1:24){ stop("HOUR is required: 1 to 24 (8 is 7:00 to 7:59)") }

  roadtypes = trimws(strsplit(Sys.getenv("ROADTYPES"), ",")[[1]])
  roadtypes = roadtypes[nchar(roadtypes) > 0]
  if(length(roadtypes) == 0){
    # No ROADTYPES: take them from the link table
    if(!file.exists("inputs/link.csv")){ stop("ROADTYPES is required when inputs/link.csv is absent") }
    link = read.csv("inputs/link.csv", check.names = FALSE, stringsAsFactors = FALSE)
    column = which(tolower(names(link)) == "roadtypeid")
    if(length(column) == 0){ stop("inputs/link.csv has no roadTypeID column") }
    roadtypes = unique(link[[column[1]]])
  }
  roadtypes = suppressWarnings(as.integer(roadtypes))
  if(length(roadtypes) == 0 || anyNA(roadtypes) || !all(roadtypes %in% 1:5)){
    stop("ROADTYPES must be a list of road types from 1 to 5")
  }
  roadtypes = sort(unique(roadtypes))

  # Make the base runspec, then turn it into a project runspec
  catr::custom_rs(
    .geoid = GEOID, .year = YEAR, .pollutants = c(98, 3, 2, 31, 33, 110, 100, 106, 107, 116, 117),
    .rate = FALSE, .level = "county", .geoaggregation = "link", .timeaggregation = "hour",
    .path = "inputs/rs_custom.xml"
  )
  source("scripts/project_functions.R")
  project_runspec("inputs/rs_custom.xml", MONTH, DAY, HOUR, roadtypes)
  # Show a rule failure now, not at run time
  if(file.exists("inputs/link.csv")){ project_check("inputs/rs_custom.xml", BUCKET = "inputs") }
}else{
  # Make the runspec
  catr::custom_rs(
    .geoid = GEOID, .year = YEAR, .pollutants = c(98, 3, 2, 31, 33, 110, 100, 106, 107, 116, 117),
    .rate = FALSE, .level = "county", .geoaggregation = "county", .timeaggregation = "year",
    .path = "inputs/rs_custom.xml"
  )
}

# Close R
q(save = "no")
