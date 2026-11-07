# task_test_db.sh #############################################################
#
# What:      R code to test database contents
# Does:      Connects to movesdb20241112 and disconnects, then counts the distinct sourceTypeID
#            values in hourvmtfraction in the custom database.
# Called by: Developer tool: test database contents. Not part of a run; launch.sh does not run it.
# Reads:     MariaDB databases movesdb20241112 and custom (table hourvmtfraction)
# Writes:    nothing
# Exits:     no exit codes set (R code kept in a .sh file; run it in an R session)
###############################################################################

library(dplyr)
library(dbplyr)
library(readr)
library(catr)
library(DBI)
library(RMariaDB)

db = catr::connect("mariadb", "movesdb20241112")
dbDisconnect(db)

db = catr::connect("mariadb", "custom")
db %>% tbl("hourvmtfraction") %>%  select(sourceTypeID)  %>% distinct() %>% count()
