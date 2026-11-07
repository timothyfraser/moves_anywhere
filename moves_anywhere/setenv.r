# setenv.r ####################################################################
#
# What:      Environment settings for the MOVES databases, in R.
# Does:      Sys.setenv() for OUTPUTDBNAME, INPUTDBNAME, the MDB_* connection settings, MOVES_FOLDER
#            and TEMP_FOLDER. Same content as scripts/setenv.R; names movesdb20240104.
# Called by: Not used by v3. Legacy environment settings; no script sources this file.
# Reads:     nothing
# Writes:    environment variables of the R session
# Needs:     base R
###############################################################################

# .env
Sys.setenv("OUTPUTDBNAME"="moves")
Sys.setenv("INPUTDBNAME"="movesdb20240104")
Sys.setenv(MDB_USERNAME="moves")
Sys.setenv(MDB_PASSWORD="moves")
Sys.setenv(MDB_PORT="3306")
Sys.setenv(MDB_HOST="localhost")
Sys.setenv(MDB_DEFAULT="movesdb20240104")
Sys.setenv(MOVES_FOLDER="/EPA_MOVES_Model")
Sys.setenv(TEMP_FOLDER=".")
