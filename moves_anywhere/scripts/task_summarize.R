# task_summarize.R #############################################################
#
# What:      Summarize results quickly for diagnostics
# Does:      Inventory runs: write CO2e Emissions (98) and Vehicle Population to
#            inputs/diagnostics.txt, or remove it if either output .csv is missing.
#            Project-scale runs: write a per-link table (miles, CO2, NOx, starts) and the list of
#            inputs filled in by default, from inputs/linkdata.csv.
# Called by: launch.sh, step 13 of launch.sh
# Reads:     inputs/rs_custom.xml, inputs/movesoutput.csv, inputs/movesactivityoutput.csv;
#            project runs: inputs/linkdata.csv, inputs/_link.csv, inputs/_project_inputs.csv
# Writes:    inputs/diagnostics.txt
# Needs:     dplyr, readr, catr, scripts/project_functions.R, scripts/task_get_linkdata.R
###############################################################################

# Set working directory
setwd("/cat")

# Load packages
library(dplyr, warn.conflicts = FALSE, quietly = TRUE)
library(readr, warn.conflicts = FALSE, quietly = TRUE)
library(catr, warn.conflicts = FALSE, quietly = TRUE)
source("scripts/project_functions.R")
source("scripts/task_get_linkdata.R")


FOLDER = "inputs"

# Get runspec metadata
rs = catr::translate_rs(.runspec = paste0(FOLDER, "/rs_custom.xml"))

if(rs$mode == "inv"){
  
  if(is_project(paste0(FOLDER, "/rs_custom.xml"))){
    
    # Project-scale run: one line per link, then the inputs that were filled in
    lpath = paste0(FOLDER, "/linkdata.csv")
    if(file.exists(lpath)){
      lk = read_csv(paste0(FOLDER, "/_link.csv"), show_col_types = FALSE)
      s = linkdata_summary(linkdata = read_csv(lpath, show_col_types = FALSE), link = lk)
      # A real CSV table, so a comma in a link's description cannot shift the columns
      table = data.frame(
        link = s$link, roadtype = s$roadtype,
        description = ifelse(is.na(s$description), "", as.character(s$description)),
        miles = round(s$miles, 3), co2_g = round(s$co2, 1), nox_g = round(s$nox, 1),
        co2_g_per_mile = round(s$co2_per_mile, 1), nox_g_per_mile = round(s$nox_per_mile, 3),
        starts = round(s$starts, 1))
      lines = c(
        "Project-scale run: one hour, results by link (grams, miles)",
        strsplit(readr::format_csv(table, na = ""), "\n")[[1]])
      # A road link at 0 mph is easy to misread: say what MOVES did with it
      still = lk$linkID[lk$roadTypeID != 1 & !is.na(lk$linkAvgSpeed) & lk$linkAvgSpeed == 0]
      if(length(still) > 0){
        lines = c(lines, "", paste0(
          "Note: link ", still, " has speed 0. MOVES counts every vehicle in its volume as idling ",
          "for the whole hour. Scale its grams by the real delay."))
      }
      ipath = paste0(FOLDER, "/_project_inputs.csv")
      if(file.exists(ipath)){
        pin = read_csv(ipath, show_col_types = FALSE)
        lines = c(lines, "", "Inputs filled in by default or supplied by you:",
                  paste(pin[[1]], pin[[2]], pin[[3]], sep = " | "))
      }
      write_lines(x = lines, file = paste0(FOLDER, "/diagnostics.txt"))
    }else{
      # No link results: do not leave an earlier run's diagnostics in the folder
      unlink(paste0(FOLDER, "/diagnostics.txt"), force = TRUE)
    }
    
  }else{
  
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
