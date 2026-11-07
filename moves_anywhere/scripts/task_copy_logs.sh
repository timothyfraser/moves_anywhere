#!/bin/bash
# task_copy_logs.sh ############################################################
#
# What:      Script to copy logs from MOVES to the inputs/ folder,
#            so that the logs persist in mounted volume after job ends.
# Does:      Copies EPA_MOVES_Model/moveslog.txt to inputs/moveslog.txt.
# Called by: launch.sh, step 12 of launch.sh (sourced)
# Reads:     /cat/EPA_MOVES_Model/moveslog.txt
# Writes:    /cat/inputs/moveslog.txt
# Exits:     1 if it cannot change directory, no logs exist, or folder 'inputs/' does not exist
###############################################################################

# Log results
echo ------------logging moveslog.txt------------

# working directory should be /cat/
cd "/cat" || { echo "Failed to change directory"; exit 1; }

# Set names
FOLDER_A="EPA_MOVES_Model"
FOLDER_B="inputs"
FILE="moveslog.txt"

# Check if logs file exists
if [ ! -f  "$FOLDER_A/$FILE" ]; then
  echo "---No logs exist at $FOLDER_A/$FILE."; 
  exit 1 # exit with error
fi

# Check if inputs folder exists
if [ ! -d "$FOLDER_B" ]; then
  echo "---Folder 'inputs/' does not exist. No logs copied."; 
  exit 1; # exit
fi

# If you made it this far, then copy it.
cp "EPA_MOVES_Model/moveslog.txt" "inputs/moveslog.txt"
echo "---Logs copied to folder inputs/"

