# setenv.R ####################################################################
#
# What:      R version of a .env file: database and folder settings
# Does:      Sets the database and folder environment variables for an R session.
# Called by: Not used by v3. Legacy v2 environment settings (names movesdb20240104, an older database).
# Reads:     nothing
# Writes:    environment variables only
# Needs:     nothing
###############################################################################
Sys.setenv("OUTPUTDBNAME"="moves")
Sys.setenv("INPUTDBNAME"="movesdb20240104")
Sys.setenv(MDB_USERNAME="moves")
Sys.setenv(MDB_PASSWORD="moves")
Sys.setenv(MDB_PORT="3306")
Sys.setenv(MDB_HOST="localhost")
Sys.setenv(MDB_DEFAULT="movesdb20240104")
Sys.setenv(MOVES_FOLDER="/EPA_MOVES_Model")
Sys.setenv(TEMP_FOLDER=".")
