#!/bin/bash
# task_copy_runspec.sh ########################################################
#
# What:      Script to copy runspec from /inputs/ into EPA_MOVES_Model folder.
# Does:      Copies /cat/inputs/rs_custom.xml to /cat/EPA_MOVES_Model/rs_custom.xml; stops if it is missing.
# Called by: launch.sh, step 3 of launch.sh (sourced, so an exit here ends launch.sh)
# Reads:     /cat/inputs/rs_custom.xml
# Writes:    /cat/EPA_MOVES_Model/rs_custom.xml
# Exits:     1 if /cat cannot be entered or rs_custom.xml is not in inputs/
###############################################################################


# Message
echo ------------copying runspec------------

# Set working direcory
cd "/cat" || { echo "Failed to change directory"; exit 1; }

# The runspec should ALWAYS be named rs_custom.xml
FOLDER_A="inputs"
FOLDER_B="EPA_MOVES_Model"
RS="rs_custom.xml"


# If the file is NOT in inputs, then STOP!
if [ ! -f "$FOLDER_A/$RS" ]; then
  echo "---$RS file not found in folder $FOLDER_A..."
  exit 1 # error
fi

# Otherwise....
# Copy from folder A to folder B
cp "$FOLDER_A/$RS" "$FOLDER_B/$RS"

# Message completion
echo "---runspec copied to folder $FOLDER_B/"
