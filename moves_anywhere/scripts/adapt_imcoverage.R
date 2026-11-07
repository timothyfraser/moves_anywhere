# adapt_imcoverage.R ##########################################################
#
# What:      adapt I/M coverage table
# Does:      Uses a custom inputs/imcoverage.csv if provided; otherwise takes the default
#            imcoverage rows for the runspec's county and year.
# Called by: task_adapt.R, step 6 of launch.sh
# Reads:     EPA_MOVES_Model/rs_custom.xml (runspec); inputs/imcoverage.csv if provided,
#            otherwise the imcoverage table in the runspec's default database (MariaDB)
# Writes:    inputs/_imcoverage.csv
# Needs:     adapt_functions.R (get_changes, get_is_custom, get_data, import_table); catr, DBI, RMariaDB, dplyr, stringr
###############################################################################

#' Adapt the imcoverage table
#' @param .runspec path to the run's runspec (XML)
adapt_imcoverage = function(.runspec = "EPA_MOVES_Model/rs_custom.xml"){
  
  ### imcoverage #################################
  table = "imcoverage"
  BUCKET = "inputs"
  
  # Get your list of key values from your runspec
  rs = catr::translate_rs(.runspec = .runspec)
  # Get name of custom input database
  .custom = rs$defaultdbname
  .year = rs$year
  .geoid = rs$geoid
  .geoidchar = stringr::str_pad(.geoid, width = 5, side = "left", pad = "0")
  
  # Get files for my bucket
  files = get_changes(BUCKET)
  
  # Classify that table as valid or not
  f = get_is_custom(files, table = table)   
  
  
  if(!table %in% files$changed){
    custom = connect("mariadb", .custom)
    # Download and filter the table
    data = custom %>% tbl("imcoverage") %>% 
      filter(countyID %in% !!.geoid, 
             yearID %in% !!.year) %>%
      collect()
    dbDisconnect(custom)
    # Import table!
    import_table(data = data, tablename = table, .custom = .custom, adapt = TRUE, save = TRUE, volume = BUCKET)
    # IF CUSTOMIZED
  }else if(table %in% files$changed){
    # Classify that table as valid or not
    f = get_is_custom(files, table = table)
    # Load data from file
    data = get_data(changes = f$changes, .geoidchar = .geoidchar)
    # get_names(table = "imcoverage")
    data = data %>% 
      select(
        "polProcessID" = "polprocessid",
        "stateID" = "stateid",
        "countyID" = "countyid",
        "yearID" = "yearid",
        "sourceTypeID" = "sourcetypeid",
        "fuelTypeID" = "fueltypeid",
        "IMProgramID" = "improgramid",
        "begModelYearID" = "begmodelyearid",
        "endModelYearID" = "endmodelyearid",
        "inspectFreq" = "inspectfreq",
        "testStandardsID" = "teststandardsid",
        "useIMyn" = "useimyn",
        "complianceFactor" = "compliancefactor"
      )
    # Import the table
    import_table(data = data, tablename = f$changed, .custom = .custom, adapt = FALSE, save = TRUE, volume = BUCKET)
  }
}