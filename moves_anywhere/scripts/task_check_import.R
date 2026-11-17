# task_check_import.R ##########################################################
#
# What:      Check that a project run's link tables were loaded into the custom database
# Does:      Counts the data rows of each _<table>.csv (link, linksourcetypehour,
#            driveschedulesecondlink, offnetworklink, opmodedistribution) and the rows of
#            the table of the same name in the custom database; stops the run on a difference.
#            ant dbimporter reports success even when a table fails to load.
# Called by: task_importer.sh, after the importer (project runs only)
# Reads:     /cat/inputs/_<table>.csv, database custom
# Writes:    /cat/run/stop_reason (on a difference, if /cat/run exists)
# Exits:     1 if any table has a different number of rows in the database than in its file
# Needs:     catr, DBI, readr
###############################################################################

# 1. The comparison ####
tables_checked = c("link", "linksourcetypehour", "driveschedulesecondlink",
                   "offnetworklink", "opmodedistribution")

#' Compare row counts of the files with those of the database tables
#' @param counts_file named integer vector: rows of each input file
#' @param counts_db named integer vector: rows of each database table (same names)
#' @return "" if all agree, else the message for the first difference
check_import = function(counts_file, counts_db){
  for(tbl in names(counts_file)){
    n_db = if(tbl %in% names(counts_db)){ counts_db[[tbl]] } else { 0L }
    if(is.null(n_db) || is.na(n_db)){ n_db = 0L }
    if(n_db != counts_file[[tbl]]){
      return(paste0("project import failed: ", tbl, " has ", n_db,
                    " rows, expected ", counts_file[[tbl]]))
    }
  }
  return("")
}

# 2. Count and compare (skipped when a test sources this file) ####
if(!exists("CHECK_IMPORT_TEST")){
  setwd("/cat")
  library(catr, warn.conflicts = FALSE, quietly = TRUE)
  library(DBI, warn.conflicts = FALSE, quietly = TRUE)
  
  counts_file = c()
  for(tbl in tables_checked){
    path = paste0("inputs/_", tbl, ".csv")
    if(file.exists(path)){
      counts_file[[tbl]] = nrow(readr::read_csv(path, show_col_types = FALSE, progress = FALSE))
    }
  }
  
  db = catr::connect("mariadb", "custom")
  counts_db = c()
  for(tbl in names(counts_file)){
    counts_db[[tbl]] = tryCatch(
      as.integer(DBI::dbGetQuery(db, paste0("select count(*) as n from ", tbl))$n[1]),
      error = function(e){ 0L })
  }
  try(DBI::dbDisconnect(db), silent = TRUE)
  
  msg = check_import(counts_file, counts_db)
  if(msg != ""){
    if(dir.exists("/cat/run")){ writeLines(msg, "/cat/run/stop_reason", sep = "") }
    message(msg)
    quit(save = "no", status = 1)
  }
  for(tbl in names(counts_file)){
    cat("---project import checked: ", tbl, " ", counts_file[[tbl]], " rows\n", sep = "")
  }
  quit(save = "no", status = 0)
}
