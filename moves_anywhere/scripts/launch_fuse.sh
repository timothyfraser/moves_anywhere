#!/bin/bash
# launch_fuse.sh ##############################################################
#
# What:      A script to run MOVES ANYWHERE in the cloud at launch,
#            initiating Google Cloud Storage FUSE.
# Does:      Mounts the inputs bucket with gcsfuse (task_fuse.sh), then runs the v2 steps in order:
#            setenv, packages, mysql, adapt, database, inputs, importer, MOVES, postprocess, logs, summary.
# Called by: Not used by v3. Legacy (v2, Google Cloud): launch script for a cloud run with gcsfuse.
#            v3 runs launch.sh instead.
# Reads:     the bucket named in $BUCKET, mounted at /cat/inputs
# Writes:    whatever the task scripts it runs write (database, outputs, logs)
# Exits:     0 at the end; 1 earlier if a sourced task script exits 1 (for example task_fuse.sh)
###############################################################################

# Mount inputs folder from bucket with GCSFUSE
. "scripts/task_fuse.sh"

# Check for contents of inputs folder
. "scripts/task_check_inputs.sh"

# Check for contents of inputs folder
. "scripts/task_copy_runspec.sh"

# Modify and run setenv.sh file
echo ------------running setenv------------
chmod 777 /cat/EPA_MOVES_Model/setenv.sh
. /cat/EPA_MOVES_Model/setenv.sh

# Modify and run setenv.R file
Rscript "scripts/setenv.R"

# Check if all R packages are installed.
Rscript "scripts/task_install_catr.R"

# Check if all R packages are installed.
Rscript "scripts/task_check_packages.R"

# Start up mysql
. "scripts/task_start_mysql.sh"

# Initiate the adapt protocol
Rscript "scripts/task_adapt.R"

# Create custom database
Rscript "scripts/task_db_create.R"

# Copy inputs into EPA_MOVES_Model (customized for gcsfuse)
. "scripts/task_copy_inputs.sh"

# Create importer script (customized for gcsfuse)
Rscript "scripts/task_create_importer_fuse.R"

# Import tables into newly created database
. "scripts/task_importer.sh"

# Copy MOVES logs into inputs bucket
. "scripts/task_launch_moves.sh"


# Postprocess MOVES output data in R
Rscript "scripts/task_postprocess.R"

# Copy MOVES logs into inputs bucket
. "scripts/task_copy_logs.sh"

# Summarize results quickly for diagnostics
Rscript "scripts/task_summarize.R"

# Finishup
exit 0 # Exit without error
