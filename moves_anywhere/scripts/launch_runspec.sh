#!/bin/bash
# launch_runspec.sh ###########################################################
#
# What:      A script to make a runspec with MOVES ANYWHERE at launch.
# Does:      Checks the R packages (task_check_packages.R), then creates the runspec (task_runspec.R).
#            The other steps are commented out.
# Called by: Developer tool: make a runspec at launch, not part of a run. testme.sh runs it.
# Reads:     environment variables GEOID and YEAR (in task_runspec.R)
# Writes:    /cat/inputs/rs_custom.xml (in task_runspec.R)
# Exits:     0 at the end
###############################################################################

# Check for contents of inputs folder
# . "scripts/task_check_inputs.sh"

# Check for contents of inputs folder
# . "scripts/task_copy_runspec.sh"

# Check if all R packages are installed.
# Rscript "scripts/task_install_catr.R"

# Check if all R packages are installed.
Rscript "scripts/task_check_packages.R"

# Create the runspec
Rscript "scripts/task_runspec.R"

# Finishup
exit 0 # Exit without error
