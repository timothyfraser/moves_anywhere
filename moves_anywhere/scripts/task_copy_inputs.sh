#!/bin/bash
# task_copy_inputs.sh #########################################################
#
# What:      We're going to copy inputs from the /cat/inputs/ folder,
#            into the /cat/EPA_MOVES_Model/inputs folder
# Does:      Copies the customized tables (_*.csv) into /cat/EPA_MOVES_Model/inputs/,
#            then lists _sourcetypeagedistribution.csv to verify the copy.
# Called by: Not used by v3. Legacy (v2, Google Cloud): launch_fuse.sh, after task_db_create.R
#            (copy inputs from the gcsfuse mount).
# Reads:     /cat/inputs/_*.csv
# Writes:    /cat/EPA_MOVES_Model/inputs/
# Exits:     no exit code set; sourced, so the run continues
###############################################################################

# Set working directory
cd "/cat"

# Make new directory
mkdir "/cat/EPA_MOVES_Model/inputs"

# Copy all of the customized tables into new directory
cp /cat/inputs/_*.csv /cat/EPA_MOVES_Model/inputs/

# Messaging
echo "✅ Verifying key file exists:"
ls -l /cat/EPA_MOVES_Model/inputs/_sourcetypeagedistribution.csv

# Messaging
echo "-----finished copying inputs to runtime directory-------"
