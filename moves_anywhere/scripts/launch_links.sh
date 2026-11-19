#!/bin/bash
# launch_links.sh #############################################################
#
# What:      A script to build the link table of a project-scale run with MOVES ANYWHERE at launch.
# Does:      Copies the run file into place, starts MariaDB, checks the R packages (task_check_packages.R),
#            then builds the links (task_links.R). No MOVES run, no pack, no push.
# Called by: links.sh (docker run ... /cat/scripts/launch_links.sh)
# Reads:     /cat/inputs/rs_custom.xml; environment variables PLACE, STATE, MAX_LINKS, MA_FILL_REMAINDER, OVERWRITE (in task_links.R)
# Writes:    /cat/EPA_MOVES_Model/rs_custom.xml; link.csv, link_summary.txt and the other link files in /cat/inputs (in task_links.R)
# Exits:     1 if rs_custom.xml is not in the inputs folder; 2 if R packages are missing; otherwise the exit status of task_links.R
###############################################################################

cd /cat || { echo "links: cannot enter /cat"; exit 1; }
mkdir -p /cat/run

if [ ! -f /cat/inputs/rs_custom.xml ]; then
  echo "links: no rs_custom.xml in the inputs folder"
  exit 1
fi

# Copy runspec
. "scripts/task_copy_runspec.sh"

# Start MariaDB
. "scripts/task_start_mysql.sh"

# Check if all R packages are installed.
Rscript "scripts/task_check_packages.R" || exit 2

# Build the links
Rscript "scripts/task_links.R"
exit $?
