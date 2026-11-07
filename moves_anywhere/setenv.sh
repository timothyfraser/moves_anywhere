#!/bin/sh
# setenv.sh ###################################################################
#
# What:      Java and Ant environment for MOVES.
# Does:      Exports PATH (jre/bin, ant/bin), JAVA_TOOL_OPTIONS, ANT_OPTS, JAVA_HOME and JRE_HOME.
# Called by: setupdb.sh at image build (the Dockerfile copies it to EPA_MOVES_Model/setenv.sh).
#            Not run by launch.sh.
# Reads:     nothing
# Writes:    environment variables of the shell that sources it
# Exits:     none (sourced)
###############################################################################

export PATH=jre/bin:ant/bin:$PATH
export JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8
export ANT_OPTS=-XX:-UseGCOverheadLimit
#For running on Git Bash with windows, ensure that JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 is uncommented and JAVA_HOME=/usr is commented
#export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export JAVA_HOME=/usr
export JRE_HOME=jre
