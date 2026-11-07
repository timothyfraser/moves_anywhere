# task_summarize.R #############################################################
#
# What:      Summarize results quickly for diagnostics
# Does:      Inventory runs: write CO2e Emissions (98) and Vehicle Population to
#            inputs/diagnostics.txt, or remove it if either output .csv is missing.
# Called by: launch.sh, step 13 of launch.sh
# Reads:     inputs/rs_custom.xml, inputs/movesoutput.csv, inputs/movesactivityoutput.csv
# Writes:    inputs/diagnostics.txt
# Needs:     dplyr, readr, catr
###############################################################################

# Set working directory
setwd("/cat")

# Load packages
library(dplyr, warn.conflicts = FALSE, quietly = TRUE)
library(readr, warn.conflicts = FALSE, quietly = TRUE)
library(catr, warn.conflicts = FALSE, quietly = TRUE)


FOLDER = "inputs"

# Get runspec metadata
rs = catr::translate_rs(.runspec = paste0(FOLDER, "/rs_custom.xml"))

if(rs$mode == "inv"){
  
  epath = paste0(FOLDER, "/movesoutput.csv")
  if(file.exists(epath)){
    e = epath  %>%
      read_csv(show_col_types = FALSE) %>%
      filter(pollutantID == 98)
    if(nrow(e) > 0){
      e = e %>%
        summarize(emissions = sum(emissionQuant, na.rm = TRUE)) %>%
        with(emissions)
    }else{
      e = NA_character_
    }
  }
  
  apath = paste0(FOLDER, "/movesactivityoutput.csv")
  
  
  if(file.exists(apath)){
    a = apath %>% 
      read_csv(show_col_types = FALSE) %>%
      filter(activityTypeID == 6)
    if(nrow(a) > 0){
      a = a %>%
        summarize(activity = sum(activity, na.rm = TRUE)) %>%
        with(activity)
    }else{
      a = NA_character_
    }
  }
  
  dpath = paste0(FOLDER, "/diagnostics.txt")
  if(file.exists(epath) & file.exists(apath)){
    write_lines(
      x = c(
        paste0("CO2e Emissions (98): ", round(e,1) ),
        paste0("Vehicle Population: ", round(a, 1) )
      ),
      file = dpath
    )
  }else{
    unlink(dpath, force = TRUE)
  }
  
}
 
# setwd(paste0(rstudioapi::getActiveProject(), "/moves_anywhere"))
# FOLDER="inputs_ny"
# path = paste0(FOLDER, "/_sourcetypeyear.csv")
# path %>% read_csv() %>%
#   summarize(vehicles = sum(sourceTypePopulation))
# catr::translate_rs(.runspec = paste0(FOLDER, "/rs_custom.xml"))
  
  
rm(list = ls())

# Close out of script
q(save = "no")