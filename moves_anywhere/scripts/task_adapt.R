# task_adapt.R ################################################################
#
# What:      Runs the adapt protocol: adapts the MOVES input tables for this run.
# Does:      Sources adapt_functions.R and each adapt_*.R script, then runs their adapt_*()
#            functions in order on the runspec, from identifiers to climate. Each group runs
#            inside run_adapter(): on an error it writes /cat/run/stop_reason ("adapt failed on
#            <name>: <first error line>"), prints the full error, and exits with status 1.
# Called by: launch.sh, step 6 of launch.sh
# Reads:     EPA_MOVES_Model/rs_custom.xml; inputs/; the MOVES default database named in the runspec
# Writes:    adapted tables as files in inputs/ (through the adapt_* scripts);
#            /cat/run/stop_reason if an adapter fails
# Needs:     scripts/adapt_functions.R, scripts/adapt_*.R;
#            packages catr, DBI, RMariaDB, dplyr, readr
###############################################################################

# Script to get a vector of csvs

# Testing values
# FOLDER=paste0(rstudioapi::getActiveProject(), "/moves_anywhere")
# BUCKET=paste0(rstudioapi::getActiveProject(), "/moves_anywhere/inputs_ny")
# R

# Message start
cat("\n\n---ADAPTING INPUT TABLES------------------\n")

# Runtime Variables
FOLDER="/cat/"
BUCKET="inputs"
.runspec = "EPA_MOVES_Model/rs_custom.xml"
.volume=BUCKET

# Set working directory to /cat/
setwd(FOLDER)

# Load packages
library(catr, warn.conflicts = FALSE,  quietly = TRUE)
library(DBI, warn.conflicts = FALSE, quietly = TRUE)
library(RMariaDB, warn.conflicts = FALSE,  quietly = TRUE)
library(dplyr, warn.conflicts = FALSE, quietly = TRUE)
library(readr, warn.conflicts = FALSE, quietly = TRUE)
# Load functions
source("scripts/adapt_functions.R")

# Run one adapter group; on error, record why and stop the run with status 1 (read by launch.sh)
run_adapter = function(name, expr){
  tryCatch(force(expr), error = function(e){
    full = conditionMessage(e)
    msg = paste0("adapt failed on ", name, ": ", strsplit(full, "\n")[[1]][1])
    msg = substr(msg, 1, 110)
    if(dir.exists("/cat/run")){ writeLines(msg, "/cat/run/stop_reason", sep = "") }
    message(paste0("ERROR: adapt failed on ", name, ": ", gsub("[[:space:]]*\n[[:space:]]*", " | ", full)))
    quit(save = "no", status = 1)
  })
}

# IDENTIFIERS ####################################
cat("\n\n---IDENTIFER TABLES----------------------\n")
run_adapter("adapt_ids", {
  source("scripts/adapt_ids.R")
  adapt_ids(.runspec = .runspec)
})

## FUEL ###############################################
cat("\n\n---FUELS----------------------------------\n")
run_adapter("fuel", {
  source("scripts/adapt_fuel.R")
  adapt_fuelformulation(.runspec = .runspec)
  adapt_fuelsupply(.runspec = .runspec)
  adapt_fuelusagefraction(.runspec = .runspec)
  adapt_avft(.runspec = .runspec)
})


# SOURCETYPE YEAR #################################
cat("\n\n---VEHICLE POPULATION TABLES----------------------\n")

# Skip using raw defaults
# source("scripts/adapt_sourcetypeyear.R")
# adapt_sourcetypeyear(.runspec = .runspec)

# Instead, adapt from NEI MOVES Input data
run_adapter("sourcetypeyear", {
  source("scripts/adapt_from_nei.R")
  source("scripts/adapt_sourcetypeyear2.R")
  adapt_sourcetypeyear2(.runspec = .runspec)
})


# VMT #################################
cat("\n\n---VEHICLE VMT TABLES----------------------\n")

# Skip using raw defaults
# source("scripts/adapt_vmt.R")
# adapt_vmt(.runspec = .runspec)

# Instead adapt from NEI MOVES Input data
run_adapter("vmt", {
  source("scripts/adapt_from_nei.R")
  source("scripts/adapt_vmt2.R")
  adapt_vmt2(.runspec = .runspec)
})



# VMT FRACTIONS ########################################
cat("\n\n---VMT FRACTION TABLES----------------------\n")
run_adapter("vmtfraction", {
  source("scripts/adapt_vmtfraction.R")
  adapt_dayvmtfraction(.runspec = .runspec)
  adapt_hourvmtfraction(.runspec = .runspec)
  adapt_monthvmtfraction(.runspec = .runspec)
})

## AGE DISTRIBUTION ####################################
cat("\n\n---AGE DISTRIBUTION TABLES----------------------\n")
run_adapter("sourcetypeagedistribution", {
  source("scripts/adapt_sourcetypeagedistribution.R")  
  adapt_sourcetypeagedistribution(.runspec = .runspec)
})


## SPEED DISTRIBUTION ##################################
cat("\n\n---AVG SPEED DISTRIBUTION TABLES----------------------\n")
run_adapter("avgspeeddistribution", {
  source("scripts/adapt_avgspeeddistribution.R")
  adapt_avgspeeddistribution(.runspec = .runspec)
})


## ROADTYPE VMT ########################################
cat("\n\n---ROADTYPE DISTRIBUTION TABLES-----------------------\n")
run_adapter("roadtypedistribution", {
  source("scripts/adapt_roadtypedistribution.R")
  adapt_roadtypedistribution(.runspec = .runspec)
})


## STARTS ##############################################
cat("\n\n---STARTS TABLES-----------------------------\n")
run_adapter("starts", {
  source("scripts/adapt_starts.R")
  adapt_startshourfraction(.runspec = .runspec)
  adapt_starts(.runspec = .runspec)
  adapt_startsperday(.runspec = .runspec)
  adapt_startsperdaypervehicle(.runspec = .runspec)
})

run_adapter("startsopmodedistribution", {
  source("scripts/adapt_startsopmodedistribution.R")
  adapt_startsopmodedistribution(.runspec = .runspec)
})


## HOTELLING ############################################
cat("\n\n---HOTELLING TABLES-----------------------\n")
run_adapter("hotelling", {
  source("scripts/adapt_hotellingactivitydistribution.R")
  adapt_hotellingactivitydistribution(.runspec = .runspec)
})


## IDLING ##############################################
cat("\n\n---IDLING TABLES--------------------------\n")
run_adapter("totalidlefraction", {
  source("scripts/adapt_totalidlefraction.R")
  adapt_totalidlefraction(.runspec = .runspec)
})

## IM PROGRAMS ##########################################
cat("\n\n---IM PROGRAM TABLES------------------------\n")
run_adapter("imcoverage", {
  source("scripts/adapt_imcoverage.R")
  adapt_imcoverage(.runspec = .runspec)
})

## CLIMATE ##############################################
cat("\n\n---CLIMATE TABLES---------------------------\n")
run_adapter("zonemonthhour", {
  source("scripts/adapt_zonemonthhour.R")
  adapt_zonemonthhour(.runspec = .runspec)
})


## CLEANUP ############################################
gc() # clear cache
cat("\n---done!---------------------------\n")


# Close
q(save = "no")
