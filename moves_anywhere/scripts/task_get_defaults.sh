#!/bin/bash
# task_get_defaults.sh ########################################################
#
# What:      Script to get several key default input tables from MOVES
# Does:      Starts R; the lines after `R` are R code that write fuelsupply, fuelformulation and
#            fuelusagefraction from the default MOVES database to CSV files.
# Called by: Developer tool: dump default MOVES tables, not part of a run.
# Reads:     default MOVES database movesdb20241112 (MariaDB, through catr::connect)
# Writes:    scripts/defaults/<table>.csv
# Exits:     no exit code set
###############################################################################
R
# Load packages
library(dplyr)
library(readr)
library(dbplyr)
library(DBI)
library(RMariaDB)
library(catr)

# folder = "scripts/defaults"

get_table = function(table, folder = "scripts/defaults", defaultdb = "movesdb20241112"){ 
  # Make a folder of defaults
  dir.create(folder, showWarnings = FALSE)
  # Connect to database
  db = catr::connect("mariadb", defaultdb)
  # Collect table
  data = db %>% tbl(table) %>% collect()
  # Disconnect
  dbDisconnect(db)
  # Write to file
  write_csv(data, file = paste0(folder, "/", table, ".csv"))
  # Status message
  cat(paste0("\n---downloaded: ", table, "----------------", "\n"))
}


get_table(table = "fuelsupply")
get_table(table = "fuelformulation")
get_table(table = "fuelusagefraction")

# Close out of R
q(save = "no")
