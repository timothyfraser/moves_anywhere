# task_create_importer.R #######################################################
#
# What:      Script to create an importer.xml file
# Does:      Runs create_importer() from importer.R on the inputs/ folder, for normal
#            use in Docker (not the FUSE bucket mount).
# Called by: launch.sh, step 8 of launch.sh
# Reads:     inputs/rs_custom.xml, inputs/ input tables (_*.csv), scripts/importer_template.xml
# Writes:    inputs/importer.xml
# Needs:     scripts/importer.R; catr, DBI, RMariaDB, dplyr, dbplyr
###############################################################################

# R # start R, if needed
# Load packages
library(catr, warn.conflicts = FALSE,  quietly = TRUE)
library(DBI, warn.conflicts = FALSE, quietly = TRUE)
library(RMariaDB, warn.conflicts = FALSE,  quietly = TRUE)
library(dplyr, warn.conflicts = FALSE, quietly = TRUE)
library(dbplyr, warn.conflicts = FALSE, quietly = TRUE)

# Set directory
setwd("/cat/")
# Load the importer
source("scripts/importer.R")

# Create importer, for NORMAL use in Docker 
# when not mounting bucket by FUSE
path_importer = create_importer(
  BUCKET = "inputs", 
  SOURCE = "scripts", 
  dir = "/cat")

cat("\n---created importer.xml file...\n")

# Close R
q(save = "no")
