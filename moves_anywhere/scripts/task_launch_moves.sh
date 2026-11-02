#!/bin/bash

# task_launch_moves.sh

# Script to launch MOVES

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
echo ------------running runspec------------
sudo -u mysql ant run -Drunspec="/cat/EPA_MOVES_Model/rs_custom.xml"

# Jump Backwards in File Directory, back to /cat/
cd "/cat"

