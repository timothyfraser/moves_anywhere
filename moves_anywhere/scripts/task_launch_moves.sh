#!/bin/bash
# task_launch_moves.sh #########################################################
#
# What:      Script to launch MOVES
# Does:      Runs the CUSTOM runspec (rs_custom.xml) with MOVES as the mysql user;
#            debug mode (keepDebugData) only when the run opts in.
# Called by: launch.sh, step 10 of launch.sh (sourced)
# Reads:     /cat/EPA_MOVES_Model/rs_custom.xml, MOVESConfiguration.txt, /cat/inputs/parameters.json ("debug")
# Writes:    MOVES output database; EPA_MOVES_Model/moveslog.txt; MOVESConfiguration.txt (edited in place)
# Exits:     1 if it cannot change directory
###############################################################################

# 3. MOVES Setup ###################################
cd "/cat/EPA_MOVES_Model" || { echo "Failed to change directory"; exit 1; }

# Editing MOVES Configuration generator path
echo ------------editing MOVESConfiguration.txt------------
sed -i 's|\\|/|g' MOVESConfiguration.txt


# Ensure that the output of these two match: 
#   which java should have the same path as $JAVA_HOME, but with /bin/java at the end
which java
echo $JAVA_HOME

# Changing to mysql user and running the CUSTOM runspec
# Debug mode (D29): off by default; a run opts in with "debug": true in parameters.json or MOVES_DEBUG=1.
if [ "${MOVES_DEBUG:-0}" = "1" ] || grep -Eq '"debug"[[:space:]]*:[[:space:]]*true' /cat/inputs/parameters.json 2>/dev/null; then
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Dmoves.keepDebugData=true"
  echo "------------debug mode ON (keepDebugData)------------"
fi
echo ------------running runspec------------
sudo -u mysql ant run -Drunspec="/cat/EPA_MOVES_Model/rs_custom.xml"

# Jump Backwards in File Directory, back to /cat/
cd "/cat"

