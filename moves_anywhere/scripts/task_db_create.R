# task_db_create.R ############################################################
#
# What:      Creates the custom input database.
# Does:      Connects to MariaDB and runs CREATE DATABASE IF NOT EXISTS custom.
#            The output database and table schema steps below are commented out.
# Called by: launch.sh, step 7 of launch.sh
# Reads:     nothing (connects to the local MariaDB server)
# Writes:    MariaDB database custom
# Needs:     packages catr, DBI, RMariaDB, dplyr, dbplyr
###############################################################################

# R # start R, if needed

# Load packages
library(catr, warn.conflicts = FALSE,  quietly = TRUE)
library(DBI, warn.conflicts = FALSE, quietly = TRUE)
library(RMariaDB, warn.conflicts = FALSE,  quietly = TRUE)
library(dplyr, warn.conflicts = FALSE, quietly = TRUE)
library(dbplyr, warn.conflicts = FALSE, quietly = TRUE)

# CREATE OUTPUT DATABASE ############################################

# # Connect to mariadb 
# db = connect("mariadb")
# 
# # Test
# # db %>% tbl(in_schema("moves", "movesoutput"))
# 
# # Initialize database custom
# dbExecute(conn = db, statement = "CREATE DATABASE IF NOT EXISTS moves;")
# 
# # Disconnect
# dbDisconnect(db)
# 
# cat("\n---output database created...\n")
# 
# # ADD TABLE SCHEMA ###################################################
# 
# # Add Tables for MOVES Outputs
# # Connect to newly made output database
# db = connect("mariadb", "moves")
# # Read SQL file with commands to initialize each table
# sql = readLines("scripts/CreateOutput.sql")
# # Reformat into a vector
# sql = paste0(unlist(strsplit(paste0(sql, collapse = "\n"), ';')), ";")
# # Initialize each table
# for(i in 1:length(sql)){ dbExecute(conn = db, statement = sql[i])  }
# 
# cat("\n---moves output table schemas added...\n")
# 
# # Repeat for Output Rates
# # Read SQL file with commands to initialize each table
# sql = readLines("scripts/CreateOutputRates.sql")
# # Reformat into a vector
# sql = paste0(unlist(strsplit(paste0(sql, collapse = "\n"), ';')), ";")
# # Initialize each table
# for(i in 1:length(sql)){ dbExecute(conn = db, statement = sql[i])  }
# 
# # Disconnect
# dbDisconnect(db)
# 
# cat("\n---moves output rate table schemas added...\n")



# CREATE INPUT DATABASE ###############################

# Connect to mariadb 
db = connect("mariadb")

# Initialize database custom
dbExecute(conn = db, statement = "CREATE DATABASE IF NOT EXISTS custom;")

# Disconnect
dbDisconnect(db)

cat("\n---custom input database created...\n")

# ADD TABLE SCHEMA ######################################

# # Connect to newly made custom database
# db = connect("mariadb", "custom")
# # Read SQL file with commands to initialize each table
# sql = readLines("scripts/CreateDefault.sql")
# # Reformat into a vector
# sql = paste0(unlist(strsplit(paste0(sql, collapse = "\n"), ';')), ";")
# # Initialize each table
# for(i in 1:length(sql)){ dbExecute(conn = db, statement = sql[i]) }
# # Disconnect
# dbDisconnect(db)
# 
# cat("\n---custom input table schemas added...\n")

# q(save = "no") # close R, if needed
