#!/bin/bash
# task_start_mysql.sh #########################################################
#
# What:      Script to launch MySQL
# Does:      Starts the mysql service, then waits until mysqladmin ping answers.
# Called by: launch.sh, step 5 of launch.sh (sourced)
# Reads:     nothing
# Writes:    nothing (starts the MySQL service)
# Exits:     no exit of its own; it waits until MySQL answers ping
###############################################################################

# Start MySQL Service #############################
echo -----------starting MySQL service----------------
service mysql start

# Wait for mysql to start up
while ! mysqladmin ping --silent; do
    sleep 1
done



